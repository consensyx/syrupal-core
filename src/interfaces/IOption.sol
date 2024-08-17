// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IAsset} from "./IAsset.sol";
import {IForwardOracle} from "../oracle/interfaces/IForwardOracle.sol";

/// @title IOption Interface
interface IOption is IAsset {
    /// @notice Struct to hold an asset balance with a specific index.
    /// This struct optimizes storage by fitting the index and balance within a single storage slot.
    struct IndexBalance {
        uint16 index; // Index to help reference this specific balance in a array.
        int240 balance; // Asset balance, using int240 to efficiently use the storage slot.
    }

    /// @notice Structure representing an option
    /// @param strike The strike price of the option
    /// @param balance The balance of the option
    /// @param isCall Whether the option is a call option
    struct Option {
        uint256 strike;
        int256 balance;
        bool isCall;
    }

    /// @notice Snapshot of open interest
    /// @param initialized Whether the snapshot is initialized
    /// @param oi The open interest value
    struct OISnapshot {
        bool initialized;
        uint240 oi;
    }

    /// @notice Snapshot of a position
    /// @param initialized Whether the snapshot is initialized
    /// @param position The position value
    struct PositionSnapshot {
        bool initialized;
        uint240 position;
    }

    /// @notice Returns the total open interest for a specific option
    /// @param optionId The ID of the option
    /// @return The total open interest for the option
    function openInterest(uint256 optionId) external view returns (uint256);

    /// @notice Calculates the profit or loss for an expired option
    /// @param subId The subId of the option
    /// @param balance The balance of the option
    /// @return payout The payout for the option
    /// @return priceSettled A boolean indicating if the price is settled
    function calculatePayOff(uint256 subId, int256 balance) external view returns (int256 payout, bool priceSettled);

    /// @notice Queries all option positions held by a sub-account
    /// @param accountId The sub-account ID
    /// @return assetBalances All held option details
    function getAccountBalance(uint256 accountId) external view returns (AssetBalance[] memory assetBalances);

    /// @notice Queries the details of a specified option held by a sub-account
    /// @param accountId The sub-account ID
    /// @param subId The subId of the option
    /// @return balance The balance of the specified option
    function getPositionBalance(uint256 accountId, uint256 subId) external view returns (int256);

    /// @notice Returns the forward oracle contract for a specific market
    /// @param marketId The ID of the market
    /// @return The forward oracle contract
    function forwardOracle(uint16 marketId) external view returns (IForwardOracle);

    /// @notice Event emitted when the forward oracle is set for a market
    /// @param marketId The ID of the market
    /// @param forwardOracle The address of the forward oracle contract
    event ForwardOracleSet(uint16 marketId, address forwardOracle);

    /// @notice Event emitted when the open interest fee rate is set
    /// @param oldFeeRate The old fee rate
    /// @param newFeeRate The new fee rate
    event OIFeeSet(uint256 oldFeeRate, uint256 newFeeRate);

    /// @notice Event emitted when an open interest snapshot is taken
    /// @param optionId The ID of the option
    /// @param txId The transaction ID
    /// @param oi The open interest value
    event SnapshotOI(uint256 optionId, uint256 txId, uint256 oi);

    /// @notice Event emitted when a market position snapshot is taken
    /// @param marketId The ID of the market
    /// @param txId The transaction ID
    /// @param position The market position value
    event SnapshotPosition(uint16 marketId, uint256 txId, uint256 position);
}
