// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../../src/external/Encoding.sol";
import "../utils/IntegrationSetup.sol";

contract OptionExerciseTest is IntegrationSetup {
    using DecimalMath for uint256;

    int256 constant amount = 1e18;
    uint256 constant strike = 2000e18;

    uint112 callId;
    uint112 putId;
    uint16 marketId;
    uint64 expiry;

    function setUp() public {
        _setupIntegration();

        _depositUSD(alice, aliceAcc, DEFAULT_DEPOSIT);
        _depositUSD(bob, bobAcc, DEFAULT_DEPOSIT);

        expiry = uint64(block.timestamp) + 4 weeks;
        marketId = uint16(markets["weth"].id);
        callId = Encoding.toSubId(marketId, expiry, strike, true);
        putId = Encoding.toSubId(marketId, expiry, strike, false);

        _setSpotPrice("weth", 2000e18);
        _setForwardPrice("weth", expiry, 2000e18);
        _setDefaultSVIForExpiry("weth", expiry);
    }

    function test_settleShortCall() public {
        _tradeCall();

        vm.warp(expiry);
        _setSpotPrice("weth", 2500e18);
        _setSettlementPrice("weth", expiry, 2500e18);

        assertEq(hub.lastTxId(aliceAcc), 3);
        int256 aliceUSDBefore = getUSDXBalance(aliceAcc);
        uint256 oiBefore = option.openInterest(callId);

        positionManager.exercise(aliceAcc);
        int256 aliceUSDAfter = getUSDXBalance(aliceAcc);
        uint256 oiAfter = option.openInterest(callId);

        assertEq(hub.lastTxId(aliceAcc), 5);

        int256 expectedPayout = 500 * amount;

        assertEq(aliceUSDAfter, aliceUSDBefore - expectedPayout);

        assertEq(usdx.temporarySupply(), -expectedPayout);
        _assertExchangeRate();

        assertEq(oiAfter, oiBefore);
    }

    function test_settleLongCall() public {
        _tradeCall();

        vm.warp(expiry);
        _setSpotPrice("weth", 2500e18);
        _setSettlementPrice("weth", expiry, 2500e18);

        int256 bobUSDBefore = getUSDXBalance(bobAcc);

        positionManager.exercise(bobAcc);
        int256 bobUSDAfter = getUSDXBalance(bobAcc);
        uint256 oiAfter = option.openInterest(callId);

        int256 expectedPayout = 500 * amount;

        assertEq(bobUSDAfter, bobUSDBefore + expectedPayout);

        assertEq(usdx.temporarySupply(), expectedPayout);
        _assertExchangeRate();

        assertEq(oiAfter, 0);
    }

    function test_settleShortPut() public {
        _tradePut();

        vm.warp(expiry);
        _setSpotPrice("weth", 1500e18);
        _setSettlementPrice("weth", expiry, 1500e18);

        int256 aliceUSDBefore = getUSDXBalance(aliceAcc);

        positionManager.exercise(aliceAcc);
        int256 aliceUSDAfter = getUSDXBalance(aliceAcc);

        int256 expectedPayout = 500 * amount;

        assertEq(aliceUSDAfter, aliceUSDBefore - expectedPayout);

        assertEq(usdx.temporarySupply(), -expectedPayout);

        _assertExchangeRate();
    }

    function test_settleLongPut() public {
        _tradePut();

        vm.warp(expiry);
        _setSpotPrice("weth", 1500e18);
        _setSettlementPrice("weth", expiry, 1500e18);

        int256 bobUSDBefore = getUSDXBalance(bobAcc);

        positionManager.exercise(bobAcc);
        int256 bobUSDAfter = getUSDXBalance(bobAcc);
        uint256 oiAfter = option.openInterest(putId);

        int256 expectedPayout = 500 * amount;

        assertEq(bobUSDAfter, bobUSDBefore + expectedPayout);

        assertEq(usdx.temporarySupply(), expectedPayout);

        _assertExchangeRate();

        assertEq(oiAfter, 0);
    }

    function test_settleMultipleOptions() public {
        _depositUSD(alice, aliceAcc, DEFAULT_DEPOSIT * 3);

        _tradeCall();
        uint64 longExpiry = expiry + 14 days;
        _setForwardPrice("weth", longExpiry, 2000e18);
        _setDefaultSVIForExpiry("weth", longExpiry);

        uint112 longerDateCallId = Encoding.toSubId(marketId, longExpiry, strike, true);
        _trade(aliceAcc, option, longerDateCallId, amount, bobAcc, usdx, 0, 0);

        vm.warp(expiry);
        _setSpotPrice("weth", 1500e18);
        _setSettlementPrice("weth", expiry, 1500e18);

        positionManager.exercise(bobAcc);

        IAsset.AssetBalance[] memory assets = option.getAccountBalance(bobAcc);
        assertEq(assets.length, 1);

        vm.warp(longExpiry);
        _setSpotPrice("weth", 1500e18);

        positionManager.exercise(bobAcc);
        assets = option.getAccountBalance(bobAcc);
        assertEq(assets.length, 1);
    }

    function _tradeCall() public {
        int256 premium = 0;
        _trade(aliceAcc, option, callId, amount, bobAcc, usdx, 0, premium);
    }

    function _tradePut() public {
        int256 premium = 1750e18;
        _trade(aliceAcc, option, putId, amount, bobAcc, usdx, 0, premium);
    }
}
