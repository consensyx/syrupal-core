//SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title Custom error definitions for the protocol
/// @notice This library contains all the error definitions used throughout the contract
/// @dev The errors are arranged in alphabetical order
library Errors {
    /// @notice Error indicating adjustments are paused
    error AdjustmentsPaused();

    /// @notice Error indicating that the lengths of the provided arrays do not match
    error ArrayLengthNotMatch();

    /// @notice Error indicating that the position cap has been exceeded
    error CannotIncreasePosition();

    /// @notice Error indicating that the account cannot start liquidation
    error CannotStartLiquidation();

    /// @notice Error indicating that the account cannot stop liquidation
    error CannotStopLiquidation();

    /// @notice Error indicating duplicated signer
    error DuplicatedSigner();

    /// @notice Error indicating expired data
    error ExpiredData();

    /// @notice Error indicating that the expiry is too far in the future
    error ExpiryTooFarInFuture();

    /// @notice Error indicating that the maximum number of open positions has been exceeded
    error ExceedMaxOpenPositions();

    /// @notice Error indicating that the position cap has been exceeded
    error ExceededPositionCap();

    /// @notice Error indicating missing expiry data
    error InvalidExpiryData();

    /// @notice Error indicating invalid depeg parameters
    error InvalidDepegParams();

    /// @notice Error indicating invalid discount
    error InvalidDiscount();

    /// @notice Error indicating invalid forward data timestamp
    error InvalidFwdDataTimestamp();

    /// @notice Error indicating invalid liquidation
    error InvalidLiquidation();

    /// @notice Error indicating invalid margin parameters
    error InvalidMarginParams();

    /// @notice Error indicating invalid minimum signers
    error InvalidMinimumSigners();

    /// @notice Error indicating invalid OI fee
    error InvalidOIFee();

    /// @notice Error indicating invalid settlement data
    error InvalidSettlementData();

    /// @notice Error indicating invalid signature
    error InvalidSignature();

    /// @notice Error indicating invalid signer
    error InvalidSigner();

    /// @notice Error indicating invalid timestamp
    error InvalidTimestamp();

    /// @notice Error indicating invalid vol data timestamp
    error InvalidVolDataTimestamp();

    /// @notice Error indicating invalid withdraw threshold
    error InvalidWithdrawThreshold();

    /// @notice Error indicating the account is liquidated
    error LiquidateAccount();

    /// @notice Error indicating negative margin
    error NegativeMargin();

    /// @notice Error indicating negative USD balance
    error NegativeUSD();

    /// @notice Error indicating the market does not exist
    error NotExistMarket();

    /// @notice Error indicating the position does not exist
    error NotExistPosition();

    /// @notice Error indicating the account is not liquidated
    error NotLiquidatedAccount();

    /// @notice Error indicating not enough signers
    error NotEnoughSigners();

    /// @notice Error indicating only the account owner can call
    error OnlyAccountOwner();

    /// @notice Error indicating only trusted executor can call
    error OnlyExecutor();

    /// @notice Error indicating only trusted liquidator can call
    error OnlyLiquidator();

    /// @notice Error indicating only manager can call
    error OnlyManager();

    /// @notice Error indicating only authorized operator allowed
    error OnlyOperator();

    /// @notice Error indicating only one recipient allowed
    error OnlyOneRecipient();

    /// @notice Error indicating only privileged can call
    error OnlyPrivilege();

    /// @notice Error indicating only protocol can call
    error OnlyProtocol();

    /// @notice Error indicating only whitelist can call
    error OnlyWhitelist();

    /// @notice Error indicating self transfer is not allowed
    /// @param caller The address of the caller
    /// @param accountId The ID of the account
    error SelfTransfer(address caller, uint256 accountId);

    /// @notice Error indicating mismatch in signers length
    error SignatureSignersLengthMismatch();

    /// @notice Error indicating settlement data is too old
    error SettlementDataTooOld();

    /// @notice Error indicating unauthorized call
    error UnauthorizedCall();

    /// @notice Error indicating virtual function not implemented
    error VirtualNotImplemented();

    /// @notice Error indicating withdraw is paused
    error WithdrawPaused();

    /// @notice Error indicating zero account address
    error ZeroAccount();

    /// @notice Error indicating zero amount
    error ZeroAmount();

    /// @notice Error indicating zero address
    error ZeroAddress();

    /// @notice Error indicating zero price
    error ZeroPrice();
}
