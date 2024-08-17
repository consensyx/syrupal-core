// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

import {Errors} from "../../src/libraries/Errors.sol";
import {Encoding} from "../../src/external/Encoding.sol";
import {Black76} from "../../src/external/Black76.sol";
import {DecimalMath} from "../../src/external/decimals/DecimalMath.sol";
import {ConvertDecimals} from "../../src/external/decimals/ConvertDecimals.sol";
import {IAsset} from "../../src/interfaces/IAsset.sol";
import {ILiquidation} from "../../src/interfaces/ILiquidation.sol";
import {BaseSetup} from "../utils/BaseSetup.sol";

contract OptionTest is BaseSetup {
    using SafeCast for uint256;
    using SafeCast for int256;
    using ConvertDecimals for uint256;

    address internal tom = address(0x103);
    uint256 internal tomAcc;

    address internal jerry = address(0x104);
    uint256 internal jerryAcc;

    uint256 constant INITIAL_DEPOSIT = 1000000e18;

    uint256 INITIAL_TIME = 1716292800;

    uint256 expiry = 1717747200;

    function setUp() public override {
        super.setUp();

        tomAcc = positionManager.createSubAccount(tom);
        vm.prank(tom);
        positionManager.approve(address(this), tomAcc);
        vm.stopPrank();

        jerryAcc = positionManager.createSubAccount(jerry);
        vm.prank(jerry);
        positionManager.approve(address(this), jerryAcc);
        vm.stopPrank();

        usdc.mint(alice, 1e12);
        usdc.mint(bob, 1e12);
        usdc.mint(tom, 1e12);
        usdc.mint(jerry, 1e12);

        _setupBaseline();
    }

    function test_openInterest() public {
        uint112 subId = Encoding.toSubId(markets["BTC"].id, expiry, 72000e18, true);

        // alice short and bob long, the open interest is 1e18
        _trade(aliceAcc, subId, 1e18, bobAcc, 0);

        assertEq(option.openInterest(subId), 1e18);

        // bob close his position by sell it to tom
        _trade(bobAcc, subId, 1e18, tomAcc, 0);

        assertEq(option.openInterest(subId), 1e18);

        // tom short half of his position to jerry
        _trade(tomAcc, subId, 0.5e18, jerryAcc, 0);

        assertEq(option.openInterest(subId), 1e18);

        // tom short all remaining position to alice, this will cause the total open position decrease to 0.5e18
        _trade(tomAcc, subId, 0.5e18, aliceAcc, 0);

        assertEq(option.openInterest(subId), 0.5e18);

        // jerry short all his open position, after that, the open position is 0
        _trade(jerryAcc, subId, 0.5e18, aliceAcc, 0);

        assertEq(option.openInterest(subId), 0);
    }

    function test_setForwardOracle() public {
        option.setForwardOracle(1, address(0));

        assertEq(address(option.forwardOracle(1)), address(0));

        // revert if called by non owner
        vm.prank(address(0xff));
        vm.expectRevert("Ownable: caller is not the owner");
        option.setForwardOracle(1, address(0));

        // revert if marketid not exist
        vm.expectRevert(Errors.NotExistMarket.selector);
        option.setForwardOracle(3, address(0));
    }

    function test_setOpenInterestFee() public {
        uint256 defaultFee = 0.1e18;
        option.setOIFee(defaultFee);

        assertEq(option.OIFee(), defaultFee);

        // revert if called by non owner
        vm.prank(address(0xff));
        vm.expectRevert("Ownable: caller is not the owner");
        option.setOIFee(defaultFee);

        vm.expectRevert(Errors.InvalidOIFee.selector);
        option.setOIFee(1.5e18);
    }

    function test_updateBalance() public {
        uint112 subId = Encoding.toSubId(markets["BTC"].id, expiry, 72000e18, true);

        uint256 accountId = 10;
        IAsset.BalanceAdjustment memory adjustment =
            IAsset.BalanceAdjustment({accountId: accountId, asset: option, subId: subId, amount: 10e18});

        vm.expectRevert(Errors.OnlyProtocol.selector);
        option.updateBalance(adjustment, 1);

        // balance +10e18
        vm.startPrank(address(positionManager));
        option.updateBalance(adjustment, 2);

        assertEq(option.getPositionBalance(accountId, subId), 10e18);

        // balance -5e18
        adjustment = IAsset.BalanceAdjustment({accountId: accountId, asset: option, subId: subId, amount: -5e18});
        option.updateBalance(adjustment, 3);

        assertEq(option.getPositionBalance(accountId, subId), 5e18);

        // balance -5e18, balance will be 0
        adjustment = IAsset.BalanceAdjustment({accountId: accountId, asset: option, subId: subId, amount: -5e18});
        option.updateBalance(adjustment, 4);

        assertEq(option.getPositionBalance(accountId, subId), 0);

        vm.stopPrank();
    }

    function test_getAccountBalance() public {
        uint112 subId1 = Encoding.toSubId(markets["BTC"].id, expiry, 5000e18, true);
        uint112 subId2 = Encoding.toSubId(markets["ETH"].id, expiry, 6000e18, true);
        uint112 subId3 = Encoding.toSubId(markets["BTC"].id, expiry, 7000e18, true);
        uint112 subId4 = Encoding.toSubId(markets["ETH"].id, expiry, 8000e18, true);

        // alice short and bob long, the open interest is 1e18
        _trade(aliceAcc, subId1, 1e18, bobAcc, 0);
        _trade(aliceAcc, subId2, 1e18, bobAcc, 0);
        _trade(bobAcc, subId3, 1e18, aliceAcc, 0);
        _trade(bobAcc, subId4, 1e18, aliceAcc, 0);

        IAsset.AssetBalance[] memory assetBalances = option.getAccountBalance(aliceAcc);

        assertEq(assetBalances.length, 4);

        assetBalances[0].subId = subId1;
        assetBalances[0].balance = -1e18;

        assetBalances[1].subId = subId2;
        assetBalances[1].balance = -1e18;

        assetBalances[2].subId = subId3;
        assetBalances[2].balance = 1e18;

        assetBalances[3].subId = subId4;
        assetBalances[3].balance = 1e18;
    }

    function _setupBaseline() internal {
        vm.warp(INITIAL_TIME);

        _submitOracleData();

        _depositUSD(alice, aliceAcc, INITIAL_DEPOSIT);
        _depositUSD(bob, bobAcc, INITIAL_DEPOSIT);
        _depositUSD(tom, tomAcc, INITIAL_DEPOSIT);
        _depositUSD(jerry, jerryAcc, INITIAL_DEPOSIT);
    }

    function _submitOracleData() internal {
        _setStablePrice(1e18);

        _setSpotPrice("BTC", 69000e18);
        _setForwardPrice("BTC", uint64(expiry), 70000e18);
        _setVolatility("BTC", 70000e18, uint64(expiry), getDefaultBTCSVI());

        _setSpotPrice("ETH", 3500e18);
        _setForwardPrice("ETH", uint64(expiry), 3600e18);
        _setVolatility("ETH", 3600e18, uint64(expiry), getDefaultBTCSVI());
    }
}
