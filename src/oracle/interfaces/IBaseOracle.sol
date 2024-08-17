// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

interface IBaseOracle {
    function domainSeparator() external view returns (bytes32);

    function ORACLE_DATA_TYPEHASH() external view returns (bytes32);

    struct OracleData {
        bytes data;
        uint256 deadline;
        uint64 timestamp;
        address[] signers;
        bytes[] signatures;
    }

    event SignerUpdated(address indexed signer, bool isWhitelisted);

    event HeartbeatUpdated(address indexed signer, uint256 heartbeat);

    event MinimumSignersUpdated(uint256 minimumSigners);
}
