// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {SVI} from "../external/SVI.sol";
import {Errors} from "../libraries/Errors.sol";
import {FixedPointMathLib} from "../external/FixedPointMathLib.sol";

import {BaseOracle} from "./BaseOracle.sol";
import {IVolatilityOracle} from "./interfaces/IVolatilityOracle.sol";

contract VolatilityOracle is BaseOracle, IVolatilityOracle {
    mapping(uint256 expiry => VolDetails) private volDetails;

    constructor() BaseOracle("VolatilityOracle", "1") {}

    /// @notice Gets vol for a given strike and expiry
    /// @return vol Vol of the given strike and expiry to 18dp.
    function getVol(uint128 strike, uint64 expiry) public view returns (uint256 vol) {
        VolDetails memory volDetail = volDetails[expiry];

        // Revert if no data for given expiry
        if (volDetail.timestamp == 0) {
            revert Errors.InvalidExpiryData();
        }

        _checkHeartbeat(volDetail.timestamp);

        vol = SVI.getVol(
            strike,
            volDetail.SVI_a,
            volDetail.SVI_b,
            volDetail.SVI_rho,
            volDetail.SVI_m,
            volDetail.SVI_sigma,
            volDetail.SVI_fwd,
            volDetail.SVI_refTau
        );
    }

    /// @notice Parse input data and update spot price
    function receiveData(bytes calldata data) external override {
        OracleData memory oracleData = _verifyData(data);

        (
            uint64 expiry,
            int256 SVI_a,
            uint256 SVI_b,
            int256 SVI_rho,
            int256 SVI_m,
            uint256 SVI_sigma,
            uint256 SVI_fwd,
            uint64 SVI_refTau
        ) = abi.decode(oracleData.data, (uint64, int256, uint256, int256, int256, uint256, uint256, uint64));

        // ignore if timestamp is lower than current
        if (oracleData.timestamp <= volDetails[expiry].timestamp) return;

        if (oracleData.timestamp > expiry) revert Errors.InvalidVolDataTimestamp();

        // update spot price
        VolDetails memory newVolDetails = VolDetails({
            SVI_a: SVI_a,
            SVI_b: SVI_b,
            SVI_rho: SVI_rho,
            SVI_m: SVI_m,
            SVI_sigma: SVI_sigma,
            SVI_fwd: SVI_fwd,
            SVI_refTau: SVI_refTau,
            timestamp: oracleData.timestamp
        });
        volDetails[expiry] = newVolDetails;

        emit VolatilityUpdated(expiry, newVolDetails);
    }
}
