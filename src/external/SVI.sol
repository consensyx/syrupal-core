//SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.24;

// Libraries
import {SignedDecimalMath} from "./decimals/SignedDecimalMath.sol";
import {DecimalMath} from "./decimals/DecimalMath.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";

library SVI {
    using DecimalMath for uint256;
    using SignedDecimalMath for int256;
    using FixedPointMathLib for uint256;
    using FixedPointMathLib for int256;
    using SafeCast for int256;
    using SafeCast for uint256;

    error SVI_InvalidParameters();
    error SVI_NoForwardPrice();

    /// @dev Upper bound of of w in SVI
    int256 internal constant MAX_TOTAL_VAR = 144e18;

    /// @dev scaler used to calculate the upper bound and lower bound of k in SVI
    int256 internal constant TOTAL_VOL_SCALAR = 4e18;

    /**
     * @dev compute the vol for a given strike and set of SVI parameters
     * @param strike desired strike for which to get vol for, in range [0, inf)
     * @param a SVI parameter in range (-inf, inf)
     * @param b SVI parameter in range [0, inf)
     * @param rho SVI parameter in range (-1, 1)
     * @param m SVI parameter in range (-inf, inf)
     * @param sigma SVI parameter in range (0, inf)
     * @param forwardPrice forward price in range [0, inf)
     * @param tau time to expiry (in years) in range [0, inf)
     * @return vol
     */
    function getVol(
        uint256 strike,
        int256 a,
        uint256 b,
        int256 rho,
        int256 m,
        uint256 sigma,
        uint256 forwardPrice,
        uint64 tau
    ) internal pure returns (uint256) {
        if (strike == 0) return 0;
        if (forwardPrice == 0) revert SVI_NoForwardPrice();

        // k = ln(strike / fwd) but with some bounds
        int256 k = getK(strike, a, b, sigma, forwardPrice);
        int256 k_sub_m = int256(k) - m;

        // any number squared is positive, so we can cast to uint
        uint256 k_sub_m_sq = uint256(k_sub_m.multiplyDecimal(k_sub_m)); // (k - m)^2
        uint256 sigma_sq = sigma.multiplyDecimal(sigma); // sigma^2

        // b * (sqrt((k - m)^2 + sigma^2) + rho * (k - m))
        int256 bPortion = int256(b).multiplyDecimal(
            int256(FixedPointMathLib.sqrt(k_sub_m_sq + sigma_sq)) + rho.multiplyDecimal(k_sub_m)
        );

        // a + b * (sqrt((k - m)^2 + sigma^2) + rho * (k - m))
        int256 w = a + bPortion;

        if (w < 0) {
            revert SVI_InvalidParameters();
        } else if (w > MAX_TOTAL_VAR) {
            w = MAX_TOTAL_VAR;
        }

        // sqrt((a + b * (sqrt((k - m)^2 + sigma^2) + rho * (k - m)))/tau)
        return FixedPointMathLib.sqrt(uint256(w).divideDecimal(uint256(tau)));
    }

    /**
     * @dev k = ln(strike / fwd), but being bounded by B: -B < k < B
     * where B = TOTAL_VOL_SCALAR x sqrt(a + b * sig)
     */
    function getK(uint256 strike, int256 a, uint256 b, uint256 sigma, uint256 forwardPrice)
        internal
        pure
        returns (int256 k)
    {
        // calculate the bounds
        int256 volFactor = int256(FixedPointMathLib.sqrt((a + b.multiplyDecimal(sigma).toInt256()).toUint256()));
        int256 k_bound = volFactor.multiplyDecimal(TOTAL_VOL_SCALAR);
        int256 sk = int256(strike.divideDecimal(forwardPrice));

        if (sk == 0) return -k_bound;

        // k = ln (strike / fwd)
        k = FixedPointMathLib.ln(sk);

        // make sure -B < k < B
        if (k > k_bound) return k_bound;
        if (k < -k_bound) return -k_bound;
    }
}
