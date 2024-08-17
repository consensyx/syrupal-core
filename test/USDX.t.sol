// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {Errors} from "../src/libraries/Errors.sol";
import {Encoding} from "../src/external/Encoding.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Black76} from "../src/external/Black76.sol";
import {DecimalMath} from "../src/external/decimals/DecimalMath.sol";
import {ConvertDecimals} from "../src/external/decimals/ConvertDecimals.sol";

import {BaseSetup} from "./utils/BaseSetup.sol";
import {IAsset} from "../src/interfaces/IAsset.sol";
import {ILiquidation} from "../src/interfaces/ILiquidation.sol";

contract USDXTest is BaseSetup {
    using SafeCast for uint256;
    using SafeCast for int256;
    using ConvertDecimals for uint256;

    function setUp() public override {
        super.setUp();

        usdc.mint(alice, 1e12);
        usdc.mint(bob, 1e12);
    }

    function test_LossGreaterThanTotalUnderlying() public {
        uint256 depositAmount = 100000e18;
        _depositUSD(alice, aliceAcc, depositAmount);

        uint256 donateAmount = uint256(100e6).to18Decimals(6);
        usdc.mint(address(this), 100e6);
        usdc.approve(address(insuranceFund), 100e6);
        insuranceFund.donate(100e6);

        assertEq(usdc.balanceOf(address(usdx)), (depositAmount + donateAmount).from18Decimals(6));
        assertEq(usdx.totalSupply(), depositAmount + donateAmount);
        // recipient balance is equal donate amount
        assertEq(usdx.balances(1), donateAmount.toInt256());

        uint256 preTotalSupply = usdx.totalSupply();

        vm.startPrank(address(positionManager));

        int256 insolventAmount = 100e18;
        // adjustment amount greater than total deposit USDC amount
        int256 adjustmentAmount = -depositAmount.toInt256() - donateAmount.toInt256() - insolventAmount;

        IAsset.BalanceAdjustment memory adjustment =
            IAsset.BalanceAdjustment({accountId: 1, asset: usdx, subId: 0, amount: adjustmentAmount});

        usdx.updateBalance(adjustment, 1);
        usdx.updateTemporarySupply(adjustmentAmount);

        vm.stopPrank();

        assertEq(usdc.balanceOf(address(usdx)).to18Decimals(6), depositAmount + donateAmount);

        uint256 inflationSupply = (-(adjustmentAmount + donateAmount.toInt256())).toUint256();
        assertEq(usdx.totalSupply(), preTotalSupply + inflationSupply);

        // after socialize loss, insurance fund balance decrease to 0
        assertEq(usdx.balances(1), 0);
    }

    function test_LossLessThanTotalUnderlying() public {
        uint256 depositAmount = 100000e18;
        _depositUSD(alice, aliceAcc, depositAmount);

        uint256 donateAmount = uint256(100e6).to18Decimals(6);
        usdc.mint(address(this), 100e6);
        usdc.approve(address(insuranceFund), 100e6);
        insuranceFund.donate(100e6);

        assertEq(usdc.balanceOf(address(usdx)), (depositAmount + donateAmount).from18Decimals(6));
        assertEq(usdx.totalSupply(), depositAmount + donateAmount);
        // recipient balance is equal donate amount
        assertEq(usdx.balances(1), donateAmount.toInt256());

        uint256 preTotalSupply = usdx.totalSupply();

        vm.startPrank(address(positionManager));

        // adjustment amount less than total deposit USDC amount
        int256 adjustmentAmount = -10000e18;

        IAsset.BalanceAdjustment memory adjustment =
            IAsset.BalanceAdjustment({accountId: 1, asset: usdx, subId: 0, amount: adjustmentAmount});

        usdx.updateBalance(adjustment, 1);
        usdx.updateTemporarySupply(adjustmentAmount);

        vm.stopPrank();

        assertEq(usdc.balanceOf(address(usdx)).to18Decimals(6), depositAmount + donateAmount);

        uint256 inflationSupply = (-(adjustmentAmount + donateAmount.toInt256())).toUint256();
        assertEq(usdx.totalSupply(), preTotalSupply + inflationSupply);

        // after socialize loss, insurance fund balance decrease to 0
        assertEq(usdx.balances(1), 0);
    }

    function test_LossLessThanInsuranceFundBalance() public {
        uint256 depositAmount = 100000e18;
        _depositUSD(alice, aliceAcc, depositAmount);

        uint256 donateAmount = uint256(10000e6).to18Decimals(6);
        usdc.mint(address(this), 10000e6);
        usdc.approve(address(insuranceFund), 10000e6);
        insuranceFund.donate(10000e6);

        uint256 preTotalSupply = usdx.totalSupply();

        vm.startPrank(address(positionManager));

        // adjustment amount less than insurance fund balance
        int256 adjustmentAmount = -100e18;

        IAsset.BalanceAdjustment memory adjustment =
            IAsset.BalanceAdjustment({accountId: 1, asset: usdx, subId: 0, amount: adjustmentAmount});

        usdx.updateBalance(adjustment, 1);
        usdx.updateTemporarySupply(adjustmentAmount);

        vm.stopPrank();

        assertEq(usdc.balanceOf(address(usdx)).to18Decimals(6), depositAmount + donateAmount);

        // insurance fund balance can cover socialise loss, so, totalsupply will not change
        assertEq(usdx.totalSupply(), preTotalSupply);

        assertEq(usdx.balances(1), (donateAmount.toInt256() + adjustmentAmount));
    }

    // TO BE CONTINUE
}
