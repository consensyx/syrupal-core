// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

/// @title Transient storage utils
/// @notice Provides utilities for reading from and writing to transient storage in EVM.
/// Transient storage is a temporary storage location that exists only during the execution of a transaction.
library TStorage {
    /// @notice Loads a value from transient storage at a given slot.
    /// @param slot The storage slot to read from, typically a unique identifier.
    /// @return value The value stored at the specified slot.
    function tload(uint256 slot) internal view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }

    /// @notice Loads a value from transient storage from a address slot.
    /// @param slot The storage slot to read from, typically an address converted to a slot.
    /// @return value The value stored at the specified slot.
    function tload(address slot) internal view returns (uint256 value) {
        assembly {
            value := tload(slot)
        }
    }

    /// @notice Loads a boolean value from transient storage at a given slot.
    /// @param slot The storage slot to read from.
    /// @return value The boolean value stored at the specified slot.
    function tload(bytes32 slot) internal view returns (bool value) {
        assembly {
            value := tload(slot)
        }
    }

    /// @notice Stores a value in transient storage at a given slot.
    /// @param slot The storage slot to write to.
    /// @param value The value to store at the specified slot.
    function tstore(uint256 slot, uint256 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /// @notice Stores a uint256 value in transient storage at a given 'address' slot.
    /// @param slot The storage slot to write to, typically an address converted to a slot.
    /// @param value The value to store at the specified slot.
    function tstore(address slot, uint256 value) internal {
        assembly {
            tstore(slot, value)
        }
    }

    /// @notice Stores a boolean value in transient storage at a given slot.
    /// @param slot The storage slot to write to.
    /// @param value The boolean value to store at the specified slot.
    function tstore(bytes32 slot, bool value) internal {
        assembly {
            tstore(slot, value)
        }
    }
}
