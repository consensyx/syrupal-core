// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {StdInvariant} from "forge-std/StdInvariant.sol";

import {ConvertDecimals} from "../../src/external/decimals/ConvertDecimals.sol";

import {USDX} from "../../src/token/USDX.sol";
import {BaseTest} from "./Base.t.sol";
import {USDXHandler} from "./handlers/USDXHandler.sol";

contract USDX_Invariant_Test is StdInvariant, BaseTest {
    using ConvertDecimals for uint256;

    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    USDXHandler internal usdxHandler;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public override {
        super.setUp();

        usdxHandler = new USDXHandler(usdx, usdc, positionManager, address(this));

        targetContract(address(usdxHandler));

        // Prevent these contracts from being fuzzed as `msg.sender`.
        excludeSender(address(usdxHandler));
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INVARIANTS
    //////////////////////////////////////////////////////////////////////////*/

    function invariant_totalSupply() public view {
        assertEq(usdx.totalSupply().from18Decimals(6), usdxHandler.ghost_depositSum() - usdxHandler.ghost_withdrawSum());
    }

    function invariant_callSummary() public view {
        usdxHandler.callSummary();
    }
}
