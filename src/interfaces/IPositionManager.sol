// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IERC721} from "openzeppelin/token/ERC721/IERC721.sol";

import {IAsset} from "./IAsset.sol";
import {ILiquidation} from "../interfaces/ILiquidation.sol";

/// @title Interface for Position Manager
interface IPositionManager is IERC721 {
    /// @notice Structure to hold data for manager operations
    struct PreProcessData {
        address receiver; // Address expected to receive the data
        bytes data; // Data passed to the receiver
    }

    /// @notice Represents an options contract with strike, balance, and type
    struct Option {
        uint256 strike; // Strike price of the option
        int256 balance; // Balance of options held
        bool isCall; // True if call option, false if put option
    }

    /// @notice Submits a batch of asset transfers associated with a single transaction.
    /// @param transfers An array of `BalanceTransfer` structs defining the transfers to be processed.
    /// @param preData Additional data that may be needed by the asset manager or other transaction handlers.
    /// @return txId The transaction ID generated for this batch of transfers.
    function batchTransfers(IAsset.BalanceTransfer[] memory transfers, bytes memory preData)
        external
        returns (uint256 txId);

    /// @notice Adjust the account's position in response to transactions or market events
    /// @param txId Transaction ID associated with the adjustment
    /// @param subAccount Identifier of the sub-account being adjusted
    /// @param decreaseUSD Boolean indicating if USD balance should decrease
    /// @param oiFee Open interest fee applicable to the adjustment
    /// @param caller Address of the entity initiating the adjustment
    /// @param data Custom data associated with the adjustment operation
    function evaluateMargin(
        uint256 txId,
        uint256 subAccount,
        bool decreaseUSD,
        uint64 oiFee,
        address caller,
        bytes calldata data
    ) external;

    /// @notice Creates a new sub-account under the control of a specified owner.
    /// @param owner The address that will own the new sub-account.
    /// @return subAccount The unique identifier of the newly created sub-account.
    function createSubAccount(address owner) external returns (uint256 subAccount);

    /// @notice Exercise expired options for a specified account
    /// @param accountId Identifier of the account whose options will be exercised
    function exercise(uint256 accountId) external;

    /// @notice Transfer positions and balances from a liquidated user to the insurance fund
    /// @param liquidateeId Identifier of the user being liquidated
    function takeover(uint256 liquidateeId) external;

    /// @notice Verify the existence of a market by its ID
    /// @param marketId Identifier of the market to check
    function isMarketExist(uint256 marketId) external view;

    /// @notice Automatically deleverage positions in response to market conditions
    /// @param transfers Array of liquidation transfers to be processed
    function autoDeleverage(ILiquidation.LiquidationTransfer[] calldata transfers) external;

    /// @notice Calculate the total margin of a sub-account
    /// @param accountId Identifier of the account
    /// @param isInitial Boolean indicating if the calculation is for initial margin
    /// @return margin Total calculated margin
    function getTotalMargin(uint256 accountId, bool isInitial) external returns (int256);

    /// @notice Calculate the total market value of a sub-account
    /// @param accountId Identifier of the account
    /// @return margin Total calculated market value of all postion and usdx balance
    function getTotalMarketValue(uint256 accountId) external returns (int256);

    /// @notice Emitted when a new account is created, associating it with its owner.
    /// @param owner The address of the account owner.
    /// @param accountId The unique identifier of the new account.
    event AccountCreated(address indexed owner, uint256 indexed accountId);

    /// @notice Emitted when a new market is created
    /// @param marketId The ID of the newly created market
    /// @param marketName The name of the newly created market
    event MarketCreated(uint256 marketId, string marketName);

    /// @notice Emitted when a takeover occurs, transferring all positions and balances
    /// @param liquidatorId The ID of the liquidator
    /// @param liquidateeId The ID of the liquidated user
    /// @param subId The sub-account ID
    /// @param amount The amount transferred
    event TakeOver(uint256 liquidatorId, uint256 liquidateeId, uint256 subId, int256 amount);

    /// @notice Emitted during the auto-deleveraging process
    /// @param counterparty The counterparty involved in the deleverage
    /// @param feeRecipient The recipient of the fees from deleveraging
    /// @param subId The sub-account ID involved in the deleverage
    /// @param amount The amount of the position adjusted
    /// @param marketValue The market value of the position adjusted
    event AutoDeleverage(uint256 counterparty, uint256 feeRecipient, uint256 subId, int256 amount, int256 marketValue);

    /// @notice Emitted when an option is exercised
    /// @param accountId The ID of the account exercising the option
    /// @param subId The sub-account ID of the exercised option
    /// @param amount The amount of the option exercised
    /// @param USDAmount The USD amount involved in the exercise
    event OptionExercised(uint256 indexed accountId, uint256 subId, int256 amount, int256 USDAmount);

    /// @notice Emitted when assets are transferred between sub-accounts as part of a managed transaction.
    /// @param from The ID of the account from which assets are transferred.
    /// @param to The ID of the account receiving the assets.
    /// @param asset The asset interface being transferred.
    /// @param subId The sub-account or specific asset class identifier related to the transfer.
    /// @param amount The amount of the asset being transferred.
    /// @param txId The transaction ID associated with this asset transfer.
    event BalanceTransferred(
        uint256 indexed from, uint256 indexed to, IAsset asset, uint256 subId, int256 amount, uint256 txId
    );

    /// @param receiver Addresses authorized to accept customize manager data
    event DataReceiverSet(address receiver, bool authorized);

    /// @notice Emitted when the annualized discount for BSM formula is set
    /// @param discount The new discount factor
    event DiscountSet(uint64 discount);

    /// @notice Emitted when the oracle for stablecoin prices is set
    /// @param stableOracle The address of the stablecoin oracle
    event StableOracleSet(address stableOracle);

    /// @notice Emitted when the fee recipient account is set
    /// @param newRecipient The account ID of the new fee recipient
    event FeeRecipientSet(uint256 newRecipient);

    /// @param threshold The price threshold for depegging consideration
    /// @param depegFactor The depeg factor for margin increase
    event DepegParamsSet(uint256 threshold, uint256 depegFactor);

    /// @notice Emitted when a liquidator is set or updated
    /// @param liquidator The address of the liquidator
    /// @param allowed Whether the liquidator is allowed to act
    event LiquidatorSet(address liquidator, bool allowed);

    /// @notice Emitted when a executor is set or updated
    /// @param executor The address of the trusted executor
    /// @param allowed Whether the executor is allowed to act
    event ExecutorSet(address executor, bool allowed);

    /// @notice Emitted when a operator is set or updated
    /// @param operator The address of the trusted executor
    event OperatorSet(address operator);

    /// @notice Emitted when a caller is set to bypass the open interest fee
    /// @param caller The address of the caller
    /// @param exempted Whether the OI fee is bypassed
    event FeeExemptionSet(address caller, bool exempted);

    /// @notice Emitted when a trusted caller set, which only need to meet the maintenance margin requirements when they create position
    /// @param caller The address of the risk assessor
    /// @param trusted Whether the risk assessor is trusted
    event MaintenanceMarginCallerSet(address caller, bool trusted);

    /// @notice Emitted when oracles for a market are set
    /// @param marketId The market ID
    /// @param spotOracle The address of the spot price oracle
    /// @param forwardOracle The address of the forward price oracle
    /// @param volOracle The address of the volatility oracle
    event OraclesSet(uint256 marketId, address spotOracle, address forwardOracle, address volOracle);

    /// @notice Emitted when margin parameters for a market are set
    /// @param marketId The market ID
    /// @param IMUpperRatio The upper initial margin ratio set
    /// @param IMLowerRatio The lower initial margin ratio set
    /// @param MMRatio The maintenance margin ratio set
    event MarginParamsSet(uint256 marketId, uint256 IMUpperRatio, uint256 IMLowerRatio, uint256 MMRatio);
}
