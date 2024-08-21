// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {Errors} from "../src/libraries/Errors.sol";
import {Encoding} from "../src/external/Encoding.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Black76} from "../src/external/Black76.sol";
import {DecimalMath} from "../src/external/decimals/DecimalMath.sol";

import {BaseSetup} from "./utils/BaseSetup.sol";
import {ILiquidation} from "../src/interfaces/ILiquidation.sol";

contract LiquidationTest is BaseSetup {
    using SafeCast for uint256;
    using SafeCast for int256;
    using DecimalMath for uint256;

    address internal tom = address(0x201);
    uint256 tomAcc;

    uint256 INITIAL_DEPOSIT = 15000e18;

    // 2024-05-21 12:00 UTC
    uint256 INITIAL_TIME = 1716292800;

    // 2024-6-28 8:00 UTC
    uint256 expiry1 = 1719561600;
    // 2024-6-07 8:00 UTC
    uint256 liquidationTime = 1717747200;

    uint256 defaultPositionId;
    int256 defaultAmount = 1e18;
    uint256 defualtMarkPrice = 1951.94904939114e18;

    function setUp() public override {
        super.setUp();
        liquidation.setLiquidator(address(this));

        positionManager.setLiquidator(address(this), true);
        positionManager.setFeeRecipient(insuranceFund.recipient());

        vm.warp(INITIAL_TIME);
        _submitOracleData();

        tomAcc = positionManager.createSubAccount(tom);
        vm.prank(tom);
        positionManager.approve(address(this), tomAcc);
        vm.stopPrank();

        _depositUSD(tom, tomAcc, INITIAL_DEPOSIT);
        _depositUSD(alice, aliceAcc, 100000e18);

        defaultPositionId = Encoding.toSubId(markets["BTC"].id, expiry1, 71000e18, true);
        _trade(tomAcc, defaultPositionId.toUint112(), defaultAmount, aliceAcc, int256(defualtMarkPrice));
    }

    function test_canotStartLiquidate() public {
        int256 tomMM = positionManager.getTotalMargin(tomAcc, false);
        assertTrue(tomMM > 0);
        vm.expectRevert(Errors.CannotStartLiquidation.selector);
        liquidation.startLiquidation(tomAcc);
    }

    function test_canStartLiquidate() public {
        _updateMarketForLiquidate(liquidationTime);

        int256 tomMM = positionManager.getTotalMargin(tomAcc, false);
        assertTrue(tomMM < 0);
        liquidation.startLiquidation(tomAcc);
        assertTrue(liquidation.liquidatedAccounts(tomAcc));
    }

    function test_canotStopLiquidate() public {
        _updateMarketForLiquidate(liquidationTime);
        int256 tomMM = positionManager.getTotalMargin(tomAcc, false);
        assertTrue(tomMM < 0);
        liquidation.startLiquidation(tomAcc);
        vm.expectRevert(Errors.CannotStopLiquidation.selector);
        liquidation.stopLiquidation(tomAcc);
    }

    function test_canStopLiquidate() public {
        // TODO
    }

    function test_notLiquidatorCanottakeOver() public {
        vm.prank(alice);
        vm.expectRevert(Errors.OnlyLiquidator.selector);
        positionManager.takeover(tomAcc);
        vm.stopPrank();
    }

    function test_canotTakeOverNotLiquidatedAccount() public {
        vm.expectRevert(Errors.NotLiquidatedAccount.selector);
        positionManager.takeover(tomAcc);
    }

    function test_canTakeOverLiquidatedAccount() public {
        _updateMarketForLiquidate(liquidationTime);
        liquidation.startLiquidation(tomAcc);

        int256 tomBeforeBalance = option.getPositionBalance(tomAcc, defaultPositionId);
        int256 tomBeforeUSDBalance = usdx.balances(tomAcc);

        uint256 insuranceAcc = insuranceFund.recipient();
        int256 insuranceBeforeBalance = option.getPositionBalance(insuranceAcc, defaultPositionId);
        int256 insuranceBeforeUSDBalance = usdx.balances(insuranceAcc);

        positionManager.takeover(tomAcc);

        int256 tomAfterBalance = option.getPositionBalance(tomAcc, defaultPositionId);
        int256 tomAfterUSDBalance = usdx.balances(tomAcc);

        int256 insuranceAfterBalance = option.getPositionBalance(insuranceAcc, defaultPositionId);
        int256 insuranceAfterUSDBalance = usdx.balances(insuranceAcc);

        assertEq(tomAfterBalance, 0);
        assertEq(tomAfterUSDBalance, 0);

        assertEq(insuranceAfterBalance, insuranceBeforeBalance + tomBeforeBalance);
        assertEq(insuranceAfterUSDBalance, insuranceBeforeUSDBalance + tomBeforeUSDBalance);
    }

    function test_canAutoDeleverage() public {
        _updateMarketForLiquidate(liquidationTime);

        liquidation.startLiquidation(tomAcc);
        positionManager.takeover(tomAcc);

        vm.warp(liquidationTime + 12 hours);

        _updateMarketForLiquidate(liquidationTime + 12 hours);

        ILiquidation.LiquidationTransfer[] memory transfers = new ILiquidation.LiquidationTransfer[](1);

        uint256 insuranceAcc = insuranceFund.recipient();
        _depositUSD(address(insuranceFund), insuranceAcc, 100e18);

        // int256 aliceBeforeUSDBalance = usdx.balances(aliceAcc);

        // int256 insuranceBeforeUSDBalance = usdx.balances(insuranceAcc);

        // choose alice as counterpart to deleverage
        transfers[0] = ILiquidation.LiquidationTransfer({
            counterParty: aliceAcc,
            amount: defaultAmount,
            subId: defaultPositionId.toUint112()
        });

        // uint256 vol = markets["BTC"].volOracle.getVol(71000e18, expiry1.toUint64());
        // uint256 currentMarkPrice = _calcBSMPrice(80000e18, 71000e18, expiry1, vol, true);

        positionManager.autoDeleverage(transfers);

        int256 insuranceAfterBalance = option.getPositionBalance(insuranceAcc, defaultPositionId);
        // int256 insuranceAfterUSDBalance = usdx.balances(insuranceAcc);

        int256 aliceAfterBalance = option.getPositionBalance(aliceAcc, defaultPositionId);
        // int256 aliceAfterUSDBalance = usdx.balances(aliceAcc);

        assertEq(insuranceAfterBalance, 0);
        assertEq(aliceAfterBalance, 0);

        // assertEq(aliceAfterUSDBalance, aliceBeforeUSDBalance + currentMarkPrice.toInt256());
        // assertEq(insuranceAfterUSDBalance, insuranceBeforeUSDBalance - currentMarkPrice.toInt256());
    }

    function test_AutoDeleverageWithSocializeLoss() public {
        _updateMarketForLiquidate(liquidationTime);

        liquidation.startLiquidation(tomAcc);
        positionManager.takeover(tomAcc);

        vm.warp(liquidationTime + 12 hours);

        _updateMarketForLiquidate(liquidationTime + 12 hours);

        ILiquidation.LiquidationTransfer[] memory transfers = new ILiquidation.LiquidationTransfer[](1);

        uint256 insuranceAcc = insuranceFund.recipient();

        // int256 aliceBeforeUSDBalance = usdx.balances(aliceAcc);

        // int256 insuranceBeforeUSDBalance = usdx.balances(insuranceAcc);

        // choose alice as counterpart to deleverage
        transfers[0] = ILiquidation.LiquidationTransfer({
            counterParty: aliceAcc,
            amount: defaultAmount,
            subId: defaultPositionId.toUint112()
        });

        // uint256 vol = markets["BTC"].volOracle.getVol(71000e18, expiry1.toUint64());
        // uint256 currentMarkPrice = _calcBSMPrice(80000e18, 71000e18, expiry1, vol, true);

        // TODO: make sure insurance fund usdx balance < market value
        positionManager.autoDeleverage(transfers);

        int256 insuranceAfterBalance = option.getPositionBalance(insuranceAcc, defaultPositionId);
        // int256 insuranceAfterUSDBalance = usdx.balances(insuranceAcc);

        int256 aliceAfterBalance = option.getPositionBalance(aliceAcc, defaultPositionId);
        // int256 aliceAfterUSDBalance = usdx.balances(aliceAcc);

        assertEq(insuranceAfterBalance, 0);
        assertEq(aliceAfterBalance, 0);

        // assertEq(aliceAfterUSDBalance, aliceBeforeUSDBalance + currentMarkPrice.toInt256());
        // assertEq(insuranceAfterUSDBalance, insuranceBeforeUSDBalance - currentMarkPrice.toInt256());
    }

    function _submitOracleData() internal {
        _setStablePrice(1e18);

        _setSpotPrice("BTC", 69000e18);

        _setForwardPrice("BTC", uint64(expiry1), 70000e18);
        _setVolatility("BTC", 70000e18, uint64(expiry1), getDefaultBTCSVI());
    }

    function _updateMarketForLiquidate(uint256 _liquidateTime) internal {
        vm.warp(_liquidateTime);
        _setStablePrice(1e18);
        _setSpotPrice("BTC", 79000e18);
        _setForwardPrice("BTC", uint64(expiry1), 80000e18);
        _setVolatility("BTC", 80000e18, uint64(expiry1), getDefaultBTCSVI());
    }

    function _calcBSMPrice(uint256 forwardPrice, uint256 strike, uint256 expiry, uint256 vol, bool isCall)
        internal
        view
        returns (uint256)
    {
        uint64 secToExpiry = expiry > block.timestamp ? uint64(expiry - block.timestamp) : 0;

        (uint256 call, uint256 put) = Black76.prices(
            Black76.Black76Inputs({
                timeToExpirySec: secToExpiry,
                volatility: vol.toUint128(),
                fwdPrice: forwardPrice.toUint128(),
                strikePrice: strike.toUint128(),
                discount: 1e18
            })
        );

        return isCall ? call : put;
    }
}
