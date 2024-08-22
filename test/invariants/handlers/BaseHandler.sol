// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {console} from "forge-std/console.sol";

/// @notice Base contract with common logic needed by all handler contracts.
abstract contract BaseHandler {
    /*//////////////////////////////////////////////////////////////////////////
                                    STATE-VARIABLES
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Maps function names to the number of times they have been called.
    mapping(string func => uint256 calls) public calls;

    /// @dev The total number of calls made to this contract.
    uint256 public totalCalls;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Default ERC-20 asset used for testing.
    // IERC20 public asset;

    /*//////////////////////////////////////////////////////////////////////////
                                    CONSTRUCTOR
    //////////////////////////////////////////////////////////////////////////*/

    // constructor(IERC20 asset_) {
    //     asset = asset_;
    // }

    /*//////////////////////////////////////////////////////////////////////////
                                     MODIFIERS
    //////////////////////////////////////////////////////////////////////////*/

    /// @dev Records a function call for instrumentation purposes.
    modifier countCall(string memory functionName) {
        calls[functionName]++;
        totalCalls++;
        _;
    }

    /// @dev Simulates the passage of time. The time jump is upper bounded so that streams don't settle too quickly.
    /// @param timeJumpSeed A fuzzed value needed for generating random time warps.
    // modifier advanceTimestamp(uint256 timeJumpSeed) {
    //     uint256 timeJump = bound(timeJumpSeed, 2 minutes, 40 days);
    //     vm.warp(block.timestamp + timeJump);
    //     _;
    // }

    /// @dev Checks user assumptions.
    // modifier checkUsers(address sender, address recipient, address broker) {
    //     // The protocol doesn't allow the sender, recipient or broker to be the zero address.
    //     if (sender == address(0) || recipient == address(0) || broker == address(0)) {
    //         return;
    //     }

    //     // Prevent the contract itself from playing the role of any user.
    //     if (sender == address(this) || recipient == address(this) || broker == address(this)) {
    //         return;
    //     }

    //     _;
    // }

    function callSummary() external view {
        console.log("Call summary:");
        console.log("-------------------");
        console.log("deposit", calls["deposit"]);
        console.log("withdraw", calls["withdraw"]);
        console.log("totalCalls", totalCalls);
    }
}
