// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ISpotOracle} from "../../src/oracle/interfaces/ISpotOracle.sol";
import {IVolatilityOracle} from "../../src/oracle/interfaces/IVolatilityOracle.sol";
import {IForwardOracle} from "../../src/oracle/interfaces/IForwardOracle.sol";
import {IReceiver} from "../../src/interfaces/IReceiver.sol";

contract MockOracles is ISpotOracle, IVolatilityOracle, IForwardOracle {
    uint256 public spot;
    mapping(uint256 => uint256) forwardPrices;
    mapping(uint256 => uint256) fwdFixedPortion;
    mapping(uint256 => int256) interestRates;
    mapping(uint256 => uint256) settlementPrice;
    mapping(uint64 => mapping(uint128 => uint256)) vols;

    function setSpot(uint256 _spot) external {
        spot = _spot;
    }

    function setSettlementPrice(uint256 expiry, uint256 price) external {
        settlementPrice[expiry] = price;
    }

    function setVol(uint64 expiry, uint128 strike, uint256 vol) external {
        vols[expiry][strike] = vol;
    }

    function setForwardPrice(uint256 expiry, uint256 price) external {
        forwardPrices[expiry] = price;
        fwdFixedPortion[expiry] = 0;
    }

    function setForwardPricePortions(uint256 expiry, uint256 fixedPortion, uint256 price) external {
        forwardPrices[expiry] = price;
        fwdFixedPortion[expiry] = fixedPortion;
    }

    // function receiveData(bytes calldata callData) external override {
    function receiveData(bytes calldata callData) external {
        spot = abi.decode(callData, (uint256));
    }

    // ISpotOracle

    function getSpot() external view returns (uint256) {
        return spot;
    }

    // IForwardOracle

    function getForwardPrice(uint64 expiry) external view returns (uint256 forwardPrice) {
        return (forwardPrices[expiry] + fwdFixedPortion[expiry]);
    }

    function getTWAPPrice(uint64 expiry)
        external
        view
        returns (uint256 forwardFixedPortion, uint256 forwardVariablePortion)
    {
        return (fwdFixedPortion[expiry], forwardPrices[expiry]);
    }

    // ISettlementPrice

    function getSettlementPrice(uint64 expiry) external view returns (bool, uint256) {
        return (settlementPrice[expiry] != 0, settlementPrice[expiry]);
    }

    // IVolatilityOracle

    function getVol(uint128 strike, uint64 expiry) external view returns (uint256 vol) {
        return vols[expiry][strike];
    }
}
