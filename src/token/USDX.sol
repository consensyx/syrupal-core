// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Math} from "openzeppelin/utils/math/Math.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {Errors} from "../libraries/Errors.sol";
import {DecimalMath} from "../external/decimals/DecimalMath.sol";
import {ConvertDecimals} from "../external/decimals/ConvertDecimals.sol";
import {SignedDecimalMath} from "../external/decimals/SignedDecimalMath.sol";
import {ReentrancyGuardTransient} from "../libraries/ReentrancyGuardTransient.sol";

import {IHub} from "../interfaces/IHub.sol";
import {IUSDX} from "../interfaces/IUSDX.sol";
import {IPositionManager} from "../interfaces/IPositionManager.sol";

/// @title USDX Stablecoin Contract
/// @dev This contract represents a stablecoin (USDX) that is backed by a stablecoin asset (e.g., USDC).
contract USDX is IUSDX, Ownable2Step, ReentrancyGuardTransient {
    using SafeERC20 for IERC20Metadata;
    using ConvertDecimals for uint256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using SignedDecimalMath for int256;
    using DecimalMath for uint256;

    IHub public hub;

    /// @dev Position manager contract address
    IPositionManager public manager;

    /// @dev stablecoin token address
    IERC20Metadata public immutable stablecoin;

    /// @dev stablecoin decimal
    uint8 private immutable stableDecimal;

    /// @dev The sub-account that receive protocol fee, it's owner should be insurance fund
    uint256 public feeRecipient;

    /// @dev Gross issued USDX
    uint256 private grossSupply;

    /// @dev Gross borrowed asset
    uint256 private grossDebt;

    /// @dev When the ratio of USDC amount to USDX total supply in the contract falls below this threshold, the contract will suspend withdrawals
    uint256 public withdrawThreshold = 1e18;

    /// @dev The temporary change in USDX total supply when exercise expired options. the user's positions is exercised one by one.
    /// Assume Alice and Bob are counterparties, when the option expire, Alice earns 1000 USD, this profit derived from Bob's loss,
    /// If Alice's position is exercised first, Alice's account will increase by 1000 USD, but Bob's account have not been decreased 1000 USD,
    /// which will lead the 'totalSupply' also increase 1000 USD, therefore, we use 'temporarySupply' to record the temporary changes in totalSupply caused by the exercise.
    int256 public temporarySupply;

    /// @dev accountId => balance
    mapping(uint256 accountId => int256) public balances;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(IHub _hub, IPositionManager _manager, IERC20Metadata _stablecoin) {
        hub = _hub;
        manager = _manager;
        stablecoin = _stablecoin;
        stableDecimal = stablecoin.decimals();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                      EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    /// @inheritdoc IUSDX
    function deposit(uint256 recipientAccount, uint256 stableAmount) external nonReentrant {
        _deposit(recipientAccount, stableAmount);
    }

    /// @inheritdoc IUSDX
    function withdraw(uint256 accountId, uint256 stableAmount, address receiver) external nonReentrant {
        if (msg.sender != manager.ownerOf(accountId)) revert Errors.OnlyAccountOwner();
        // Withdrawals will be suspend if maintenance margin < 0
        if (hub.liquidation().canLiquidate(accountId, false)) revert Errors.NegativeMargin();

        if (_getExchangeRate() < withdrawThreshold) revert Errors.WithdrawPaused();

        // if stablecoin token decimal pass in is in higher decimals than 18, round up the trailing amount
        // to make sure users cannot withdraw dust amount, while keeping usdxAmount == 0.
        uint256 tokenAmount = stableAmount.to18DecimalsRoundUp(stableDecimal);
        _withdraw(accountId, tokenAmount, receiver);
    }

    /// @inheritdoc IUSDX
    function donate(uint256 subAccount, uint256 amount) external nonReentrant returns (uint256 burnAmount) {
        if (msg.sender != address(manager.ownerOf(subAccount))) {
            revert Errors.OnlyAccountOwner();
        }

        uint256 insolventAmount = totalSupply() - stablecoin.balanceOf(address(this)).to18Decimals(stableDecimal);
        burnAmount = Math.min(amount, insolventAmount);

        _balanceAdjustment(
            BalanceAdjustment({
                accountId: subAccount,
                asset: IUSDX(address(this)),
                subId: 0,
                amount: -(burnAmount.toInt256())
            }),
            ""
        );
    }

    /// @notice It is the only entry point to modify the user's USDX balance
    /// @dev only position manager or subAccount can call this function
    /// @param adjustment struct for changes in the sub-account's USDX balance
    /// @param txId txid corresponding to the current balance change transaction
    /// @return postBalance the balance after update
    /// @return oiFee always return 0
    function updateBalance(BalanceAdjustment memory adjustment, uint256 txId)
        public
        returns (int256 postBalance, uint64 oiFee)
    {
        if (msg.sender != address(manager)) {
            revert Errors.OnlyProtocol();
        }

        return (_updateBalance(adjustment, txId), 0);
    }

    /// @inheritdoc IUSDX
    function updateTemporarySupply(int256 amount) external {
        if (msg.sender != address(manager)) revert Errors.OnlyManager();

        temporarySupply += amount;

        emit TemporarySupplySet(amount, temporarySupply);
    }

    /// @notice Set withdraw thereshold
    /// @dev When the ratio of USDC amount to USDX total supply falls below this threshold, the contract will suspend withdrawals
    /// @param _threshold The minimum ratio of USDC to total supply required for withdrawals.
    function setWithdrawThreshold(uint256 _threshold) public onlyOwner {
        if (_threshold > 1e18) {
            revert Errors.InvalidWithdrawThreshold();
        }
        withdrawThreshold = _threshold;

        emit WithdrawThresholdSet(_threshold);
    }

    /// @notice Set the protocol fee recipient sub-account
    /// @param _newRecipient new fee recipient sub-account
    function setFeeRecipient(uint256 _newRecipient) external onlyOwner {
        manager.ownerOf(_newRecipient);

        feeRecipient = _newRecipient;
        emit FeeRecipientSet(_newRecipient);
    }

    // @inheritdoc IUSDX
    function getExchangeRate() external view returns (uint256) {
        return _getExchangeRate();
    }

    function totalSupply() public view returns (uint256) {
        return (grossSupply.toInt256() - grossDebt.toInt256() - temporarySupply).toUint256();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                       INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////////////////*/

    function _deposit(uint256 recipientAccount, uint256 stableAmount) internal {
        stablecoin.safeTransferFrom(msg.sender, address(this), stableAmount);
        uint256 usdAmount = stableAmount.to18Decimals(stableDecimal);

        _balanceAdjustment(
            BalanceAdjustment({
                accountId: recipientAccount,
                asset: IUSDX(address(this)),
                subId: 0,
                amount: usdAmount.toInt256()
            }),
            ""
        );

        emit Deposit(recipientAccount, msg.sender, usdAmount, stableAmount);
    }

    function _withdraw(uint256 accountId, uint256 amount, address recipient) internal {
        uint256 exchangeRate = _getExchangeRate();

        uint256 stableAmount = amount.multiplyDecimal(exchangeRate).from18Decimals(stableDecimal);

        stablecoin.safeTransfer(recipient, stableAmount);

        _balanceAdjustment(
            BalanceAdjustment({
                accountId: accountId,
                asset: IUSDX(address(this)),
                subId: 0,
                amount: -(amount.toInt256())
            }),
            ""
        );

        emit Withdraw(accountId, recipient, amount, stableAmount);
    }

    function _balanceAdjustment(BalanceAdjustment memory adjustment, bytes memory preData)
        internal
        returns (int256 postBalance)
    {
        uint256 txId = hub.incrementTxId();
        postBalance = _updateBalance(adjustment, txId);

        // Only withdraw and donate need to check margin
        if (adjustment.amount < 0) {
            manager.evaluateMargin(txId, adjustment.accountId, true, 0, address(this), preData);
        }
    }

    function _updateBalance(BalanceAdjustment memory adjustment, uint256 txId) internal returns (int256 postBalance) {
        hub.updateLastTxId(adjustment.accountId, txId);
        int256 preBalance = balances[adjustment.accountId];

        postBalance = preBalance + adjustment.amount;

        if (adjustment.accountId == feeRecipient && postBalance < 0) {
            // when the balance of the insurance fund is insufficient to cover the counterparty's profit,
            // the loss amount needs to be fulfilled by minting additional tokens
            emit InflationaryLoss(feeRecipient, (-postBalance).toUint256());

            // reset insurance fund balance to 0
            postBalance = 0;
        }

        // update post balance
        balances[adjustment.accountId] = postBalance.toInt240();

        uint256 _grossSupply =
            (grossSupply.toInt256() + SignedMath.max(0, postBalance) - SignedMath.max(0, preBalance)).toUint256();

        uint256 _grossDebt =
            (grossDebt.toInt256() + SignedMath.min(0, preBalance) - SignedMath.min(0, postBalance)).toUint256();

        // update gross variables
        grossSupply = _grossSupply;
        grossDebt = _grossDebt;

        emit BalanceUpdated(adjustment.accountId, address(adjustment.asset), adjustment.amount, txId);
    }

    function _getExchangeRate() internal view returns (uint256 exchangeRate) {
        uint256 _totalSupply = totalSupply();
        uint256 stableBalance = stablecoin.balanceOf(address(this)).to18Decimals(stableDecimal);
        if (stableBalance >= _totalSupply) {
            return 1e18;
        }
        return stableBalance.divideDecimal(_totalSupply);
    }
}
