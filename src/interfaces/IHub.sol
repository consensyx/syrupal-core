// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {IUSDX} from "./IUSDX.sol";
import {IOption} from "./IOption.sol";
import {ILiquidation} from "./ILiquidation.sol";
import {IInsuranceFund} from "./IInsuranceFund.sol";
import {IPositionManager} from "./IPositionManager.sol";

/// @title IHub Interface
interface IHub {
    /// @notice Retrieves the contract instance of the USDX token.
    /// @return The instance of USDX contract.
    function usdx() external returns (IUSDX);

    /// @notice Retrieves the contract instance managing options.
    /// @return The address of Option contract.
    function option() external returns (IOption);

    /// @notice Retrieves the contract instance managing liquidations.
    /// @return The address of Liquidation contract.
    function liquidation() external returns (ILiquidation);

    /// @notice Retrieves the contract instance managing position-related operations.
    /// @return The address of PositionManager contract.
    function manager() external returns (IPositionManager);

    /// @notice Retrieves the contract instance managing the insurance fund.
    /// @return The address of IInsuranceFund contract.
    function insuranceFund() external returns (IInsuranceFund);

    /// @notice Generates a new transaction ID, typically used for tracking operations uniquely across the system.
    /// @return The new transaction ID.
    function incrementTxId() external returns (uint256);

    /// @notice Retrieves the last transaction ID associated with a specific account.
    /// @param accountId The ID of the account for which to retrieve the last transaction ID.
    /// @return The last transaction ID recorded for the specified account.
    function lastTxId(uint256 accountId) external returns (uint256);

    /// @notice Updates the last transaction ID recorded for a specific account.
    /// @param account The ID of the account for which to update the transaction ID.
    /// @param txId The new transaction ID to be recorded.
    function updateLastTxId(uint256 account, uint256 txId) external;

    /// @notice Sets up the system components by linking all the relevant contracts together.
    /// This function is typically used during initialization to set up the relationships between different system parts.
    /// @param _manager The contract instance managing position-related operations.
    /// @param _usdx The contract instance of the USDX token.
    /// @param _option The contract instance managing options.
    /// @param _liquidation The contract instance managing liquidations.
    /// @param _insuranceFund The contract instance managing the insurance fund.
    function setProtocol(
        IPositionManager _manager,
        IUSDX _usdx,
        IOption _option,
        ILiquidation _liquidation,
        IInsuranceFund _insuranceFund
    ) external;
}
