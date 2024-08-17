// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

/**
 * @notice Util functions for encoding / decoding IDs into option details.
 *         [ 1 bit ] [ 63 bits ] [ 32 bit ] = uint96 subId
 *           isCall     strike     expiry
 *         Can support:
 *         - expiries: up to year 2106
 *         - strikes: down to 8 decimal points and up to $90B
 */
library Encoding {
    uint256 constant UINT63_MAX = 0x7fffffffffffffff; // 9223372036854775807;

    /**
     * @dev Convert option details into subId
     * @param expiry timestamp of expiry
     * @param strike 18 decimal strike price
     * @param isCall if call, then true
     * @return subId ID of option
     */
    function toSubId(uint256 marketId, uint256 expiry, uint256 strike, bool isCall)
        internal
        pure
        returns (uint112 subId)
    {
        if (marketId > type(uint16).max) {
            revert MarketIdTooLarge(marketId);
        }

        // can support expiry up to year 2106
        if (expiry > type(uint32).max) {
            revert ExpiryTooLarge(expiry);
        }

        // zero expiry guaranteed to not be possible
        if (expiry == 0) {
            revert ZeroExpiry();
        }

        // can support strike granularity down to 8 decimal points
        if (strike % 1e10 > 0) {
            revert StrikeTooGranular(strike);
        }

        // convert to 8 decimal points
        strike = strike / 1e10;

        // can support strike as high as $92,233,720,368
        if (strike > UINT63_MAX) {
            revert StrikeTooLarge(strike);
        }

        uint112 shiftedStrike = uint112(strike) << 32;
        uint112 shiftedIsCall = uint112((isCall) ? 1 : 0) << 95;
        uint112 shiftedMarketId = uint112(marketId) << 96;
        subId = uint112(expiry) | shiftedStrike | shiftedIsCall | shiftedMarketId;
    }

    /**
     * @dev Convert subId into option details
     * @param subId ID of option
     * @return marketId
     * @return expiry timestamp of expiry
     * @return strike 18 decimal strike price
     * @return isCall if call, then true
     */
    function fromSubId(uint112 subId)
        internal
        pure
        returns (uint256 marketId, uint256 expiry, uint256 strike, bool isCall)
    {
        expiry = subId & type(uint32).max;
        strike = ((subId >> 32) & UINT63_MAX) * 1e10;
        isCall = (subId >> 95) & 1 > 0;
        marketId = (subId >> 96) & type(uint16).max;
    }

    error ZeroExpiry();
    error MarketIdTooLarge(uint256 marketId);
    error ExpiryTooLarge(uint256 expiry);
    error StrikeTooLarge(uint256 strike);
    error StrikeTooGranular(uint256 strike);
}
