// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IInsuranceFund {
    /// @notice Returns the recipient sub-account id
    /// @return The recipient sub-account id
    function recipient() external returns (uint256);

    /// @notice Event emitted when the fee recipient sub-account is created
    /// @param accountId The created fee recipient sub-account id
    event FeeRecipientCreated(uint256 accountId);

    /// @notice Emitted when a operator is set or updated
    /// @param operator The address of the trusted executor
    event OperatorSet(address operator);
}
