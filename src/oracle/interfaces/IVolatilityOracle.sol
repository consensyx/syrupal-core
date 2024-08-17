// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IVolatilityOracle {
    function getVol(uint128 strike, uint64 expiry) external view returns (uint256 vol);

    struct VolDetails {
        int256 SVI_a;
        uint256 SVI_b;
        int256 SVI_rho;
        int256 SVI_m;
        uint256 SVI_sigma;
        uint256 SVI_fwd;
        uint64 SVI_refTau;
        uint64 timestamp;
    }

    event VolatilityUpdated(uint64 indexed expiry, VolDetails volDetails);
}
