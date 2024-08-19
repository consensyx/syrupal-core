// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {MockERC20} from "../src/mocks/MockERC20.sol";
import {Faucet} from "../src/mocks/Faucet.sol";

contract FaucetTest is Test {
    MockERC20 internal usdc;
    Faucet internal faucet;

    address internal alice = address(0x100);

    uint256 ETH_AMOUNT;

    function setUp() public {
        usdc = new MockERC20("USDC", "USDC", 6);

        faucet = new Faucet(usdc);

        ETH_AMOUNT = faucet.requiredETHAmount();

        vm.deal(alice, 10000 ether);

        assertEq(alice.balance, 10000 ether);

        usdc.mint(address(faucet), 100e18);
    }

    function test_claim() public {
        uint256 aliceBeforeBalance = usdc.balanceOf(alice);
        uint256 faucetBeforeBalance = usdc.balanceOf(address(faucet));

        vm.prank(alice);
        faucet.claim{value: ETH_AMOUNT}();

        uint256 aliceAfterBalance = usdc.balanceOf(alice);
        uint256 faucetfterBalance = usdc.balanceOf(address(faucet));

        assertEq(aliceBeforeBalance + faucet.claimAmount(), aliceAfterBalance);
        assertEq(faucetBeforeBalance - faucet.claimAmount(), faucetfterBalance);

        vm.prank(alice);
        vm.expectRevert("Lower ETH Amount to claim USDC");
        faucet.claim{value: ETH_AMOUNT - 1}();
    }

    function test_setClaimAmount() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        faucet.setClaimAmount(100);

        faucet.setClaimAmount(100);

        assertEq(faucet.claimAmount(), 100);

        vm.expectRevert("Invalid claim amount");
        faucet.setClaimAmount(0);
    }

    function test_setETHAmount() public {
        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        faucet.setETHAmount(0.02 ether);

        faucet.setETHAmount(0.02 ether);

        assertEq(faucet.requiredETHAmount(), 0.02 ether);

        faucet.setETHAmount(0);
        assertEq(faucet.requiredETHAmount(), 0);
    }

    function test_withdrawETH() public {
        assertEq(address(faucet).balance, 0);
        vm.prank(alice);
        faucet.claim{value: ETH_AMOUNT}();

        address payable bob = payable(address(0x101));

        vm.prank(alice);
        vm.expectRevert("Ownable: caller is not the owner");
        faucet.withdrawETH(bob);

        uint256 beforeBobBalance = address(bob).balance;
        uint256 beforeFaucetBalance = address(faucet).balance;
        faucet.withdrawETH(bob);

        uint256 afterBobBalance = address(bob).balance;
        uint256 afterFaucetBalance = address(faucet).balance;
        assertEq(beforeBobBalance + faucet.requiredETHAmount(), afterBobBalance);
        assertEq(beforeFaucetBalance - faucet.requiredETHAmount(), afterFaucetBalance);

        vm.expectRevert("No ETH to withdraw");
        faucet.withdrawETH(bob);

        vm.prank(alice);
        // can't send ETH to faucet
        (bool success,) = address(faucet).call{value: 10 ether}("");
        assertFalse(success);
    }
}
