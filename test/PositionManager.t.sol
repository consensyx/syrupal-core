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

contract PositionManagerTest is BaseSetup {
    using SafeCast for uint256;
    using SafeCast for int256;
    using ConvertDecimals for uint256;

    function setUp() public override {
        super.setUp();
    }

    // TO BE CONTINUE
}
