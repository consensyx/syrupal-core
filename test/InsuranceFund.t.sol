// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

import {Errors} from "../src/libraries/Errors.sol";
import {Encoding} from "../src/external/Encoding.sol";
import {ConvertDecimals} from "../src/external/decimals/ConvertDecimals.sol";

import {IAsset} from "../src/interfaces/IAsset.sol";
import {Hub} from "../src/Hub.sol";
import {USDX} from "../src/token/USDX.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {BaseSetup} from "./utils/BaseSetup.sol";

import {MockERC20} from "../src/mocks/MockERC20.sol";

contract InsuranceFundTest is BaseSetup {
    using SafeCast for uint256;
    using SafeCast for int256;
    using ConvertDecimals for uint256;

    function setUp() public override {
        super.setUp();

        usdc.mint(alice, 1e12);
        usdc.mint(bob, 1e12);
    }

    function test_Donate() public {
        assertEq(usdx.balances(insuranceFund.recipient()), 0);

        uint256 donateAmount = 10e6;
        vm.startPrank(alice);
        usdc.approve(address(insuranceFund), donateAmount);
        insuranceFund.donate(donateAmount);
        vm.stopPrank();

        assertEq(usdx.balances(insuranceFund.recipient()).toUint256(), donateAmount.to18Decimals(usdc.decimals()));
    }

    function test_Withdraw() public {
        assertEq(usdx.balances(insuranceFund.recipient()), 0);

        uint256 donateAmount = 1234567;
        vm.startPrank(alice);
        usdc.approve(address(insuranceFund), donateAmount);
        insuranceFund.donate(donateAmount);
        vm.stopPrank();

        address david = address(0xcc);

        vm.startPrank(alice);
        vm.expectRevert(Errors.OnlyOperator.selector);
        insuranceFund.withdraw(donateAmount, david);
        vm.stopPrank();

        insuranceFund.withdraw(donateAmount, david);

        assertEq(usdc.balanceOf(david), donateAmount);
    }

    function test_CreateRecipient() public {
        vm.expectRevert(Errors.OnlyOneRecipient.selector);
        insuranceFund.createRecipient();
    }

    function test_PayInsolvency() public {
        uint256 depositAmount = 100000e18;
        _depositUSD(alice, aliceAcc, depositAmount);

        assertEq(usdc.balanceOf(address(usdx)), (depositAmount).from18Decimals(6));
        assertEq(usdx.totalSupply(), depositAmount);

        uint256 preTotalSupply = usdx.totalSupply();

        vm.startPrank(address(positionManager));
        // deduct amount greater than insurance fund balance
        int256 lossAmount = -200e18;
        IAsset.BalanceAdjustment memory adjustment =
            IAsset.BalanceAdjustment({accountId: 1, asset: usdx, subId: 0, amount: lossAmount});

        usdx.updateBalance(adjustment, 1);
        usdx.updateTemporarySupply(lossAmount);
        vm.stopPrank();

        assertEq(usdx.totalSupply(), preTotalSupply + (-lossAmount).toUint256());

        uint256 donateAmount = uint256(300e6).to18Decimals(6);
        usdc.mint(address(this), 300e6);
        usdc.approve(address(insuranceFund), 300e6);
        insuranceFund.donate(300e6);

        // donateAmount > (-lossAmount)
        assertEq(usdx.balances(1), donateAmount.toInt256());

        // anyone can call payInsolvency
        vm.prank(alice);
        insuranceFund.payInsolvency();

        // after payInsolvency, usdx totalySupply will equal to usdc amount
        assertEq(usdx.totalSupply(), usdc.balanceOf(address(usdx)).to18Decimals(6));
        // after payInsolvency, insurance fund balance will deduct actual burn amount
        assertEq(usdx.balances(1), donateAmount.toInt256() + lossAmount);
    }

    function test_resetApproval() public {
        assertEq(usdx.stablecoin().allowance(address(insuranceFund), address(usdx)), type(uint256).max);

        uint256 newApproveAmount = type(uint128).max;
        insuranceFund.resetApproval(newApproveAmount);

        assertEq(usdx.stablecoin().allowance(address(insuranceFund), address(usdx)), newApproveAmount);

        vm.startPrank(alice);
        vm.expectRevert(Errors.OnlyOperator.selector);
        insuranceFund.resetApproval(newApproveAmount);
        vm.stopPrank();
    }

    function test_SetOperator() public {
        assertEq(insuranceFund.operator(), address(this));

        insuranceFund.setOperator(alice);

        vm.startPrank(bob);
        vm.expectRevert(Errors.OnlyOperator.selector);
        insuranceFund.resetApproval(1e18);
        vm.stopPrank();

        vm.startPrank(alice);
        insuranceFund.resetApproval(1e18);
        vm.stopPrank();

        assertEq(usdx.stablecoin().allowance(address(insuranceFund), address(usdx)), 1e18);
    }

    function test_RescueERC20() public {
        MockERC20 randomToken = new MockERC20("WETH", "WETH", 6);

        randomToken.mint(alice, 1e18);

        vm.startPrank(alice);
        randomToken.transfer(address(insuranceFund), 1e18);
        vm.stopPrank();

        insuranceFund.rescueERC20(address(randomToken), bob, 10e8);

        assertEq(randomToken.balanceOf(bob), 10e8);
    }
}
