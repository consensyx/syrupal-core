// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

import {Errors} from "./libraries/Errors.sol";
import {Encoding} from "./external/Encoding.sol";
import {TStorage} from "./libraries/TStorage.sol";
import {UniqueArray} from "./libraries/UniqueArray.sol";
import {DecimalMath} from "./external/decimals/DecimalMath.sol";
import {SignedDecimalMath} from "./external/decimals/SignedDecimalMath.sol";

import {IHub} from "./interfaces/IHub.sol";
import {IOption} from "./interfaces/IOption.sol";
import {ILiquidation} from "./interfaces/ILiquidation.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";
import {IForwardOracle} from "./oracle/interfaces/IForwardOracle.sol";

/// @title Option Trading Contract
/// @dev This contract handles the creation and management of options for various markets.
/// It includes balance adjustments, position management, liquidation checks and calculating payoffs for expired options.
contract Option is IOption, Ownable2Step {
    using SafeCast for uint256;
    using SafeCast for int256;
    using TStorage for uint256;
    using DecimalMath for uint256;
    using UniqueArray for uint256[];
    using SignedDecimalMath for int256;

    /// @dev The Hub contract addres
    IHub public hub;

    /// @dev Position manager contract address
    IPositionManager public manager;

    /// @dev Liquidation contract address
    ILiquidation public liquidation;

    /// @dev Open interest fee rate in basis points (BPS)
    uint256 public OIFee;

    /// @dev The maximum allowed number of opened positions per sub-account
    uint64 internal constant MAX_OPEN_POSITIONS = 128;

    /// @dev Maps account IDs to their positions and their balances
    mapping(uint256 accountId => mapping(uint256 subId => IndexBalance)) internal balances;

    /// @dev Maps account IDs to lists of open position IDs
    mapping(uint256 accountId => uint256[]) internal positions;

    /// @dev Maps market IDs to their associated forward price oracles
    mapping(uint16 marketId => IForwardOracle) public forwardOracle;

    /// @dev Maps sub-IDs to their total open interest
    mapping(uint256 subId => uint256) public openInterest;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @notice Constructs the Option contract and initializes market settings
    /// @param _hub Reference to the Hub contract
    /// @param _manager Reference to the Position manager contract
    /// @param _liquidation Reference to the Liquidation contract
    constructor(IHub _hub, IPositionManager _manager, ILiquidation _liquidation) {
        hub = _hub;
        manager = _manager;
        liquidation = _liquidation;
    }

    /*//////////////////////////////////////////////////////////////////////////
                                  EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Update the balance of a specific asset and records transaction details
    /// @param adjustment Details of the balance adjustment
    /// @param txId Transaction ID for tracking
    /// @return postBalance Updated balance after adjustment
    /// @return oiFee Open interest fee calculated for the adjustment
    function updateBalance(BalanceAdjustment memory adjustment, uint256 txId)
        external
        returns (int256 postBalance, uint64 oiFee)
    {
        if (msg.sender != address(manager)) {
            revert Errors.OnlyProtocol();
        }

        hub.updateLastTxId(adjustment.accountId, txId);

        IndexBalance storage userBalance = balances[adjustment.accountId][adjustment.subId];
        int256 preBalance = userBalance.balance;

        (postBalance, oiFee) = _preUpdate(adjustment, txId, preBalance);

        // If the user under liquidation can't create any new positions
        if (
            liquidation.liquidatedAccounts(adjustment.accountId)
                && ((preBalance * postBalance < 0) || SignedMath.abs(postBalance) > SignedMath.abs(preBalance))
        ) {
            revert Errors.CannotIncreasePosition();
        }

        if (preBalance != 0 && postBalance == 0) {
            _removePosition(adjustment.accountId, userBalance.index);
        } else if (preBalance == 0 && postBalance != 0) {
            userBalance.index = _addPosition(adjustment.accountId, adjustment.subId).toUint16();
        }

        userBalance.balance = postBalance.toInt240();

        emit BalanceUpdated(adjustment.accountId, address(adjustment.asset), adjustment.amount, txId);
    }

    /// @notice Calculates the payoff for an expired option
    /// @param subId sub-account id
    /// @param balance The balance of the option
    /// @return profitLoss The profit or loss resulting from the option
    /// @return exercised True if the option was exercised, false otherwise
    function calculatePayOff(uint256 subId, int256 balance) external view returns (int256, bool) {
        (uint256 marketId, uint256 expiry, uint256 strike, bool isCall) = Encoding.fromSubId(subId.toUint112());

        if (expiry > block.timestamp) {
            return (0, false);
        }

        (bool exercised, uint256 settlePrice) = forwardOracle[uint16(marketId)].getSettlementPrice(uint64(expiry));
        if (!exercised) return (0, false);

        int256 diff = settlePrice.toInt256() - strike.toInt256();

        if (isCall && diff > 0) {
            // ITM CALL
            return (diff.multiplyDecimal(balance), true);
        } else if (!isCall && diff < 0) {
            // ITM PUT
            return (-diff.multiplyDecimal(balance), true);
        } else {
            // OTM
            return (0, true);
        }
    }

    /// @notice Sets the forward price oracle for a given market
    /// @param marketId The market identifier
    /// @param _forwardOracle The address of the forward oracle contract
    function setForwardOracle(uint16 marketId, address _forwardOracle) external onlyOwner {
        manager.isMarketExist(marketId);
        forwardOracle[marketId] = IForwardOracle(_forwardOracle);
        emit ForwardOracleSet(marketId, _forwardOracle);
    }

    /// @notice Sets the open interest fee rate
    /// @param _newOIFee The new open interest fee rate in basis points (BPS)
    function setOIFee(uint256 _newOIFee) external onlyOwner {
        if (_newOIFee > 1e18) revert Errors.InvalidOIFee();

        uint256 oldFee = OIFee;
        OIFee = _newOIFee;

        emit OIFeeSet(oldFee, _newOIFee);
    }

    /// @notice Retrieves the balance of all options held by a sub-account
    /// @param accountId The identifier of the account
    /// @return assetBalances Array of balances for each option held
    function getAccountBalance(uint256 accountId) external view returns (AssetBalance[] memory assetBalances) {
        uint256 optionLen = positions[accountId].length;
        assetBalances = new AssetBalance[](optionLen);

        for (uint256 i; i < optionLen; i++) {
            uint112 _subId = positions[accountId][i].toUint112();
            assetBalances[i] = AssetBalance({subId: _subId, balance: int256(balances[accountId][_subId].balance)});
        }
    }

    /// @notice Retrieves the balance of a specific option held by a sub-account
    /// @param accountId The identifier of the account
    /// @param subId The identifier of the position within the account
    /// @return balance The balance of the specified option
    function getPositionBalance(uint256 accountId, uint256 subId) external view returns (int256 balance) {
        return int256(balances[accountId][subId.toUint112()].balance);
    }

    /// @notice Encodes option details into a subId
    /// @param marketId The market identifier
    /// @param expiry The expiration date of the option
    /// @param strike The strike price of the option
    /// @param isCall True if the option is a call, false if it is a put
    /// @return subId The encoded subId representing the option
    function encodingSubId(uint256 marketId, uint256 expiry, uint256 strike, bool isCall)
        external
        pure
        returns (uint112 subId)
    {
        return Encoding.toSubId(marketId, expiry, strike, isCall);
    }

    /// @notice Decodes a subId into its component option details
    /// @param subId The encoded subId representing the option
    /// @return marketId The market identifier
    /// @return expiry The expiration date of the option
    /// @return strike The strike price of the option
    /// @return isCall True if the option is a call, false if it is a put
    function decodingSubId(uint112 subId)
        external
        pure
        returns (uint256 marketId, uint256 expiry, uint256 strike, bool isCall)
    {
        return Encoding.fromSubId(subId);
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Pre-update logic to handle open interest and position tracking before making balance changes.
    /// @param adjustment Details of the asset balance adjustment.
    /// @param preBalance The balance before the adjustment.
    /// @return postBalance The balance after the adjustment.
    /// @return oiFee The open interest fee calculated based on the adjustment.
    function _preUpdate(BalanceAdjustment memory adjustment, uint256 txId, int256 preBalance)
        internal
        returns (int256 postBalance, uint64 oiFee)
    {
        // Open interest tracking
        _preSnapshotOI(adjustment.subId, txId);
        _postSnapshotOI(adjustment.subId, preBalance, adjustment.amount);

        oiFee = _calcOpenInterestFee(adjustment.amount, adjustment.subId, txId);

        postBalance = preBalance + adjustment.amount;
    }

    /// @dev Adds a new position to the account's list of active positions
    /// @param accountId The ID of the account where the position is being added
    /// @param subId The sub-ID of the new position
    /// @return index The index at which the new position was added
    function _addPosition(uint256 accountId, uint256 subId) internal returns (uint256 index) {
        index = positions[accountId].length;
        if (index + 1 > MAX_OPEN_POSITIONS) revert Errors.ExceedMaxOpenPositions();

        positions[accountId].push(subId);
    }

    /// @dev Removes a position from the account's list of active positions
    /// @param accountId The ID of the account from which the position is being removed
    /// @param index The index of the position in the list to be removed
    function _removePosition(uint256 accountId, uint16 index) internal {
        uint256 positionNum = positions[accountId].length;

        uint256 positionToRemove = positions[accountId][index];

        if (index != positionNum - 1) {
            uint256 positonToMove = positions[accountId][positionNum - 1];
            positions[accountId][index] = positonToMove;

            balances[accountId][positonToMove].index = index;
        }

        delete balances[accountId][positionToRemove];
        positions[accountId].pop();
    }

    /// @dev Takes a snapshot of the open interest before a transaction
    /// @param subId The sub-ID of the option for which the snapshot is being taken
    /// @param txId The transaction ID for which the snapshot is being taken
    function _preSnapshotOI(uint256 subId, uint256 txId) internal {
        uint256 beforeOISlot = uint256(keccak256(abi.encode(subId, txId)));

        ///     <-- 15 bits -->  <---  240 bit --- >   <--- 1 bit--- >
        ///        0               Open interest        initialized

        if (beforeOISlot.tload() & 1 == 1) return;

        uint256 oi = openInterest[subId];

        beforeOISlot.tstore(1 | oi.toUint240() << 1);

        emit SnapshotOI(subId, txId, oi);
    }

    /// @dev Updates the open interest after a transaction
    /// @param subId The sub-ID of the option for which the open interest is updated
    /// @param preBalance The balance before the transaction
    /// @param change The change in balance resulting from the transaction
    function _postSnapshotOI(uint256 subId, int256 preBalance, int256 change) internal {
        int256 postBalance = preBalance + change;

        openInterest[subId] = (
            openInterest[subId].toInt256() + SignedMath.max(0, postBalance) - SignedMath.max(0, preBalance)
        ).toUint256();
    }

    /// @dev Calculates the open interest fee based on the change in open interest
    /// @param delta The change in the open interest resulting from the transaction
    /// @param subId The sub-ID of the option
    /// @param txId The transaction ID for which the fee is calculated
    /// @return fee The calculated open interest fee
    function _calcOpenInterestFee(int256 delta, uint256 subId, uint256 txId) internal view returns (uint64 fee) {
        uint256 beforeOI = uint256(keccak256(abi.encode(subId, txId))).tload() >> 1;

        if (!(openInterest[subId] > beforeOI)) return 0;

        (uint256 marketId, uint256 expiry,,) = Encoding.fromSubId(subId.toUint112());
        uint256 forwardPrice = forwardOracle[marketId.toUint16()].getForwardPrice(uint64(expiry));

        fee = SignedMath.abs(delta).multiplyDecimal(forwardPrice).multiplyDecimal(OIFee).toUint64();
    }
}
