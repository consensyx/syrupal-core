// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Errors} from "../../../src/libraries/Errors.sol";

import "./OracleTestUtils.sol";
import "../../../src/external/Black76.sol";
import "../../../src/oracle/VolatilityOracle.sol";

contract UNIT_VolatilityOracle is OracleTestUtils {
    VolatilityOracle oracle;

    bytes32 domainSeparator;

    uint256 private pk;
    address private pkOwner;
    uint256 referenceTime;
    uint64 defaultExpiry;

    function setUp() public {
        oracle = new VolatilityOracle();

        domainSeparator = oracle.domainSeparator();

        pk = 0x1234;
        pkOwner = vm.addr(pk);

        vm.warp(block.timestamp + 365 days);
        referenceTime = block.timestamp;
        defaultExpiry = uint64(referenceTime + 365 days);

        oracle.setSigner(pkOwner, true);
    }

    function test_fetchingInvalidExpiryRevert() public {
        vm.expectRevert(Errors.InvalidExpiryData.selector);
        oracle.getVol(uint128(uint256(1500e18)), defaultExpiry);
    }

    function test_cannotUpdateLaterTimestampThanExpiry() public {
        IBaseOracle.OracleData memory volData = _getDefaultVolData();

        vm.warp(defaultExpiry + 1);

        volData.timestamp = uint64(defaultExpiry + 1);
        volData.deadline = uint64(defaultExpiry + 1);
        bytes memory data = _signOracleData(oracle, pk, volData);

        vm.expectRevert(Errors.InvalidVolDataTimestamp.selector);
        oracle.receiveData(data);
    }

    function test_updateVolOracle() public {
        IBaseOracle.OracleData memory volData = _getDefaultVolData();
        bytes memory data = _signOracleData(oracle, pk, volData);

        oracle.receiveData(data);

        uint256 vol = oracle.getVol(uint128(uint256(1500e18)), defaultExpiry);
        assertApproxEqAbs(vol, 1.1728e18, 0.0001e18);
    }

    function test_updateVolOracleRevertFromInvalidSigner() public {
        oracle.setSigner(pkOwner, false);

        IBaseOracle.OracleData memory volData = _getDefaultVolData();
        bytes memory data = _signOracleData(oracle, pk, volData);

        vm.expectRevert(Errors.InvalidSigner.selector);
        oracle.receiveData(data);
    }

    function test_updateVolOracleRevertAfterDeadline() public {
        IBaseOracle.OracleData memory volData = _getDefaultVolData();
        bytes memory data = _signOracleData(oracle, pk, volData);

        vm.warp(block.timestamp + 10);

        vm.expectRevert(Errors.ExpiredData.selector);
        oracle.receiveData(data);
    }

    function test_updateVolRevertInTheFuture() public {
        IBaseOracle.OracleData memory volData = _getDefaultVolData();
        volData.timestamp = uint64(block.timestamp + 1000);
        bytes memory data = _signOracleData(oracle, pk, volData);

        vm.expectRevert(Errors.InvalidTimestamp.selector);
        oracle.receiveData(data);
    }

    function test_submitPriceRevertWithInvalidSigner() public {
        uint256 pk2 = 0x2345;

        IBaseOracle.OracleData memory volData = _getDefaultVolData();
        volData.signers[0] = pkOwner;
        bytes memory data = _signOracleData(oracle, pk2, volData);

        vm.expectRevert(Errors.InvalidSignature.selector);
        oracle.receiveData(data);
    }

    function _getDefaultVolData() internal view returns (IBaseOracle.OracleData memory) {
        int256 SVI_a = 1e18;
        uint256 SVI_b = 1.5e18;
        int256 SVI_rho = -0.1e18;
        int256 SVI_m = -0.05e18;
        uint256 SVI_sigma = 0.05e18;
        uint256 SVI_fwd = 1200e18;
        uint64 SVI_refTau = uint64(Black76.annualise(uint64(defaultExpiry - block.timestamp)));

        bytes memory volData = abi.encode(defaultExpiry, SVI_a, SVI_b, SVI_rho, SVI_m, SVI_sigma, SVI_fwd, SVI_refTau);
        return IBaseOracle.OracleData({
            data: volData,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }
}
