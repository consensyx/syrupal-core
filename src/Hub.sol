// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

import {Errors} from "./libraries/Errors.sol";

import {IHub} from "./interfaces/IHub.sol";
import {IUSDX} from "./interfaces/IUSDX.sol";
import {IOption} from "./interfaces/IOption.sol";
import {ILiquidation} from "./interfaces/ILiquidation.sol";
import {IInsuranceFund} from "./interfaces/IInsuranceFund.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title Hub Contract
/// @notice Acts as the central component of the protocol, connecting various modules like accounts, trading, and risk management.
contract Hub is IHub, Ownable2Step {
    /// @dev  position management contract
    IPositionManager public manager;

    /// @dev USDX contract
    IUSDX public usdx;

    /// @dev Option contract
    IOption public option;

    /// @dev Liquidation management contract
    ILiquidation public liquidation;

    /// @dev Insurance fund contract
    IInsuranceFund public insuranceFund;

    /// @dev Global transaction ID, incremented for each transaction
    uint256 public txId;

    /// @dev Stores the last transaction ID for each sub-account to track updates
    mapping(uint256 accountId => uint256 txId) public lastTxId;

    /// @notice Sets up the various components of the hub, linking all major parts of the system
    /// @param _manager Position mananger contract
    /// @param _usdx USDX token contract
    /// @param _option Option contract
    /// @param _liquidation Contract for handling liquidations
    /// @param _insuranceFund Contract for managing the insurance fund
    function setProtocol(
        IPositionManager _manager,
        IUSDX _usdx,
        IOption _option,
        ILiquidation _liquidation,
        IInsuranceFund _insuranceFund
    ) external onlyOwner {
        manager = _manager;
        usdx = _usdx;
        option = _option;
        liquidation = _liquidation;
        insuranceFund = _insuranceFund;
    }

    /// @notice Increments the global transaction ID, used for tracking transactions across the system
    /// @return Returns the new transaction ID after increment
    function incrementTxId() external onlyProtocol returns (uint256) {
        return ++txId;
    }

    /// @notice Updates the last transaction ID for a specific sub-account, used for tracking latest interactions
    /// @param _account The sub-account ID
    /// @param _txId The new transaction ID to be recorded
    function updateLastTxId(uint256 _account, uint256 _txId) external onlyProtocol {
        lastTxId[_account] = _txId;
    }

    /// @dev Modifier to ensure only the msg.sender is protocol contract
    modifier onlyProtocol() {
        if (msg.sender != address(manager) && msg.sender != address(usdx) && msg.sender != address(option)) {
            revert Errors.OnlyProtocol();
        }
        _;
    }
}
