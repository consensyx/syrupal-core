// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Errors} from "../../../src/libraries/Errors.sol";

import "../../../src/oracle/SpotOracle.sol";
import "./OracleTestUtils.sol";

contract UNIT_SpotOracle is OracleTestUtils {
    SpotOracle oracle;

    bytes32 domainSeparator;

    uint256 private pk;
    address private pkOwner;

    function setUp() public {
        oracle = new SpotOracle();
        domainSeparator = oracle.domainSeparator();

        pk = 0x1234;
        pkOwner = vm.addr(pk);

        vm.warp(block.timestamp + 365 days);
        oracle.setSigner(pkOwner, true);
    }

    function test_updateSpotOracle() public {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotData();
        bytes memory data = _signOracleData(oracle, pk, spotData);

        oracle.receiveData(data);

        uint256 spot = oracle.getSpot();

        assertEq(spot, 1000e18);
    }

    function test_updateSpotOracleRevertFromInvalidSigner() public {
        oracle.setSigner(pkOwner, false);

        IBaseOracle.OracleData memory spotData = _getDefaultSpotData();
        bytes memory data = _signOracleData(oracle, pk, spotData);

        vm.expectRevert(Errors.InvalidSigner.selector);
        oracle.receiveData(data);
    }

    function test_updateSpotOracleRevertAfterDeadline() public {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotData();
        bytes memory data = _signOracleData(oracle, pk, spotData);

        vm.warp(block.timestamp + 10);

        vm.expectRevert(Errors.ExpiredData.selector);
        oracle.receiveData(data);
    }

    function test_setSpotRevertInTheFuture() public {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotData();
        spotData.timestamp = uint64(block.timestamp + 1000);

        bytes memory data = _signOracleData(oracle, pk, spotData);

        vm.expectRevert(Errors.InvalidTimestamp.selector);
        oracle.receiveData(data);
    }

    function test_ignoreOlderData() public {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotData();
        bytes memory data1 = _signOracleData(oracle, pk, spotData);

        oracle.receiveData(data1);

        spotData.data = abi.encode(1100e18, 1.01e18);

        bytes memory data2 = _signOracleData(oracle, pk, spotData);
        oracle.receiveData(data2);

        uint256 spot = oracle.getSpot();
        assertEq(spot, 1000e18);
    }

    function test_submitPriceRevertWithFakeSigner() public {
        uint256 pk2 = 0x2345;

        IBaseOracle.OracleData memory spotData = _getDefaultSpotData();
        spotData.signers[0] = pkOwner;
        bytes memory data = _signOracleData(oracle, pk2, spotData);

        vm.expectRevert(Errors.InvalidSignature.selector);
        oracle.receiveData(data);
    }

    function test_cannotReadExipiredData() public {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotData();
        bytes memory data = _signOracleData(oracle, pk, spotData);
        oracle.receiveData(data);

        vm.warp(block.timestamp + oracle.heartbeat() + 1);

        vm.expectRevert(Errors.ExpiredData.selector);
        oracle.getSpot();
    }

    function _getDefaultSpotData() internal view returns (IBaseOracle.OracleData memory) {
        uint96 price = 1000e18;
        bytes memory spotData = abi.encode(price);

        return IBaseOracle.OracleData({
            data: spotData,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }
}
