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
import {ISpotOracle} from "../src/oracle/interfaces/ISpotOracle.sol";
import {IForwardOracle} from "../src/oracle/interfaces/IForwardOracle.sol";
import {IVolatilityOracle} from "../src/oracle/interfaces/IVolatilityOracle.sol";

contract PositionManagerTest is BaseSetup {
    using SafeCast for uint256;
    using SafeCast for int256;
    using ConvertDecimals for uint256;

    function setUp() public override {
        super.setUp();
    }

    function test_setOperator() public {
        address operator = address(0x1234);
        positionManager.setOperator(operator);

        assertEq(positionManager.operator(), operator);

        vm.prank(operator);
        address liquidator = address(0x2345);
        positionManager.setLiquidator(liquidator, true);

        assertEq(positionManager.trustedLiquidator(liquidator), true);

        vm.prank(address(0xff));
        vm.expectRevert("Ownable: caller is not the owner");
        positionManager.setOperator(operator);

        vm.expectRevert(Errors.ZeroAddress.selector);
        positionManager.setOperator(address(0));
    }

    function test_setLiquidator() public {
        address liquidator = address(0x1234);
        positionManager.setLiquidator(liquidator, true);
        assertEq(positionManager.trustedLiquidator(liquidator), true);

        positionManager.setLiquidator(liquidator, false);
        assertEq(positionManager.trustedLiquidator(liquidator), false);

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setLiquidator(liquidator, true);

        vm.expectRevert(Errors.ZeroAddress.selector);
        positionManager.setLiquidator(address(0), true);
    }

    function test_setExecutor() public {
        address executor = address(0x1234);
        positionManager.setExecutor(executor, true);
        assertEq(positionManager.trustedExecutor(executor), true);

        positionManager.setExecutor(executor, false);
        assertEq(positionManager.trustedExecutor(executor), false);

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setExecutor(executor, true);

        vm.expectRevert(Errors.ZeroAddress.selector);
        positionManager.setLiquidator(address(0), true);
    }

    function test_setDiscount() public {
        positionManager.setDiscount(1e18);
        assertEq(positionManager.discount(), 1e18);

        positionManager.setDiscount(0);
        assertEq(positionManager.discount(), 0);

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setDiscount(1e18);

        vm.expectRevert(Errors.InvalidDiscount.selector);
        positionManager.setDiscount(1.1e18);
    }

    function test_setMarketOracles() public {
        ISpotOracle spotOracle = ISpotOracle(address(0));
        IForwardOracle forwardOracle = IForwardOracle(address(0));
        IVolatilityOracle volOracle = IVolatilityOracle(address(0));

        positionManager.setMarketOracles(1, spotOracle, forwardOracle, volOracle);

        assertEq(address(positionManager.spotOracles(1)), address(0));
        assertEq(address(positionManager.forwardOracles(1)), address(0));
        assertEq(address(positionManager.volOracles(1)), address(0));

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setMarketOracles(1, spotOracle, forwardOracle, volOracle);

        vm.expectRevert(Errors.NotExistMarket.selector);
        positionManager.setMarketOracles(3, spotOracle, forwardOracle, volOracle);
    }

    function test_setStableOracle() public {
        ISpotOracle stableOracle = ISpotOracle(address(0));

        positionManager.setStableOracle(stableOracle);

        assertEq(address(positionManager.stableOracle()), address(0));

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setStableOracle(stableOracle);
    }

    function test_setFeeRecipient() public {
        uint256 feeRecipient = positionManager.createSubAccount(address(1001));
        positionManager.setFeeRecipient(feeRecipient);

        assertEq(positionManager.feeRecipient(), feeRecipient);

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setFeeRecipient(feeRecipient);

        vm.expectRevert("ERC721: invalid token ID");
        positionManager.setFeeRecipient(1000);
    }

    function test_setFeeExemption() public {
        address exemptionCaller = address(100);

        positionManager.setFeeExemption(exemptionCaller, true);

        assertEq(positionManager.feeExemption(exemptionCaller), true);

        positionManager.setFeeExemption(exemptionCaller, false);

        assertEq(positionManager.feeExemption(exemptionCaller), false);

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setFeeExemption(exemptionCaller, true);
    }

    function test_setDataReceiver() public {
        address dataReceiver = address(100);

        positionManager.setDataReceiver(dataReceiver, true);

        assertEq(positionManager.dataReceiver(dataReceiver), true);

        positionManager.setDataReceiver(dataReceiver, false);

        assertEq(positionManager.dataReceiver(dataReceiver), false);

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setDataReceiver(dataReceiver, true);
    }

    function test_setMaintenanceMarginCaller() public {
        address trustedCaller = address(100);

        positionManager.setMaintenanceMarginCaller(trustedCaller, true);

        assertEq(positionManager.mmCallerAccounts(trustedCaller), true);

        positionManager.setMaintenanceMarginCaller(trustedCaller, false);

        assertEq(positionManager.mmCallerAccounts(trustedCaller), false);

        vm.prank(address(0xff));
        vm.expectRevert(Errors.OnlyOperator.selector);
        positionManager.setMaintenanceMarginCaller(trustedCaller, true);
    }

    // TO BE CONTINUE
}
