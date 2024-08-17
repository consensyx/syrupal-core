// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {InvariantTest} from "forge-std/InvariantTest.sol";

import {USDX} from "../../src/token/USDX.sol";
import {USDXHandler} from "./handlers/USDXHandler.sol";

import {BaseSetup} from "../utils/BaseSetup.sol";

contract USDX_Invariant_Test is InvariantTest, BaseSetup {
    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    USDXHandler internal usdxHandler;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        usdxHandler = new USDXHandler(usdx);

        targetContract(address(usdxHandler));

        // Prevent these contracts from being fuzzed as `msg.sender`.
        excludeSender(address(usdxHandler));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INVARIANTS
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_totalSupply() external {
        assertEq(usdx.totalSupply(), usdc.balanceOf(address(this)));
    }

    function invariant_callSummary() public view {
        usdxHandler.callSummary();
    }
}
