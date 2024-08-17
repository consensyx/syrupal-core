// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {ISpotOracle} from "./ISpotOracle.sol";

interface IForwardOracle {
    function getForwardPrice(uint64 expiry) external view returns (uint256 forwardPrice);

    function getSettlementPrice(uint64 expiry) external view returns (bool settled, uint256 price);

    struct ForwardInfo {
        int96 fwdSpotDifference;
        uint64 timestamp;
    }

    struct SettlementDetails {
        uint256 settlementStartAggregate;
        uint256 currentSpotAggregate;
    }

    event MaxExpirySet(uint64 maxExpiry);
    event SpotOracleSet(ISpotOracle spotOracle);
    event SettleHeartbeatUpdated(uint64 settlementHeartbeat);
    event ForwardInfoUpdated(uint64 indexed expiry, ForwardInfo fwdDetails, SettlementDetails settlementDetails);
}
