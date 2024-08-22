// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {Errors} from "../../../src/libraries/Errors.sol";

import "../../../src/oracle/SpotOracle.sol";
import "./OracleTestUtils.sol";

contract UNIT_BaseOracle is OracleTestUtils {
    SpotOracle oracle;

    bytes32 domainSeparator;

    uint256 private pk;
    address private pkOwner;
    uint256 private pk2;
    address private pkOwner2;

    function setUp() public {
        oracle = new SpotOracle();
        domainSeparator = oracle.domainSeparator();

        pk = 0x1234;
        pkOwner = vm.addr(pk);

        pk2 = 0x2345;
        pkOwner2 = vm.addr(pk2);

        vm.warp(block.timestamp + 365 days);
        oracle.setSigner(pkOwner, true);
        oracle.setSigner(pkOwner2, true);
    }

    function test_domainSeparator() public view {
        assertEq(oracle.domainSeparator(), domainSeparator);
    }

    function test_setSigner() public {
        address alice = address(0xaaaa);
        oracle.setSigner(alice, true);
        assertEq(oracle.isSigner(alice), true);
    }

    function test_setSignerRequired() public {
        oracle.setMinimumSigners(3);
        assertEq(oracle.minimumSigners(), 3);
    }

    function test_cannotSetSignerRequiredToZero() public {
        vm.expectRevert(Errors.InvalidMinimumSigners.selector);
        oracle.setMinimumSigners(0);
    }

    function test_setMultipleSigners() public {
        oracle.setMinimumSigners(2);

        IBaseOracle.OracleData memory spotData = _getDefaultSpotDataMultipleSigners(2);
        bytes32 structHash = hashOracleData(oracle, spotData);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
        spotData.signers[0] = pkOwner;

        (v, r, s) = vm.sign(pk2, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[1] = bytes.concat(r, s, bytes1(v));
        spotData.signers[1] = pkOwner2;

        bytes memory data = abi.encode(spotData);
        oracle.receiveData(data);

        uint256 spot = oracle.getSpot();
        assertEq(spot, 1000e18);
    }

    function test_cannotUpdateIfNoSigners() public {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotDataMultipleSigners(0);
        bytes memory data = abi.encode(spotData);

        vm.expectRevert(Errors.NotEnoughSigners.selector);
        oracle.receiveData(data);
    }

    function test_cannotUpdateIfNotEnoughSigners() public {
        oracle.setMinimumSigners(2);

        IBaseOracle.OracleData memory spotData = _getDefaultSpotDataMultipleSigners(1);
        bytes32 structHash = hashOracleData(oracle, spotData);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
        spotData.signers[0] = pkOwner;

        bytes memory data = abi.encode(spotData);

        vm.expectRevert(Errors.NotEnoughSigners.selector);
        oracle.receiveData(data);
    }

    function test_cannotUseSameSigner() public {
        oracle.setMinimumSigners(2);

        IBaseOracle.OracleData memory spotData = _getDefaultSpotDataMultipleSigners(2);
        bytes32 structHash = hashOracleData(oracle, spotData);

        // signatures[0]: signed by pk
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
        spotData.signers[0] = pkOwner;
        // signatures[1]: signed by pk
        (v, r, s) = vm.sign(pk, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[1] = bytes.concat(r, s, bytes1(v));
        spotData.signers[1] = pkOwner;

        bytes memory data = abi.encode(spotData);
        vm.expectRevert(Errors.DuplicatedSigner.selector);
        oracle.receiveData(data);
    }

    function test_cannotSubmitMismatchedData() public {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotDataMultipleSigners(3);
        spotData.signatures = new bytes[](0);
        spotData.signers[0] = pkOwner;
        bytes memory data = abi.encode(spotData);

        vm.expectRevert(Errors.SignatureSignersLengthMismatch.selector);
        oracle.receiveData(data);
    }

    function test_cannotUseSameSigner2() public {
        oracle.setMinimumSigners(3);

        IBaseOracle.OracleData memory spotData = _getDefaultSpotDataMultipleSigners(3);
        bytes32 structHash = hashOracleData(oracle, spotData);

        // signed by pk
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[0] = bytes.concat(r, s, bytes1(v));
        spotData.signers[0] = pkOwner;
        // signed by pk2 (valid)
        (v, r, s) = vm.sign(pk2, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[1] = bytes.concat(r, s, bytes1(v));
        spotData.signers[1] = pkOwner2;
        // signatures[2]: signed by pk again
        (v, r, s) = vm.sign(pk, ECDSA.toTypedDataHash(oracle.domainSeparator(), structHash));
        spotData.signatures[2] = bytes.concat(r, s, bytes1(v));
        spotData.signers[2] = pkOwner;

        bytes memory data = abi.encode(spotData);
        vm.expectRevert(Errors.DuplicatedSigner.selector);
        oracle.receiveData(data);
    }

    function test_hashOracleData() public view {
        IBaseOracle.OracleData memory spotData = _getDefaultSpotDataMultipleSigners(3);
        oracle.hashOracleData(spotData);
    }

    function _getDefaultSpotDataMultipleSigners(uint256 numSigners)
        internal
        view
        returns (IBaseOracle.OracleData memory)
    {
        uint96 price = 1000e18;
        bytes memory spotData = abi.encode(price);

        return IBaseOracle.OracleData({
            data: spotData,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](numSigners),
            signatures: new bytes[](numSigners)
        });
    }
}
