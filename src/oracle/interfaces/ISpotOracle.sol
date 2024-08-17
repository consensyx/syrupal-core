// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface ISpotOracle {
    function getSpot() external view returns (uint256 spotPrice);

    struct SpotDetail {
        uint96 price;
        uint64 timestamp;
    }

    event SpotInfoUpdated(uint96 spot, uint64 timestamp);
}
