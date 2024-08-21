// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Encoding} from "../../src/external/Encoding.sol";

import {BaseSetup} from "../utils/BaseSetup.sol";

contract MarginBaseSetup is BaseSetup {
    uint256 constant INITIAL_DEPOSIT = 100000e18;

    // 2024-05-21 12:00 UTC
    uint256 INITIAL_TIME = 1716292800;

    // 2024-6-7 8:00 UTC
    uint256 expiry1 = 1717747200;
    // 2024-6-28 8:00 UTC
    uint256 expiry2 = 1719561600;

    function setUp() public virtual override {
        super.setUp();

        _setupBaseline();
    }

    function _setupBaseline() internal {
        vm.warp(INITIAL_TIME);

        _submitOracleData();

        _depositUSD(alice, aliceAcc, INITIAL_DEPOSIT);
        _depositUSD(bob, bobAcc, INITIAL_DEPOSIT);

        // tx1
        uint112 positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 72000e18, true);
        uint256 markPrice = 1571.7329e18;

        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx2
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 65000e18, true);

        markPrice = 5714.5967e18;
        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry2, 70000e18, false);

        markPrice = 2403.4011e18;
        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx4
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 81000e18, false);

        markPrice = 11197.1546e18;
        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx5
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 69000e18, true);

        markPrice = 2928.3855e18;
        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx6
        positionId = Encoding.toSubId(markets["BTC"].id, expiry2, 75000e18, true);

        markPrice = 792.6517e18;
        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx7
        positionId = Encoding.toSubId(markets["ETH"].id, expiry1, 3700e18, true);

        markPrice = 126.3673e18;
        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx8
        positionId = Encoding.toSubId(markets["ETH"].id, expiry2, 3800e18, false);

        markPrice = 294.5281e18;
        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 55700.1132e18, 1e18);
        assertApproxEqAbs(aliceMM, 71920.1132e18, 1e18);
    }

    function _submitOracleData() internal {
        _setStablePrice(1e18);

        _setSpotPrice("BTC", 69000e18);
        _setSpotPrice("ETH", 3500e18);

        _setForwardPrice("BTC", uint64(expiry1), 70000e18);
        _setForwardPrice("BTC", uint64(expiry2), 70000e18);

        _setForwardPrice("ETH", uint64(expiry1), 3600e18);
        _setForwardPrice("ETH", uint64(expiry2), 3600e18);

        _setVolatility("BTC", 70000e18, uint64(expiry1), getDefaultBTCSVI());
        _setVolatility("BTC", 70000e18, uint64(expiry2), getDefaultBTCSVI());

        _setVolatility("ETH", 3600e18, uint64(expiry1), getDefaultETHSVI());
        _setVolatility("ETH", 3600e18, uint64(expiry2), getDefaultETHSVI());
    }
}
