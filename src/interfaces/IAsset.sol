// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @title IAsset Interface
interface IAsset {
    /// @notice Struct to hold the balance of an asset for a sub-account.
    struct AssetBalance {
        uint112 subId; // Identifier for option, default 0 for USDX asset
        int256 balance; // The balance of the asset.
    }

    /// @notice Struct to define the parameters for a transfer of assets between accounts.
    struct BalanceTransfer {
        uint256 from; // Account ID from which assets are transferred.
        uint256 to; // Account ID to which assets are transferred.
        IAsset asset; // The asset address being transferred.
        uint112 subId; // The asset identifier.
        int256 amount; // The amount of the asset to transfer.
    }

    /// @notice Struct for specifying adjustments to an asset's balance.
    struct BalanceAdjustment {
        uint256 accountId; // Account ID for which the adjustment is made.
        IAsset asset; // The asset being adjusted.
        uint112 subId; // The asset identifier.
        int256 amount; // The amount of the adjustment.
    }

    /// @notice Adjust the balance of an asset for a specific account.
    /// @param adjustment The details of the adjustment.
    /// @param txId The transaction ID associated with this adjustment.
    /// @return postBalance The balance of the asset after adjustment.
    /// @return oiFee The open interest fee incurred from this transaction.
    function updateBalance(BalanceAdjustment memory adjustment, uint256 txId)
        external
        returns (int256 postBalance, uint128 oiFee);

    /// @notice Emitted when an asset's balance is updated.
    /// @param accountId The sub-account ID.
    /// @param asset The asset that was adjusted.
    /// @param amount The amount of the adjustment.
    /// @param txId The transaction ID associated with the balance adjustment.
    event BalanceUpdated(uint256 indexed accountId, address indexed asset, int256 amount, uint256 txId);
}
