// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {SignedMath} from "openzeppelin/utils/math/SignedMath.sol";

import {Errors} from "./libraries/Errors.sol";
import {DecimalMath} from "./external/decimals/DecimalMath.sol";
import {ReentrancyGuardTransient} from "./libraries/ReentrancyGuardTransient.sol";

import {ILiquidation} from "./interfaces/ILiquidation.sol";
import {IInsuranceFund} from "./interfaces/IInsuranceFund.sol";
import {IPositionManager} from "./interfaces/IPositionManager.sol";

/// @title Liquidation Contract
/// @dev This contract manages the liquidation process for insolvency sub-accounts.
contract Liquidation is ILiquidation, Ownable2Step, ReentrancyGuardTransient {
    /// @dev Trusted Liquidator address
    address public liquidator;

    /// @dev Position manager contract address
    IPositionManager public manager;

    /// @dev Insurance fund contract address
    IInsuranceFund public insuranceFund;

    /// @dev Liquidated account mapping
    mapping(uint256 accountId => bool) public liquidatedAccounts;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    constructor(IPositionManager _manager, IInsuranceFund _insuranceFund) Ownable2Step() {
        manager = _manager;
        insuranceFund = _insuranceFund;
    }

    /// @notice Marks an account as in liquidation status when its USDX balance minus the maintenance margin is less than zero
    /// @dev It will revert if (USDX - maintenance margin) < 0 is not met
    /// @param liquidateeId The sub-account ID of the user to be liquidated
    function startLiquidation(uint256 liquidateeId) external nonReentrant {
        if (msg.sender != liquidator) revert Errors.OnlyLiquidator();

        // Will not revert
        if (liquidatedAccounts[liquidateeId]) return;

        if (!canLiquidate(liquidateeId, false) || liquidateeId == insuranceFund.recipient()) {
            revert Errors.CannotStartLiquidation();
        }

        liquidatedAccounts[liquidateeId] = true;

        emit AccountLiquidated(liquidateeId);
    }

    /// @notice Reclassifies accounts marked for liquidation as normal if their USDX balance - the maintenance margin is greater than zero
    /// @dev  It will revert if (usdx - maintenance margin) >= 0 is not met
    /// @param liquidateeId The sub-account ID of the user being liquidated
    function stopLiquidation(uint256 liquidateeId) external nonReentrant {
        if (msg.sender != liquidator) revert Errors.OnlyLiquidator();

        // Will not revert
        if (!liquidatedAccounts[liquidateeId]) return;
        if (canLiquidate(liquidateeId, true)) revert Errors.CannotStopLiquidation();

        delete liquidatedAccounts[liquidateeId];

        emit AccountRecovered(liquidateeId);
    }

    /// @notice Set trusted liquidator address
    /// @param _liquidator trusted liquidator address
    function setLiquidator(address _liquidator) external onlyOwner {
        if (_liquidator == address(0)) revert Errors.ZeroAddress();
        liquidator = _liquidator;

        emit LiquidatorSet(_liquidator);
    }

    /// @notice Checks if an account can be liquidated based on its available margin
    /// @param accountId The ID of the account to check for liquidation
    /// @param initial  if it's true, we use initial margin, otherwise maintenance margin
    /// @return True if the account can be liquidated, otherwise false
    function canLiquidate(uint256 accountId, bool initial) public returns (bool) {
        int256 availableMargin = manager.getTotalMargin(accountId, initial);
        return availableMargin < 0;
    }
}
