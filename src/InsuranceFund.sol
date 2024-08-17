// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {Errors} from "./libraries/Errors.sol";
import {DecimalMath} from "./external/decimals/DecimalMath.sol";
import {ConvertDecimals} from "./external/decimals/ConvertDecimals.sol";

import {IHub} from "./interfaces/IHub.sol";
import {IUSDX} from "./interfaces/IUSDX.sol";
import {IAsset} from "./interfaces/IAsset.sol";
import {IInsuranceFund} from "./interfaces/IInsuranceFund.sol";

/// @title Insurance Fund Contract
/// @notice andling emergency deposits, withdrawals, and insolvency cover.
contract InsuranceFund is Ownable2Step, IInsuranceFund {
    using SafeCast for int256;
    using ConvertDecimals for uint256;
    using SafeERC20 for IERC20Metadata;
    using DecimalMath for uint256;

    /// @notice Hub contract for interaction with other system components
    IHub public hub;

    /// @dev USDX token contract
    IUSDX public immutable usdx;

    /// @notice The 'operator' is responsible for key operations such as withdraw, payInsolvency, etc.
    address public operator;

    /// @dev The underlying stablecoin contract used by the USDX contract for handling deposits and withdrawals.
    IERC20Metadata public immutable stablecoin;

    /// @dev ID of the insurance fund's recipient sub-account within the system for receive protocol fee
    uint256 public recipient;

    /*//////////////////////////////////////////////////////////////////////////
                                     CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    /// @param _hub Address of the system's hub contract
    /// @param _usdx Address of the USDX contract
    /// @param _operator authorized operator address
    constructor(IHub _hub, IUSDX _usdx, address _operator) {
        hub = _hub;
        usdx = _usdx;
        operator = _operator;

        stablecoin = usdx.stablecoin();
        stablecoin.approve(address(_usdx), type(uint256).max);
    }

    /// @notice Creates a recipient sub-account for the insurance fund within the system
    function createRecipient() external onlyOwner {
        // Can't create recipient sub-account repeatedly otherwise the assets held by former recipient cannot be withdraw
        if (hub.manager().balanceOf(address(this)) >= 1) revert Errors.OnlyOneRecipient();

        recipient = hub.manager().createSubAccount(address(this));

        emit FeeRecipientCreated(recipient);
    }

    /// @notice Deposits stablecoins into the insurance fund to cover insolvency loss
    /// @param stableAmount The amount of stablecoin to deposit
    function donate(uint256 stableAmount) external {
        stablecoin.safeTransferFrom(msg.sender, address(this), stableAmount);
        usdx.deposit(recipient, stableAmount);
    }

    /// @notice Uses the balance of the insurance fund to cover insolvency losses
    function payInsolvency() external {
        usdx.donate(recipient, usdx.balances(recipient).toUint256());
    }

    /// @notice Withdraws stablecoins from the insurance fund to a designated receiver
    /// @param stableAmount The amount of stablecoin to withdraw
    /// @param receiver The address to receive the withdrawn stablecoins
    function withdraw(uint256 stableAmount, address receiver) external onlyOperator {
        if (receiver == address(0)) revert Errors.ZeroAddress();
        usdx.withdraw(recipient, stableAmount, receiver);
    }

    /// @notice Reset the allowance granted to the USDX contract
    /// @param amount The new allowance amount
    function resetApproval(uint256 amount) external onlyOperator {
        stablecoin.approve(address(usdx), amount);
    }

    /// @dev Allows the recovery of ERC20 tokens accidentally sent to this contract
    /// @param tokenAddress The address of the ERC20 token to recover
    /// @param receiver The address to which the tokens will be transferred
    /// @param tokenAmount The amount of tokens to transfer
    function rescueERC20(address tokenAddress, address receiver, uint256 tokenAmount) external onlyOperator {
        IERC20Metadata(tokenAddress).safeTransfer(receiver, tokenAmount);
    }

    /// @notice Update the authorzied operator address
    /// @param _newOperator Address of the liquidator to be updated
    function setOperator(address _newOperator) external onlyOwner {
        if (_newOperator == address(0)) revert Errors.ZeroAddress();
        operator = _newOperator;

        emit OperatorSet(_newOperator);
    }

    /// @dev Modifier to ensure only msg sender is authorized operator
    modifier onlyOperator() {
        if (msg.sender != operator) revert Errors.OnlyOperator();
        _;
    }
}
