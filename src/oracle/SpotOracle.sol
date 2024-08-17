// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Errors} from "../libraries/Errors.sol";

import {BaseOracle} from "./BaseOracle.sol";
import {ISpotOracle} from "./interfaces/ISpotOracle.sol";

contract SpotOracle is BaseOracle, ISpotOracle {
    SpotDetail private spotDetail;

    constructor() BaseOracle("SpotOracle", "1") {}

    function getSpot() public view returns (uint256) {
        _checkHeartbeat(spotDetail.timestamp);

        return spotDetail.price;
    }

    function receiveData(bytes calldata data) external override {
        OracleData memory oracleData = _verifyData(data);

        if (oracleData.timestamp <= spotDetail.timestamp) return;

        uint96 price = abi.decode(oracleData.data, (uint96));

        // update spot price
        spotDetail = SpotDetail(price, uint64(oracleData.timestamp));

        emit SpotInfoUpdated(price, uint64(oracleData.timestamp));
    }
}
