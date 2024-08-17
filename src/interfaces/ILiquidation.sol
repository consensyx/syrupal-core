// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @title ILiquidation Interface
interface ILiquidation {
    /// @notice Structure to represent a liquidation transfer
    /// @param counterParty The counterparty involved in the liquidation
    /// @param amount The amount involved in the liquidation transfer
    /// @param subId The sub-account ID related to the transfer
    struct LiquidationTransfer {
        uint256 counterParty;
        int256 amount;
        uint112 subId;
    }

    /// @notice Checks if an account can be liquidated based on its available margin
    /// @param accountId The ID of the account to check for liquidation
    /// @param initial if it's true, we use initial margin, otherwise maintenance margin
    /// @return True if the account can be liquidated, otherwise false
    function canLiquidate(uint256 accountId, bool initial) external returns (bool);

    /// @notice Returns the liquidation status of an account
    /// @param accountId The ID of the account to check
    /// @return True if the account is liquidated, otherwise false
    function liquidatedAccounts(uint256 accountId) external view returns (bool);

    /// @notice Event emitted when a liquidator is set
    /// @param liquidator The address of the new liquidator
    event LiquidatorSet(address liquidator);

    /// @notice Event emitted when an account is recovered from liquidation
    /// @param accountId The ID of the account that was recovered
    event AccountRecovered(uint256 accountId);

    /// @notice Event emitted when an account is marked for liquidation
    /// @param accountId The ID of the account that was liquidated
    event AccountLiquidated(uint256 accountId);
}
