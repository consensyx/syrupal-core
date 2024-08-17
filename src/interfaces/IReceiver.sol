// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @title IReceiver Interface
/// @notice Interface for contracts designed to receive and process arbitrary data.
interface IReceiver {
    /// @notice Receive data for processing
    /// @param data Arbitrary bytes data to be processed by the implementing contract
    function receiveData(bytes calldata data) external;
}
