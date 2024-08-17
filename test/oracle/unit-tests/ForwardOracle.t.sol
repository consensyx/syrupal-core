// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Errors} from "../../../src/libraries/Errors.sol";

import "./OracleTestUtils.sol";
import "../../../src/oracle/VolatilityOracle.sol";
import "../../../src/oracle/ForwardOracle.sol";
import "../../mocks/MockOracles.sol";

contract UNIT_ForwardOracle is OracleTestUtils {
    MockOracles mockSpot;
    ForwardOracle oracle;

    bytes32 domainSeparator;

    uint256 private pk;
    address private pkOwner;
    uint256 referenceTime;
    uint64 defaultExpiry;

    int96 fwdSpotDifference = 10e18;
    uint256 settlementStartAggregate;
    uint256 currentSpotAggregate;

    function setUp() public {
        mockSpot = new MockOracles();
        mockSpot.setSpot(990e18);

        oracle = new ForwardOracle(ISpotOracle(address(mockSpot)));

        domainSeparator = oracle.domainSeparator();

        pk = 0x1234;
        pkOwner = vm.addr(pk);

        vm.warp(block.timestamp + 365 days);
        referenceTime = block.timestamp;
        defaultExpiry = uint64(referenceTime + 365 days);

        oracle.setSigner(pkOwner, true);

        settlementStartAggregate = 1050e18 * uint256(defaultExpiry - oracle.SETTLEMENT_TWAP_DURATION());
        currentSpotAggregate = 1050e18 * uint256(defaultExpiry);
    }

    function test_setSettleHeartBeat() public {
        oracle.setSettleHeartbeat(30 minutes);
        assertEq(oracle.settlementHeartbeat(), 30 minutes);
    }

    function test_setSpotOracle() public {
        MockOracles newSpotOracle = new MockOracles();
        newSpotOracle.setSpot(1500e18);

        oracle.setSpotOracle(newSpotOracle);
        assertEq(address(oracle.spotOracle()), address(newSpotOracle));
    }

    function test_revertsWhenInvalidExpiry() public {
        vm.expectRevert(Errors.InvalidExpiryData.selector);
        oracle.getForwardPrice(defaultExpiry);
    }

    function test_updateFwdOracle() public {
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        bytes memory data = _signOracleData(oracle, pk, oracleData);

        oracle.receiveData(data);

        uint256 fwdPrice = oracle.getForwardPrice(defaultExpiry);
        assertEq(fwdPrice, 1000e18);
    }

    function test_cannotGetInvalidForwardDiff() public {
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();

        int256 newDiff = -1000e18;
        oracleData.data = abi.encode(defaultExpiry, settlementStartAggregate, currentSpotAggregate, newDiff);
        oracle.receiveData(_signOracleData(oracle, pk, oracleData));

        vm.expectRevert("SafeCast: value must be positive");
        oracle.getForwardPrice(defaultExpiry);

        vm.warp(block.timestamp + 1);

        newDiff = -990e18;
        oracleData.data = abi.encode(defaultExpiry, settlementStartAggregate, currentSpotAggregate, newDiff);

        oracleData.timestamp += 1;
        oracle.receiveData(_signOracleData(oracle, pk, oracleData));
        uint256 fwdPrice = oracle.getForwardPrice(defaultExpiry);
        assertEq(fwdPrice, 0);
    }

    function test_updateFwdOracleRevertIfInvalidSigner() public {
        oracle.setSigner(pkOwner, false);

        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        bytes memory data = _signOracleData(oracle, pk, oracleData);

        vm.expectRevert(Errors.InvalidSigner.selector);
        oracle.receiveData(data);
    }

    function test_updateFwdOracleRevertAfterDeadline() public {
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        bytes memory data = _signOracleData(oracle, pk, oracleData);

        vm.warp(block.timestamp + 10);

        vm.expectRevert(Errors.ExpiredData.selector);
        oracle.receiveData(data);
    }

    function test_cannotSetFwdInTheFuture() public {
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        oracleData.timestamp = uint64(block.timestamp + 1000);
        bytes memory data = _signOracleData(oracle, pk, oracleData);

        vm.expectRevert(Errors.InvalidTimestamp.selector);
        oracle.receiveData(data);
    }

    function test_cannotSetFwdPastExpiry() public {
        vm.warp(defaultExpiry + 1);
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        oracleData.timestamp = uint64(defaultExpiry + 1);
        bytes memory data = _signOracleData(oracle, pk, oracleData);

        vm.expectRevert(Errors.InvalidFwdDataTimestamp.selector);
        oracle.receiveData(data);
    }

    function test_setSettlementData() public {
        vm.warp(defaultExpiry);
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        oracleData.timestamp = uint64(defaultExpiry);
        bytes memory data = _signOracleData(oracle, pk, oracleData);
        oracle.receiveData(data);

        (bool settled, uint256 settlementPrice) = oracle.getSettlementPrice(defaultExpiry);
        assertEq(settlementPrice, 1050e18);
        assertTrue(settled);
    }

    function test_splitForwardOracle() public {
        oracle.setHeartbeat(1 days);

        vm.warp(defaultExpiry - 10 minutes);
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        uint256 newCurAggregate = 1050e18 * uint256(defaultExpiry - 10 minutes);

        oracleData.data = abi.encode(defaultExpiry, settlementStartAggregate, newCurAggregate, fwdSpotDifference);
        oracleData.timestamp = uint64(block.timestamp);

        oracleData.data = abi.encode(defaultExpiry, settlementStartAggregate, newCurAggregate, fwdSpotDifference);

        bytes memory data = _signOracleData(oracle, pk, oracleData);
        oracle.receiveData(data);

        (uint256 forwardFixedPortion, uint256 forwardVariablePortion) = oracle.getTWAPPrice(defaultExpiry);
        assertEq(forwardFixedPortion, uint256(1050e18) * 2 / 3);
        assertEq(forwardVariablePortion, uint256(1000e18) / 3);

        vm.warp(defaultExpiry - 4 minutes);
        vm.expectRevert(Errors.SettlementDataTooOld.selector);
        oracle.getTWAPPrice(defaultExpiry);

        vm.warp(defaultExpiry);
        (bool settled,) = oracle.getSettlementPrice(defaultExpiry);
        assertEq(settled, false);
    }

    function test_cannotSubmitPriceWithFakeSigner() public {
        uint256 pk2 = 0x2345;

        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        oracleData.signers[0] = pkOwner;
        bytes memory data = _signOracleData(oracle, pk2, oracleData);

        vm.expectRevert(Errors.InvalidSignature.selector);
        oracle.receiveData(data);
    }

    function test_getSettlementPriceAfterExpiry() public {
        oracle.setHeartbeat(10 minutes);
        vm.warp(defaultExpiry);
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();
        oracleData.timestamp = uint64(defaultExpiry);
        bytes memory data = _signOracleData(oracle, pk, oracleData);
        oracle.receiveData(data);

        vm.warp(block.timestamp + 50 minutes);
        (uint256 forwardFixedPortion, uint256 forwardVariablePortion) = oracle.getTWAPPrice(defaultExpiry);

        assertEq(forwardFixedPortion, 1050e18);
        assertEq(forwardVariablePortion, 0);
    }

    function test_setSettleHeartbeat() public {
        oracle.setSettleHeartbeat(1 days);
        assertEq(oracle.settlementHeartbeat(), 1 days);
    }

    function test_cannotSetInvalidSettlementData() public {
        vm.warp(defaultExpiry - 10 minutes);
        IBaseOracle.OracleData memory oracleData = _getDefaultForwardData();

        uint256 newCurAggregate = 0;
        oracleData.data = abi.encode(defaultExpiry, settlementStartAggregate, newCurAggregate, fwdSpotDifference);
        bytes memory data = _signOracleData(oracle, pk, oracleData);

        vm.expectRevert(Errors.InvalidSettlementData.selector);
        oracle.receiveData(data);
    }

    function test_encodeFwdOracleData() public view {
        uint64 expiry_ = 1698998400;
        uint256 settlementStartAggregate_ = 1;
        uint256 currentSpotAggregate_ = 3211595747743195673395200;
        int96 fwdSpotDifference_ = 380023830429887040;
        uint64 conf_ = 1000000000000000000;

        bytes memory oracleData =
            abi.encode(expiry_, settlementStartAggregate_, currentSpotAggregate_, fwdSpotDifference_, conf_);

        address[] memory signers_ = new address[](1);
        signers_[0] = 0xC27e00dE4eFAfFA60B6B008C4520517ed00294cb;
        bytes[] memory signatures_ = new bytes[](1);
        signatures_[0] =
            hex"e09e6294d07561fcb7609e25a6d80a1ffcb13d65b5a996d9c0612eabac75a9af1559514de11ec0165e0af9658db1dce192ae74339e8207c82afcd49f6c567f531c";

        uint64 timestamp_ = 1723709654;
        uint64 deadline_ = 1723710654;

        bytes memory dataToSubmit = abi.encode(oracleData, timestamp_, deadline_, signers_, signatures_);

        console2.logBytes(dataToSubmit);
    }

    function _getDefaultForwardData() internal view returns (IBaseOracle.OracleData memory) {
        return IBaseOracle.OracleData({
            data: abi.encode(defaultExpiry, settlementStartAggregate, currentSpotAggregate, fwdSpotDifference),
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }
}
