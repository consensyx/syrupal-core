// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Encoding} from "../../src/external/Encoding.sol";
import {ManagerStorage} from "../../src/ManagerStorage.sol";
import {MarginBaseSetup} from "./MarginBaseSetup.sol";

contract MarginScenarioTest is MarginBaseSetup {
    function testIMAndMMCallMargin() public {
        // tx1
        uint112 positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 76500e18, true);
        uint256 markPrice = 558.0182e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx2
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 70000e18, true);
        markPrice = 2403.2663e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry2, 68500e18, true);
        markPrice = 3218.7578e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 19130.1132e18, 1e18);
        assertApproxEqAbs(aliceMM, 51220.1132e18, 1e18);
    }

    function testIMAndMMPutMargin() public {
        // tx1
        uint112 positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 63500e18, false);
        uint256 markPrice = 479.6486e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx2
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 70000e18, false);
        markPrice = 2403.2663e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry2, 71500e18, false);
        markPrice = 3253.1979e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 19845.1132e18, 1e18);
        assertApproxEqAbs(aliceMM, 51770.1132e18, 1e18);
    }

    function testLongCallAndShortCall() public {
        // tx1
        uint112 positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 77777e18, true);
        uint256 markPrice = 413.9019e18;

        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx2
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 75643e18, true);
        markPrice = 682.0768e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 777777e18, true);
        markPrice = 413.9019e18;

        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx4
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 75643e18, true);
        markPrice = 682.0768e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));
        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 36932.3094e18, 1e18);
        assertApproxEqAbs(aliceMM, 57292.3094e18, 1e18);
    }

    function testLongPutAndShortPut() public {
        // tx1
        uint112 positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 67232e18, false);
        uint256 markPrice = 1266.6322e18;

        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx2
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 73923e18, false);
        markPrice = 4940.6005e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 67232e18, false);
        markPrice = 1266.6322e18;

        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx4
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 73923e18, false);
        markPrice = 4940.6005e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 25566.8488e18, 1e18);
        assertApproxEqAbs(aliceMM, 55586.8488e18, 1e18);
    }

    function testReduceCallPosition() public {
        // tx1
        uint112 positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 77777e18, true);
        uint256 markPrice = 413.9019e18;

        _trade(bobAcc, positionId, 1e18, aliceAcc, int256(markPrice));

        // tx2
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 77777e18, true);
        markPrice = 0.5 * 413.9019e18;

        _trade(aliceAcc, positionId, 0.5e18, bobAcc, int256(markPrice));

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 77777e18, true);
        markPrice = 1.2 * 413.9019e18;

        _trade(aliceAcc, positionId, 1.2e18, bobAcc, int256(markPrice));

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 77777e18, true);
        markPrice = 0.3 * 413.9019e18;

        _trade(bobAcc, positionId, 0.3e18, aliceAcc, int256(markPrice));

        // tx4
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 77777e18, true);
        markPrice = 2 * 413.9019e18;

        _trade(bobAcc, positionId, 2e18, aliceAcc, int256(markPrice));

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 55037.87016e18, 1e18);
        assertApproxEqAbs(aliceMM, 71257.87016e18, 1e18);
    }

    function testReducePutPosition() public {
        // tx1
        uint112 positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 67232e18, false);
        uint256 markPrice = 0.3 * 1266.6322e18;

        _trade(bobAcc, positionId, 0.3e18, aliceAcc, int256(markPrice));

        // tx2
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 67232e18, false);
        markPrice = 0.1 * 1266.6322e18;

        _trade(aliceAcc, positionId, 0.1e18, bobAcc, int256(markPrice));

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 55446.78676e18, 1e18);
        assertApproxEqAbs(aliceMM, 71666.78676e18, 1e18);

        // tx3
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 67232e18, false);
        markPrice = 1266.6322e18;

        _trade(aliceAcc, positionId, 1e18, bobAcc, int256(markPrice));

        // tx4
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 67232e18, false);
        markPrice = 0.4 * 1266.6322e18;

        _trade(bobAcc, positionId, 0.4e18, aliceAcc, int256(markPrice));

        // tx5
        positionId = Encoding.toSubId(markets["BTC"].id, expiry1, 67232e18, false);
        markPrice = 1.1 * 1266.6322e18;

        _trade(bobAcc, positionId, 1.1e18, aliceAcc, int256(markPrice));

        aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 54813.4706599999e18, 1e18);
        assertApproxEqAbs(aliceMM, 71033.47066e18, 1e18);
    }

    function testDepegMargin() public {
        positionManager.setDepegParams(ManagerStorage.DepegParams(0.97e18, 1.2e18));

        vm.warp(block.timestamp + 1);
        _setStablePrice(0.95e18);

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 54373.6588536e18, 1e18);
        assertApproxEqAbs(aliceMM, 71920.1132e18, 1e18);

        vm.warp(block.timestamp + 1);
        _setStablePrice(0.98e18);

        aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        aliceMM = positionManager.getTotalMargin(aliceAcc, false);
        assertApproxEqAbs(aliceIM, 55700.1132e18, 1e18);
        assertApproxEqAbs(aliceMM, 71920.1132e18, 1e18);

        vm.warp(block.timestamp + 1);
        _setStablePrice(1.02e18);

        aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 55700.1132e18, 1e18);
        assertApproxEqAbs(aliceMM, 71920.1132e18, 1e18);
    }

    function testExerciseMargin() public {
        vm.warp(expiry1);
        _setStablePrice(1e18);

        _setSpotPrice("BTC", 71000e18);
        _setSpotPrice("ETH", 3600e18);

        _setForwardPrice("BTC", uint64(expiry1), 71000e18);
        _setForwardPrice("BTC", uint64(expiry2), 72300e18);

        _setForwardPrice("ETH", uint64(expiry1), 3600e18);
        _setForwardPrice("ETH", uint64(expiry2), 3670e18);

        _setVolatility("BTC", 72300e18, uint64(expiry2), getDefaultBTCSVI());

        _setVolatility("ETH", 3670e18, uint64(expiry2), getDefaultETHSVI());

        positionManager.exercise(aliceAcc);

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 83035.5618821577e18, 1e18);
        assertApproxEqAbs(aliceMM, 87844.1096e18, 1e18);

        vm.warp(expiry2);
        _setStablePrice(1e18);

        _setSpotPrice("BTC", 73000e18);
        _setSpotPrice("ETH", 3800e18);

        _setForwardPrice("BTC", uint64(expiry2), 73000e18);

        _setForwardPrice("ETH", uint64(expiry2), 3800e18);

        positionManager.exercise(aliceAcc);

        aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 96969.0443e18, 1e18);
        assertApproxEqAbs(aliceMM, 96969.0443e18, 1e18);
    }

    function testVolatilityMargin() public {
        // 2 days later
        vm.warp(INITIAL_TIME + 3600 * 48);
        _setStablePrice(1e18);

        _setSpotPrice("BTC", 75900e18);
        _setSpotPrice("ETH", 3850e18);

        _setForwardPrice("BTC", uint64(expiry1), 77000e18);
        _setForwardPrice("BTC", uint64(expiry2), 77000e18);

        _setForwardPrice("ETH", uint64(expiry1), 3960e18);
        _setForwardPrice("ETH", uint64(expiry2), 3960e18);

        _setVolatility("BTC", 77000e18, uint64(expiry1), getDefaultBTCSVI());
        _setVolatility("BTC", 77000e18, uint64(expiry2), getDefaultBTCSVI());

        _setVolatility("ETH", 3960e18, uint64(expiry1), getDefaultETHSVI());
        _setVolatility("ETH", 3960e18, uint64(expiry2), getDefaultETHSVI());

        int256 aliceIM = positionManager.getTotalMargin(aliceAcc, true);
        int256 aliceMM = positionManager.getTotalMargin(aliceAcc, false);

        assertApproxEqAbs(aliceIM, 43591.1857555556e18, 1e18);
        assertApproxEqAbs(aliceMM, 66595.6302e18, 1e18);
    }
}
