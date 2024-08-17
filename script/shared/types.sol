// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {SpotOracle} from "../../src/oracle/SpotOracle.sol";
import {ForwardOracle} from "../../src/oracle/ForwardOracle.sol";
import {VolatilityOracle} from "../../src/oracle/VolatilityOracle.sol";

struct Config {
    address usdc;
    bool useMockedOracle;
    address[] oracleSigners;
}

struct Market {
    SpotOracle spotOracle;
    VolatilityOracle volOracle;
    ForwardOracle forwardOracle;
}
