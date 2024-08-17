// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../src/oracle/SpotOracle.sol";
import "../../src/oracle/BatchSubmitter.sol";

import "../utils/IntegrationSetup.sol";

contract BatchSubmitterTest is IntegrationSetup {
    BatchSubmitter internal submitter;

    uint256 DEFAULT_EXPIRY = 1756656000;

    function setUp() public {
        vm.warp(DEFAULT_EXPIRY - 10 minutes);
        _setupIntegration();

        submitter = new BatchSubmitter();
    }

    function test_GasEstimate() public {
        IPositionManager.PreProcessData[] memory preDatas = new IPositionManager.PreProcessData[](7);

        // stablecoin price
        preDatas[0].receiver = address(stableOracle);

        IBaseOracle.OracleData memory stableOracleData = IBaseOracle.OracleData({
            data: abi.encode(1e18),
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 20,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        preDatas[0].data = _signOracleData(stableOracle, signerPK, stableOracleData);

        // ======== ETH market ======== //

        // set spot price
        preDatas[1].receiver = address(markets["weth"].spotOracle);

        uint96 spotPrice = 2920e18;
        IBaseOracle.OracleData memory spotData = _getSpotData(spotPrice);
        preDatas[1].data = _signOracleData(markets["weth"].spotOracle, signerPK, spotData);

        // set forward price
        preDatas[2].receiver = address(markets["weth"].forwardOracle);

        uint256 forwarPrice = 2920e18;

        uint256 startAggregate =
            forwarPrice * uint256(DEFAULT_EXPIRY - markets["weth"].forwardOracle.SETTLEMENT_TWAP_DURATION());
        uint256 currAggregate = forwarPrice * uint256(DEFAULT_EXPIRY);

        int256 spotDifference = 10e18;

        IBaseOracle.OracleData memory forWardData =
            _getDefaultForwardData(DEFAULT_EXPIRY, startAggregate, currAggregate, spotDifference);

        preDatas[2].data = _signOracleData(markets["weth"].forwardOracle, signerPK, forWardData);

        // set volatility price
        preDatas[3].receiver = address(markets["weth"].volOracle);
        preDatas[3].data = _signOracleData(markets["weth"].volOracle, signerPK, _getDefaultVolData(DEFAULT_EXPIRY));

        // ======== BTC market ======== //
        // set spot price
        preDatas[4].receiver = address(markets["wbtc"].spotOracle);

        spotPrice = 56200e18;
        spotData = _getSpotData(spotPrice);
        preDatas[4].data = _signOracleData(markets["wbtc"].spotOracle, signerPK, spotData);

        // set forward price
        preDatas[5].receiver = address(markets["wbtc"].forwardOracle);

        forwarPrice = 56200e18;

        startAggregate =
            forwarPrice * uint256(DEFAULT_EXPIRY - markets["wbtc"].forwardOracle.SETTLEMENT_TWAP_DURATION());
        currAggregate = forwarPrice * uint256(DEFAULT_EXPIRY);

        spotDifference = 10e18;

        forWardData = _getDefaultForwardData(DEFAULT_EXPIRY, startAggregate, currAggregate, spotDifference);

        preDatas[5].data = _signOracleData(markets["wbtc"].forwardOracle, signerPK, forWardData);

        // set volatility price
        preDatas[6].receiver = address(markets["wbtc"].volOracle);
        preDatas[6].data = _signOracleData(markets["wbtc"].volOracle, signerPK, _getDefaultVolData(DEFAULT_EXPIRY));

        submitter.sendData(abi.encode(preDatas));
    }

    function _getSpotData(uint96 price) internal view returns (IBaseOracle.OracleData memory) {
        bytes memory spotData = abi.encode(price);

        return IBaseOracle.OracleData({
            data: spotData,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 20,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }

    function _getDefaultVolData(uint256 expiry) internal view returns (IBaseOracle.OracleData memory) {
        // example data: a = 1, b = 1.5, sig = 0.05, rho = -0.1, m = -0.05

        int256 SVI_a = 1e18;
        uint256 SVI_b = 1.5e18;
        int256 SVI_rho = -0.1e18;
        int256 SVI_m = -0.05e18;
        uint256 SVI_sigma = 0.05e18;
        uint256 SVI_fwd = 1200e18;
        uint64 SVI_refTau = uint64(Black76.annualise(uint64(expiry - block.timestamp)));

        bytes memory volData = abi.encode(expiry, SVI_a, SVI_b, SVI_rho, SVI_m, SVI_sigma, SVI_fwd, SVI_refTau);
        return IBaseOracle.OracleData({
            data: volData,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 20,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }

    function _getDefaultForwardData(
        uint256 expiry,
        uint256 settlementStartAggregate,
        uint256 currentSpotAggregate,
        int256 spotDifference
    ) internal view returns (IBaseOracle.OracleData memory) {
        return IBaseOracle.OracleData({
            data: abi.encode(expiry, settlementStartAggregate, currentSpotAggregate, spotDifference),
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 20,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }
}
