// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {Math} from "openzeppelin/utils/math/Math.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

import {Errors} from "../libraries/Errors.sol";

import {BaseOracle} from "./BaseOracle.sol";
import {ISpotOracle} from "./interfaces/ISpotOracle.sol";
import {IForwardOracle} from "./interfaces/IForwardOracle.sol";

contract ForwardOracle is BaseOracle, IForwardOracle {
    uint64 public constant SETTLEMENT_TWAP_DURATION = 30 minutes;

    uint64 public maxExpiry = 365 days;

    ISpotOracle public spotOracle;

    /// @dev secondary heartbeat for when the forward price is close to expiry
    uint64 public settlementHeartbeat = 5 minutes;

    /// @dev forward price data
    mapping(uint64 expiry => ForwardInfo) private forwardInfo;

    /// @dev settlement price data, as time approach expiry the spot data stored here start contributing to forward price
    mapping(uint64 expiry => SettlementDetails) private settlementDetails;

    constructor(ISpotOracle _spotOracle) BaseOracle("ForwardOracle", "1") {
        spotOracle = _spotOracle;
    }

    /// @dev in the last SETTLEMENT_TWAP_DURATION before expiry, we require constant update on settlement data
    /// the call to get forward price will revert if last updated time is longer than settlementHeartbeat seconds ago
    function setSettleHeartbeat(uint64 _settlementHeartbeat) external onlyOwner {
        settlementHeartbeat = _settlementHeartbeat;
        emit SettleHeartbeatUpdated(_settlementHeartbeat);
    }

    function setMaxExpiry(uint64 _maxExpiry) external onlyOwner {
        maxExpiry = _maxExpiry;
        emit MaxExpirySet(_maxExpiry);
    }

    /// @dev update the spot oracle address
    function setSpotOracle(ISpotOracle _spotOracle) external onlyOwner {
        spotOracle = _spotOracle;
        emit SpotOracleSet(_spotOracle);
    }

    /// @notice Gets forward price for a given expiry
    /// @dev as time approach expiry, the forward price will be a twap of the forward price & settlement price (twap of spot)
    function getForwardPrice(uint64 expiry) external view returns (uint256) {
        (uint256 forwardFixedPortion, uint256 forwardVariablePortion) = getTWAPPrice(expiry);

        return forwardFixedPortion + forwardVariablePortion;
    }

    /// @notice Gets settlement price for a given expiry
    /// @dev Will revert if the provided data timestamp does not match the expiry
    function getSettlementPrice(uint64 expiry) external view returns (bool settled, uint256 price) {
        // The data must have the exact same timestamp as the expiry to be considered valid for settlement
        if (forwardInfo[expiry].timestamp != expiry) {
            return (false, 0);
        }

        SettlementDetails memory settlementData = settlementDetails[expiry];

        return (
            true,
            (settlementData.currentSpotAggregate - settlementData.settlementStartAggregate) / SETTLEMENT_TWAP_DURATION
        );
    }

    /// @notice Gets forward price according to TWAP rules
    /// @return forwardFixedPortion The portion of the settlement price that is guaranteed to be included.
    /// Options have no further delta exposure to this portion.
    /// @return forwardVariablePortion The part of the price that can still change until expiry
    function getTWAPPrice(uint64 expiry)
        public
        view
        returns (uint256 forwardFixedPortion, uint256 forwardVariablePortion)
    {
        uint256 spotPrice = spotOracle.getSpot();

        ForwardInfo memory info = forwardInfo[expiry];
        _verifyDetailTimestamp(expiry, info.timestamp, expiry - SETTLEMENT_TWAP_DURATION);

        (forwardFixedPortion, forwardVariablePortion) =
            _getTWAPPrice(spotPrice, info, settlementDetails[expiry], expiry);

        return (forwardFixedPortion, forwardVariablePortion);
    }

    function receiveData(bytes calldata data) external override {
        OracleData memory oracleData = _verifyData(data);

        (uint64 expiry, uint256 settlementStartAggregate, uint256 currentSpotAggregate, int96 fwdSpotDifference) =
            abi.decode(oracleData.data, (uint64, uint256, uint256, int96));

        // ignore if timestamp is lower or equal to current
        if (oracleData.timestamp <= forwardInfo[expiry].timestamp) return;

        if (oracleData.timestamp > expiry) {
            revert Errors.InvalidFwdDataTimestamp();
        }

        if (expiry > block.timestamp + maxExpiry) {
            revert Errors.ExpiryTooFarInFuture();
        }

        SettlementDetails memory settlementData;
        if (oracleData.timestamp >= expiry - SETTLEMENT_TWAP_DURATION) {
            // Settlement data, must include spot aggregate values
            _verifySettlementData(settlementStartAggregate, currentSpotAggregate);

            settlementData = SettlementDetails(settlementStartAggregate, currentSpotAggregate);

            settlementDetails[expiry] = settlementData;
        }

        // always update forward
        ForwardInfo memory forwardDetail =
            ForwardInfo({fwdSpotDifference: fwdSpotDifference, timestamp: oracleData.timestamp});
        forwardInfo[expiry] = forwardDetail;

        emit ForwardInfoUpdated(expiry, forwardDetail, settlementData);
    }

    /// @return fixedPortion The portion of the settlement price that is guaranteed to be included.
    /// Options have no further delta exposure to this portion.
    /// @return variablePortion The part of the price that can still change until expiry (current forward price applied to
    /// the remaining time until expiry)
    function _getTWAPPrice(
        uint256 spotPrice,
        ForwardInfo memory info,
        SettlementDetails memory settlementData,
        uint64 expiry
    ) internal pure returns (uint256 fixedPortion, uint256 variablePortion) {
        variablePortion = SafeCast.toUint256(SafeCast.toInt256(spotPrice) + int256(info.fwdSpotDifference));

        if (expiry - info.timestamp >= SETTLEMENT_TWAP_DURATION) {
            return (0, variablePortion);
        }

        uint256 aggregateDiff = settlementData.currentSpotAggregate - settlementData.settlementStartAggregate;
        fixedPortion = aggregateDiff / SETTLEMENT_TWAP_DURATION;

        variablePortion = variablePortion * (expiry - info.timestamp) / SETTLEMENT_TWAP_DURATION;

        return (fixedPortion, variablePortion);
    }

    /// @dev Checks the cached data timestamp against the heartbeat, and settlement heartbeat if applicable
    function _verifyDetailTimestamp(uint64 expiry, uint64 fwdDetailsTimestamp, uint64 settlementOracleStart)
        internal
        view
    {
        if (fwdDetailsTimestamp == 0) {
            revert Errors.InvalidExpiryData();
        }

        // If price is settled, return early cause we will only rely on settlement data
        if (fwdDetailsTimestamp == expiry) {
            return;
        }

        // If price is not settled, check that the last updated forward data is not stale
        _checkHeartbeat(fwdDetailsTimestamp);

        // user should attach the latest settlement data to the forward data
        // Note: this will allow old data be used up to settlementHeartbeat AFTER the settlement period starts
        if (
            block.timestamp > settlementOracleStart
                && Math.max(fwdDetailsTimestamp, settlementOracleStart) + settlementHeartbeat < block.timestamp
        ) {
            revert Errors.SettlementDataTooOld();
        }
    }

    function _verifySettlementData(uint256 settlementStartAggregate, uint256 currentSpotAggregate) internal pure {
        if (settlementStartAggregate >= currentSpotAggregate) {
            revert Errors.InvalidSettlementData();
        }
    }
}
