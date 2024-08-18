// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Math} from "openzeppelin/utils/math/Math.sol";
import {ERC721} from "openzeppelin/token/ERC721/ERC721.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

import {Errors} from "./libraries/Errors.sol";
import {Black76} from "./external/Black76.sol";
import {Encoding} from "./external/Encoding.sol";
import {TStorage} from "./libraries/TStorage.sol";
import {DecimalMath} from "./external/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "./external/decimals/SignedDecimalMath.sol";
import {ReentrancyGuardTransient} from "./libraries/ReentrancyGuardTransient.sol";

import {IReceiver} from "./interfaces/IReceiver.sol";
import {ISpotOracle} from "./oracle/interfaces/ISpotOracle.sol";
import {IForwardOracle} from "./oracle/interfaces/IForwardOracle.sol";
import {IVolatilityOracle} from "./oracle/interfaces/IVolatilityOracle.sol";

import {IHub} from "./interfaces/IHub.sol";
import {IAsset} from "./interfaces/IAsset.sol";
import {IUSDX} from "./interfaces/IUSDX.sol";
import {IOption} from "./interfaces/IOption.sol";

import {ILiquidation} from "./interfaces/ILiquidation.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

import {ManagerStorage} from "./ManagerStorage.sol";

/// @title Position Manager
/// @notice Manages the asset transfer, margin evaluation and liquidations.
contract PositionManager is IPositionManager, ManagerStorage, ERC721, Ownable2Step, ReentrancyGuardTransient {
    using SignedDecimalMath for int256;
    using DecimalMath for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using TStorage for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _hub Address of the Hub contract which acts as the central point for interaction with other components
    /// @param _usdx Address of the USDX contract representing the synthetic stablecoin used within the platform
    /// @param _option Address of the Option contract managing options trading
    /// @param _liquidation Address of the Liquidation contract handling liquidation processes
    /// @param _operator authorized operator address
    /// @param _name ERC721 token name
    /// @param _symbol ERC721 token decimal
    constructor(
        IHub _hub,
        IUSDX _usdx,
        IOption _option,
        ILiquidation _liquidation,
        address _operator,
        string memory _name,
        string memory _symbol
    ) ERC721(_name, _symbol) {
        hub = _hub;
        usdx = _usdx;
        option = _option;
        liquidation = _liquidation;
        operator = _operator;
    }

    /// @notice Handles batch transfers of assets between sub-accounts
    /// @param transfers An array of asset transfers
    /// @param preData Additional data used for managing the transfer
    /// @return txId The transaction ID assigned to this batch of transfers
    function batchTransfers(IAsset.BalanceTransfer[] calldata transfers, bytes calldata preData)
        external
        nonReentrant
        onlyExecutor
        returns (uint256 txId)
    {
        txId = hub.incrementTxId();

        uint256 count;
        uint256[] memory uniqueAccounts = new uint256[](transfers.length * 2);

        for (uint256 i; i < transfers.length; ++i) {
            if ((transfers[i].from == 0 && transfers[i].to == 0) || transfers[i].amount == 0) continue;

            // transfer asset
            (uint64 fromFee, uint64 toFee) = _transferAsset(transfers[i], txId);

            /// For saving gas, we use bitmap to store every sub-acccount transfer info
            ///
            /// (1) uniqueFlag       1bit    : Mark this sub-account has been accessed
            /// (2) decreaseUSD       1bit    : Mark the USD balance of this sub-account is decreasing
            /// (3) ShortPosition      1bit    : This sub-account has a short position
            /// (4) OIFee             64bits  : The open interest fee for per transfer
            /// ( )                   189bits : Zero-bits
            ///
            /// ========================================================================================
            ///
            /// The bitmap pattern is :
            ///
            ///          (  )              (4)            (3)             (2)              (1)
            ///     <-- 189 bits --> <-- 64 bits --> <-- 1 bit -->   <-- 1 bit -->  <-- 1 bit -->
            ///         Zeros            OIFee       ShortPosition    decreaseUSD     uniqueFlag
            ///
            ///     <--- most significant bit               least significant bit --->

            uint256 fromSlot = uint256(keccak256(abi.encode(TRANSIENT_SUB_TYPE_HASH, transfers[i].from)));
            uint256 toSlot = uint256(keccak256(abi.encode(TRANSIENT_SUB_TYPE_HASH, transfers[i].to)));
            (uint256 fromBitMap, uint256 toBitMap) = (fromSlot.tload(), toSlot.tload());

            if (fromBitMap == 0) {
                fromSlot.tstore(1);
                // update local bitmap to saving gas, don't need to use 'tload' opcode to load latest bitmap if the bitmap will be used later
                fromBitMap = 1;
                uniqueAccounts[count++] = transfers[i].from;
            }

            if (toBitMap == 0) {
                toSlot.tstore(1);
                toBitMap = 1;
                uniqueAccounts[count++] = transfers[i].to;
            }

            fromFee += (fromBitMap >> 3 & type(uint64).max).toUint64();
            toFee += (toBitMap >> 3 & type(uint64).max).toUint64();

            if (transfers[i].amount > 0) {
                fromBitMap = transfers[i].asset == usdx
                    ? _bitMap(1, 1, 1) // mark decrease usd flag and short position flag
                    : _bitMap(1, 1, (fromBitMap >> 2) & 1); // mark short position flag
            } else {
                toBitMap = transfers[i].asset == usdx
                    ? _bitMap(1, 1, 1) // mark decrease usdx flag and short position flag
                    : _bitMap(1, 1, (toBitMap >> 2) & 1); // mark short position flag
            }

            fromSlot.tstore(fromBitMap | fromFee << 3);
            toSlot.tstore(toBitMap | toFee << 3);
        }

        // As long as the sub-account has negative cash or short option positions, it needs to evaluate margin
        for (uint256 i; i < count; i++) {
            uint256 _slot = uint256(keccak256(abi.encode(TRANSIENT_SUB_TYPE_HASH, uniqueAccounts[i])));
            uint256 bitMap = _slot.tload();

            if ((bitMap >> 1) & 1 == 1) {
                _evaluateMargin(
                    txId,
                    uniqueAccounts[i],
                    (bitMap >> 2) & 1 == 1, // decrease usdx flag
                    (bitMap >> 3).toUint64(), // OI Fee
                    msg.sender,
                    preData
                );
            }
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    EVALUATE MARGIN 
    //////////////////////////////////////////////////////////////////////////*/

    function evaluateMargin(
        uint256 txId,
        uint256 subAccount,
        bool decreaseUSD,
        uint64 oiFee,
        address caller,
        bytes calldata preData
    ) public nonReentrant {
        if (msg.sender != address(usdx)) {
            revert Errors.OnlyProtocol();
        }

        _evaluateMargin(txId, subAccount, decreaseUSD, oiFee, caller, preData);
    }

    /// @notice Adjusts user account balances and performs risk scanning
    /// @param txId Transaction ID for which the adjustment is being made
    /// @param subAccount ID of the sub-account undergoing adjustment
    /// @param decreaseUSD Boolean indicating whether USD balance should be decreased
    /// @param oiFee Open interest fee applicable to the transaction
    /// @param caller Address of the entity calling this function
    /// @param preData Additional data related to the transaction
    function _evaluateMargin(
        uint256 txId,
        uint256 subAccount,
        bool decreaseUSD,
        uint64 oiFee,
        address caller,
        bytes calldata preData
    ) internal {
        int256 usdBalance = usdx.balances(subAccount);
        if (decreaseUSD && usdBalance < 0) revert Errors.NegativeUSD();

        // If a user is in liquidation state, usdx balance after adjustment must be > 0, otherwise, the account can only enter 'takeover' stage
        if (liquidation.liquidatedAccounts(subAccount) && usdBalance > 0) return;

        _preEvaluate(subAccount, txId, caller, oiFee, preData);

        (int256 postMargin,) =
            _calcTotalMarginAndMTM(option.getAccountBalance(subAccount), usdBalance, !mmCallerAccounts[caller]);

        if (postMargin < 0) revert Errors.NegativeMargin();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    MARGIN CALCULATION LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Calculates the total margin and market value for a portfolio
    /// @param assetBalances Array of asset balances
    /// @param usdBalance USD balance of the account
    /// @param isIM Boolean indicating if this is the initial calculation
    /// @return portfolioMargin Total margin of the portfolio
    /// @return portfolioMarketValue Total market value of the portfolio
    function _calcTotalMarginAndMTM(IAsset.AssetBalance[] memory assetBalances, int256 usdBalance, bool isIM)
        internal
        returns (int256 portfolioMargin, int256 portfolioMarketValue)
    {
        for (uint256 i = 0; i < assetBalances.length; i++) {
            (uint256 marketId, uint256 expiry, uint256 strike, bool isCall) = Encoding.fromSubId(assetBalances[i].subId);
            uint256 marketSlot = uint256(keccak256(abi.encode(TRANSIENT_MKT_TYPE_HASH, marketId)));

            // Saving gas for store same market spot price in transient storage
            if (marketSlot.tload() == 0) {
                marketSlot.tstore(spotOracles[marketId].getSpot());
            }

            // Same expiry position can have different strike price
            uint256 expirySlot = uint256(keccak256(abi.encode(TRANSIENT_EXP_TYPE_HASH, marketId, expiry)));

            if (expirySlot.tload() == 0) {
                expirySlot.tstore(_getForwardPrice(marketId, expiry));
            }

            Option memory position = Option({strike: strike, balance: assetBalances[i].balance, isCall: isCall});

            (int256 margin, int256 markToMarket) =
                _calcOptionMargin(isIM, marketId, expiry, marketSlot.tload(), expirySlot.tload(), position);

            portfolioMargin += margin;
            portfolioMarketValue += markToMarket;
        }

        if (isIM) {
            /**
             * Depeg Margin = max(0, USDC_THRESHOLD - USDC Value) * DEPEG_FACTOR *  IM
             *
             */
            uint256 stablePrice = stableOracle.getSpot();
            uint256 depegMultiplier = stablePrice >= depegParams.threshold
                ? 0
                : (depegParams.threshold - stablePrice).multiplyDecimal(depegParams.depegFactor);

            portfolioMargin += portfolioMargin.multiplyDecimal(depegMultiplier.toInt256());
        }

        portfolioMarketValue += usdBalance;
        portfolioMargin += usdBalance;
    }

    /// @notice Calculates the margin requirements for an option position
    /// @param isIM Boolean flag indicating whether the calculation is for initial margin (true) or maintenance margin (false)
    /// @param marketId The market ID for which the margin is being calculated
    /// @param expiry The expiry time of the option
    /// @param spotPrice Current spot price of the underlying asset
    /// @param forwardPrice Forward price of the underlying asset at the option's expiry
    /// @param optionPos Struct containing the option position details such as strike price and balance
    /// @return margin Required margin for the position
    /// @return marketValue Market value of the position
    function _calcOptionMargin(
        bool isIM,
        uint256 marketId,
        uint256 expiry,
        uint256 spotPrice,
        uint256 forwardPrice,
        Option memory optionPos
    ) internal view returns (int256 margin, int256 marketValue) {
        uint256 markPrice;
        {
            // Note: long position doesn't have any "margin", can't be used to offset other positions
            if (optionPos.balance > 0) return (0, marketValue);

            uint256 vol = volOracles[marketId].getVol(uint128(optionPos.strike), uint64(expiry));

            markPrice = _calcBSMPrice(forwardPrice, optionPos.strike, expiry, vol, optionPos.isCall);
            marketValue = markPrice.toInt256().multiplyDecimal(optionPos.balance);
        }

        if (optionPos.isCall) {
            margin = _calcShortCallMargin(
                marketId, markPrice, optionPos.strike, optionPos.balance, spotPrice, forwardPrice, isIM
            );
        } else {
            margin = _calcShortPutMargin(
                marketId, markPrice, optionPos.strike, optionPos.balance, spotPrice, forwardPrice, isIM
            );
        }
    }

    /// @notice Calculate the margin requirement for a short call option
    /// @dev This function is called only for short call positions to determine the necessary margin to hold the position
    /// @param marketId The market ID of the option being evaluated
    /// @param markPrice The current market price of the option
    /// @param strike The strike price of the option
    /// @param amount The amount (quantity) of the option being evaluated
    /// @param spotPrice The current spot price of the underlying asset
    /// @param forwardPrice The forward price of the underlying asset at the time of the option's expiry
    /// @param isIM Boolean indicating whether the calculation is for initial margin requirements
    /// @return margin The calculated margin required to hold the short call position
    function _calcShortCallMargin(
        uint256 marketId,
        uint256 markPrice,
        uint256 strike,
        int256 amount,
        uint256 spotPrice,
        uint256 forwardPrice,
        bool isIM
    ) internal view returns (int256) {
        MarginParams memory params = marginParams[marketId];

        /**
         * MM = (0.1 * Spot + Mark Price) * amount
         *
         * 1: 0.1 is constant coefficient
         */
        if (!isIM) {
            return amount.multiplyDecimal((params.MMRatio.multiplyDecimal(spotPrice).toInt256() + markPrice.toInt256()));
        }

        /**
         * IM = n * (max(0.2 - OTM Amount / Underlying Mark Price, 0.13) * Spot Price + Mark Price of the Option)
         * Note: We replace spot price by forward price (underlying mark price)
         *
         * 1: OTM Amount = Maximum(Strike Price - Underlying Mark Price, 0)
         * 2: 0.2 can be in [0.15, 0.2] range
         * 3: Underlying Mark Price: forward price
         */
        uint256 otmRatio = strike > forwardPrice ? (strike - forwardPrice).divideDecimal(forwardPrice) : 0;

        return (
            amount.multiplyDecimal(
                // cast to int256 for avoid overflow
                SignedMath.max(params.IMUpperRatio.toInt256() - otmRatio.toInt256(), params.IMLowerRatio.toInt256())
                    .multiplyDecimal(spotPrice.toInt256()) + markPrice.toInt256()
            )
        );
    }

    /// @notice Calculate short put option margin requirement
    function _calcShortPutMargin(
        uint256 marketId,
        uint256 markPrice,
        uint256 strike,
        int256 amount,
        uint256 spotPrice,
        uint256 forwardPrice,
        bool isIM
    ) internal view returns (int256 margin) {
        MarginParams memory params = marginParams[marketId];

        /**
         * MM =  n * (0.1 * Minimum(Spot Price, Strike Price) + Mark Price of the Option)
         * 1: 0.1 is contant coefficient
         */
        if (!isIM) {
            return amount.multiplyDecimal(
                (params.MMRatio.multiplyDecimal(Math.min(spotPrice, strike)) + markPrice).toInt256()
            );
        }

        /**
         * IM = n * (Maximum ((0.2 - OTM Amount / Underlying Mark Price) * spot price, 0.13 * strike price) + Mark Price of the Option)
         *
         * 1: OTM Amount = Maximum(Underlying Mark Price - Strike Price, 0)
         * 2: 0.2 can be in [0.15, 0.2] range
         * 3: Underlying Mark Price: forward price
         */
        uint256 otmRatio = forwardPrice > strike ? (forwardPrice - strike).divideDecimal(forwardPrice) : 0;

        return (
            amount.multiplyDecimal(
                SignedMath.max(
                    (params.IMUpperRatio.toInt256() - otmRatio.toInt256()).multiplyDecimal(spotPrice.toInt256()),
                    params.IMLowerRatio.multiplyDecimal(strike).toInt256()
                ) + markPrice.toInt256()
            )
        );
    }

    /// @dev Internal function to calculate option prices using the Black-Scholes-Merton model
    /// @param forwardPrice The projected future price of the underlying asset at the option's expiry
    /// @param strike The strike price of the option
    /// @param expiry The time to expiry of the option in seconds
    /// @param vol The volatility of the underlying asset
    /// @param isCall Boolean indicating if the option is a call (true) or a put (false)
    /// @return price The calculated option price
    function _calcBSMPrice(uint256 forwardPrice, uint256 strike, uint256 expiry, uint256 vol, bool isCall)
        internal
        view
        returns (uint256)
    {
        uint64 secToExpiry = expiry > block.timestamp ? uint64(expiry - block.timestamp) : 0;

        (uint256 call, uint256 put) = Black76.prices(
            Black76.Black76Inputs({
                timeToExpirySec: secToExpiry,
                volatility: vol.toUint128(),
                fwdPrice: forwardPrice.toUint128(),
                strikePrice: strike.toUint128(),
                discount: discount
            })
        );

        return isCall ? call : put;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                    EXERCISE OPTION
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Exercise all expired options for a specified account
    /// @dev This function settles all expired options for an account, calculating payoffs and adjusting balances as necessary
    /// @param accountId The ID of the account for which to exercise options
    function exercise(uint256 accountId) external {
        IAsset.AssetBalance[] memory balances = option.getAccountBalance(accountId);
        int256 usdDelta;

        for (uint256 i; i < balances.length; i++) {
            // Calculate the payoff for each option, if it is exercisable
            (int256 value, bool exercised) = option.calculatePayOff(balances[i].subId, balances[i].balance);
            // Skip if the option is not exercisable
            if (!exercised) continue;

            usdDelta += value;

            // Adjust the option balance to zero after exercise
            option.updateBalance(
                IAsset.BalanceAdjustment(accountId, option, balances[i].subId, -(balances[i].balance)),
                hub.incrementTxId()
            );

            emit OptionExercised(accountId, balances[i].subId, balances[i].balance, value);
        }

        // Update the USDX balance
        usdx.updateBalance(IAsset.BalanceAdjustment(accountId, usdx, 0, usdDelta), hub.incrementTxId());

        // Update temporary supply, otherwise the totalsupply will change
        usdx.updateTemporarySupply(usdDelta);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     LIQUIDATION LOGIC
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Liquidator transfers all positions (including usd) of the liquidated user to the sub-account of insurance fund
    function takeover(uint256 liquidateeId) external onlyLiquidator {
        if (!liquidation.liquidatedAccounts(liquidateeId)) revert Errors.NotLiquidatedAccount();

        IAsset.AssetBalance[] memory assets = option.getAccountBalance(liquidateeId);

        // transfer all opened positions to liquidator
        for (uint256 i; i < assets.length; i++) {
            _transfer(liquidateeId, feeRecipient, option, uint112(assets[i].subId), (assets[i].balance));

            emit TakeOver(feeRecipient, liquidateeId, assets[i].subId, assets[i].balance);
        }

        // transfer usd to liquidator
        int256 usdBalance = usdx.balances(liquidateeId);
        _transfer(liquidateeId, feeRecipient, usdx, 0, usdBalance);

        emit TakeOver(feeRecipient, liquidateeId, 0, usdBalance);
    }

    /// @notice Automatically deleverages the most profitable traders by closing their positions at the current market price
    /// @dev This function is used by liquidators to reduce the size of large, profitable positions in the event of market instability or a liquidation scenario
    /// @param transfers An array of liquidation transfer details, containing information about the positions to be deleveraged
    function autoDeleverage(ILiquidation.LiquidationTransfer[] calldata transfers) external onlyLiquidator {
        for (uint256 i; i < transfers.length; i++) {
            // skip usdx position
            if (transfers[i].subId == 0) continue;

            {
                (int256 counterBalance, int256 insuranceBalance) = (
                    option.getPositionBalance(transfers[i].counterParty, transfers[i].subId),
                    option.getPositionBalance(feeRecipient, transfers[i].subId)
                );

                if (counterBalance == 0 || insuranceBalance == 0) revert Errors.NotExistPosition();

                // neither the insurance fund nor the counterparty can increase their positions
                if (
                    (counterBalance * transfers[i].amount < 0) // before balance * (-delta) > 0
                        || (insuranceBalance * transfers[i].amount > 0) // before balance * (+delta) > 0
                        || (counterBalance * (counterBalance - transfers[i].amount) < 0) // before balance * after balance < 0
                        || (insuranceBalance * (insuranceBalance + transfers[i].amount) < 0)
                ) {
                    revert Errors.CannotIncreasePosition();
                }
            }

            (uint256 marketId, uint256 expiry, uint256 strike, bool isCall) = Encoding.fromSubId(transfers[i].subId);

            uint256 expirySlot = uint256(keccak256(abi.encode(TRANSIENT_EXP_TYPE_HASH, marketId, expiry)));

            if (expirySlot.tload() == 0) {
                expirySlot.tstore(_getForwardPrice(marketId, expiry));
            }

            uint256 markPrice = _calcBSMPrice(
                expirySlot.tload(), strike, expiry, volOracles[marketId].getVol(uint128(strike), uint64(expiry)), isCall
            );

            int256 marketValue = markPrice.toInt256().multiplyDecimal(transfers[i].amount);

            // 1: transfer option position
            _transfer(transfers[i].counterParty, feeRecipient, option, transfers[i].subId, transfers[i].amount);

            // 2: transfer usdx
            _transfer(feeRecipient, transfers[i].counterParty, usdx, 0, marketValue);

            // double check counterParty mm margin
            (int256 availableMargin,) = getTotalMarginAndMarketValue(transfers[i].counterParty, false);

            if (availableMargin < 0) revert Errors.NegativeMargin();

            emit AutoDeleverage(
                transfers[i].counterParty, feeRecipient, transfers[i].subId, transfers[i].amount, marketValue
            );
        }
    }

    /*//////////////////////////////////////////////////////////////////////////
                                VIEWER FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Returns the total margin and market value for a sub-account
    /// @dev Calculates the aggregate margin and market value across all positions held by an account
    /// @param accountId The ID of the account for which to calculate margin and market value
    /// @param isIM Boolean indicating whether to use initial margin requirements in the calculation
    /// @return totalMargin The total margin required across all positions for the account
    /// @return totalMarketValue The total market value of all positions held by the account
    function getTotalMarginAndMarketValue(uint256 accountId, bool isIM) public returns (int256, int256) {
        return _calcTotalMarginAndMTM(option.getAccountBalance(accountId), usdx.balances(accountId), isIM);
    }

    /// @notice Retrieves the margin requirement and market value for a specific option position
    /// @param marketId The market ID of the option
    /// @param strike The strike price of the option
    /// @param expiry The expiration time of the option
    /// @param isCall Boolean indicating if the option is a call
    /// @param balance The balance of the option position
    /// @param isIM Boolean indicating if the calculation is for the initial margin
    /// @return margin The required margin for the position
    /// @return marketValue The current market value of the position
    function getMarginAndMarketValue(
        uint256 marketId,
        uint256 strike,
        uint256 expiry,
        bool isCall,
        int256 balance,
        bool isIM
    ) external view returns (int256 margin, int256 marketValue) {
        uint256 spotPrice = spotOracles[marketId].getSpot();
        uint256 forwardPrice = _getForwardPrice(marketId, expiry);
        Option memory optionPos = Option({strike: strike, isCall: isCall, balance: balance});
        return _calcOptionMargin(isIM, marketId, expiry, spotPrice, forwardPrice, optionPos);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                OPERATION FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Update the authorzied operator address
    /// @param _newOperator Address of the liquidator to be updated
    function setOperator(address _newOperator) external onlyOwner {
        if (_newOperator == address(0)) revert Errors.ZeroAddress();
        operator = _newOperator;

        emit OperatorSet(_newOperator);
    }

    /// @notice Update the list of addresses authorized for liquidation-related transactions
    /// @param _liquidator Address of the liquidator to be updated
    /// @param _trusted Boolean indicating whether the liquidator is authorized
    function setLiquidator(address _liquidator, bool _trusted) external onlyOperator {
        if (_liquidator == address(0)) revert Errors.ZeroAddress();
        trustedLiquidator[_liquidator] = _trusted;

        emit LiquidatorSet(_liquidator, _trusted);
    }

    /// @notice Update the addresses authorized for submitTransfer transactions
    /// @param _executor Address of the executor to be updated
    /// @param _trusted Boolean indicating whether the executor is authorized
    function setExecutor(address _executor, bool _trusted) external onlyOperator {
        if (_executor == address(0)) revert Errors.ZeroAddress();
        trustedExecutor[_executor] = _trusted;

        emit ExecutorSet(_executor, _trusted);
    }

    /// @notice Set the annualized discount rate used in Black-Scholes-Merton pricing
    /// @param _discount New discount rate to set, where 1e18 represents no discount
    function setDiscount(uint64 _discount) external onlyOperator {
        if (_discount > UNIT) {
            revert Errors.InvalidDiscount();
        }

        discount = _discount;

        emit DiscountSet(discount);
    }

    /// @notice Set the pricing oracles for a given market
    /// @param marketId The market ID to associate the oracles with
    /// @param spotOracle Address of the spot price oracle
    /// @param forwardOracle Address of the forward price oracle
    /// @param volOracle Address of the volatility oracle
    function setMarketOracles(
        uint256 marketId,
        ISpotOracle spotOracle,
        IForwardOracle forwardOracle,
        IVolatilityOracle volOracle
    ) external onlyOperator {
        isMarketExist(marketId);

        spotOracles[marketId] = spotOracle;
        forwardOracles[marketId] = forwardOracle;
        volOracles[marketId] = volOracle;

        emit OraclesSet(marketId, address(spotOracle), address(forwardOracle), address(volOracle));
    }

    /// @notice Set the oracle for stablecoin pricing
    /// @param _stableOracle Address of the new stablecoin price oracle
    function setStableOracle(ISpotOracle _stableOracle) external onlyOperator {
        stableOracle = _stableOracle;

        emit StableOracleSet(address(_stableOracle));
    }

    /// @notice Update the margin parameters for a market
    /// @param marketId The market ID to update parameters for
    /// @param params Struct containing new margin parameters such as maintenance and initial margin ratios
    function setMarginParams(uint256 marketId, MarginParams calldata params) external onlyOperator {
        isMarketExist(marketId);

        if (params.IMUpperRatio > UNIT || params.IMLowerRatio > UNIT || params.MMRatio > UNIT) {
            revert Errors.InvalidMarginParams();
        }

        marginParams[marketId] = params;

        emit MarginParamsSet(marketId, params.IMUpperRatio, params.IMLowerRatio, params.MMRatio);
    }

    /// @notice Set the parameters for handling stablecoin de-pegging scenarios
    /// @param params Struct containing depegging thresholds and factors
    function setDepegParams(DepegParams calldata params) external onlyOperator {
        if (params.threshold > UNIT || params.depegFactor > 3 * UNIT) revert Errors.InvalidDepegParams();
        depegParams = params;

        emit DepegParamsSet(params.threshold, params.depegFactor);
    }

    /// @notice Designate a fee recipient sub-account
    /// @param _newRecipient The new sub-account ID to be set as the fee recipient
    function setFeeRecipient(uint256 _newRecipient) external onlyOperator {
        // ensure it's a valid sub-account
        ownerOf(_newRecipient);

        feeRecipient = _newRecipient;
        emit FeeRecipientSet(_newRecipient);
    }

    /// @notice Set whether certain callers can bypass open interest fees
    /// @param caller The address of the caller
    /// @param exempted Boolean indicating whether the caller can bypass the fees
    function setFeeExemption(address caller, bool exempted) external onlyOperator {
        feeExemption[caller] = exempted;

        emit FeeExemptionSet(caller, exempted);
    }

    /// @notice Add or remove an address which can receive data before evaluate margin
    /// @param receiver The data reciever address
    /// @param authorized Boolean indicating whether the address is authorized
    function setDataReceiver(address receiver, bool authorized) external onlyOperator {
        dataReceiver[receiver] = authorized;

        emit DataReceiverSet(receiver, authorized);
    }

    /// @notice Add or remove an address from the whitelist of authorized risk  assessors
    /// @param caller The address of the risk assessor to update
    /// @param trusted Boolean flag indicating whether the assessor is trusted
    function setMaintenanceMarginCaller(address caller, bool trusted) external onlyOperator {
        mmCallerAccounts[caller] = trusted;

        emit MaintenanceMarginCallerSet(caller, trusted);
    }

    /// @notice Creates a new sub-account and mints a new ERC721 token to represent it
    /// @param owner The owner of the new sub-account
    /// @return subAccount The newly created sub-account ID
    function createSubAccount(address owner) external onlyExecutor returns (uint256 subAccount) {
        _mint(owner, (subAccount = ++lastSubAccount));
        emit AccountCreated(owner, subAccount);
    }

    /// @notice Create a new market within the system
    /// @param _marketName The name of the market to be created
    /// @return marketId The ID of the newly created market
    function createMarket(string calldata _marketName) external onlyOperator returns (uint256 marketId) {
        marketId = ++lastMarketId;

        emit MarketCreated(marketId, _marketName);
    }

    /// @notice Check whether a given market ID exists
    /// @param marketId The market ID to check
    function isMarketExist(uint256 marketId) public view {
        if (marketId > lastMarketId) revert Errors.NotExistMarket();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Internal function to handle asset transfers between accounts
    /// @param transfer The transfer details
    /// @param txId Transaction ID for the operation
    /// @return fromOIFee The fee for the sender
    /// @return toOIFee The fee for the receiver
    function _transferAsset(IAsset.BalanceTransfer calldata transfer, uint256 txId)
        internal
        returns (uint64 fromOIFee, uint64 toOIFee)
    {
        if (transfer.from == transfer.to) {
            revert Errors.SelfTransfer(msg.sender, transfer.from);
        }

        // positive cash transfer skip owner check, option transfer always need owner check
        bool fromSkipCheck = transfer.subId == 0 ? transfer.amount > 0 ? false : true : false;
        bool toSkipCheck = transfer.subId == 0 ? transfer.amount < 0 ? false : true : false;

        if (
            (!fromSkipCheck && !_isApprovedOrOwner(msg.sender, transfer.from))
                || (!toSkipCheck && !_isApprovedOrOwner(msg.sender, transfer.to))
        ) {
            revert Errors.OnlyAccountOwner();
        }

        IAsset.BalanceAdjustment memory fromAdjustment = IAsset.BalanceAdjustment({
            accountId: transfer.from,
            asset: transfer.asset,
            subId: transfer.subId,
            amount: -transfer.amount
        });

        IAsset.BalanceAdjustment memory toAdjustment = IAsset.BalanceAdjustment({
            accountId: transfer.to,
            asset: transfer.asset,
            subId: transfer.subId,
            amount: transfer.amount
        });

        (, fromOIFee) = IAsset(transfer.asset).updateBalance(fromAdjustment, txId);
        (, toOIFee) = IAsset(transfer.asset).updateBalance(toAdjustment, txId);

        emit BalanceTransferred(transfer.from, transfer.to, transfer.asset, transfer.subId, transfer.amount, txId);
    }

    /// @dev Performs pre-evaluate processing for account balance updates
    /// @param accountId The ID of the account undergoing adjustment
    /// @param txId The transaction ID associated with the adjustment
    /// @param caller  Address of the entity calling this function
    /// @param oiFee The open interest fee applied to the transaction
    /// @param preData extra data before adjusment
    function _preEvaluate(uint256 accountId, uint256 txId, address caller, uint256 oiFee, bytes calldata preData)
        internal
    {
        _receiveData(txId, preData);

        if (feeExemption[caller]) return;

        // charge open interest fee
        if (oiFee == 0 || feeRecipient == 0) return;
        _transfer(accountId, feeRecipient, usdx, 0, int256(oiFee));
    }

    /// @dev Transfers assets from one account to another without invoking margin assessment
    /// @param from Account ID from which the asset is being transferred
    /// @param to Account ID to which the asset is being transferred
    /// @param asset The asset contract interface
    /// @param subId The sub-ID of the asset to transfer
    /// @param amount The amount of the asset to transfer
    function _transfer(uint256 from, uint256 to, IAsset asset, uint112 subId, int256 amount) internal {
        // just skip, don't revert
        if (amount == 0) return;

        asset.updateBalance(IAsset.BalanceAdjustment(from, asset, subId, -amount), hub.incrementTxId());

        asset.updateBalance(IAsset.BalanceAdjustment(to, asset, subId, amount), hub.incrementTxId());
    }

    /// @dev Processes custom data for oracles or other external interfaces during transactions
    /// @param txId The transaction ID related to the data being processed
    /// @param preData Custom data provided during a transaction
    function _receiveData(uint256 txId, bytes calldata preData) internal {
        if (preData.length == 0 || lastTxId == txId) return;

        lastTxId = txId;

        // parse array of data and update each oracle or take action
        PreProcessData[] memory preDatas = abi.decode(preData, (PreProcessData[]));
        for (uint256 i; i < preDatas.length; i++) {
            // invoke some actions if needed
            if (!dataReceiver[preDatas[i].receiver]) revert Errors.UnauthorizedCall();
            IReceiver(preDatas[i].receiver).receiveData(preDatas[i].data);
        }
    }

    /// @dev Helper function to construct a bitmap for transfer flags
    /// @param uniqueFlag the account are marked once in batch transfers
    /// @param marginFlag Flag indicating if this is a margin-related transfer
    /// @param decreaseUSD Flag indicating if this transfer decreases USD balance
    /// @return The constructed bitmap
    function _bitMap(uint256 uniqueFlag, uint256 marginFlag, uint256 decreaseUSD) internal pure returns (uint256) {
        return uniqueFlag | marginFlag << 1 | decreaseUSD << 2;
    }

    /// @dev Fetches the forward price from an oracle for a specific market and expiry
    /// @param marketId The market ID for which the forward price is needed
    /// @param expiry The expiry date of the option for which the price is being fetched
    /// @return forwardPrice The forward price as provided by the oracle
    function _getForwardPrice(uint256 marketId, uint256 expiry) internal view returns (uint256 forwardPrice) {
        forwardPrice = forwardOracles[marketId].getForwardPrice(uint64(expiry));
        if (forwardPrice == 0) revert Errors.ZeroPrice();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                        MODIFIERS 
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Modifier to ensure only msg sender is authorized operator
    modifier onlyOperator() {
        if (msg.sender != operator) revert Errors.OnlyOperator();
        _;
    }

    /// @dev Modifier to ensure only authorized liquidators can perform liquidatioin actions
    modifier onlyLiquidator() {
        if (!trustedLiquidator[msg.sender]) revert Errors.OnlyLiquidator();
        _;
    }

    /// @dev Modifier to ensure only authorized executor can call related actions
    modifier onlyExecutor() {
        if (!trustedExecutor[msg.sender]) revert Errors.OnlyExecutor();
        _;
    }
}
