// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import {EIP712, ECDSA} from "openzeppelin/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";
import {Ownable2Step} from "openzeppelin/access/Ownable2Step.sol";

import {Errors} from "../libraries/Errors.sol";
import {FixedPointMathLib} from "../external/FixedPointMathLib.sol";

import {IReceiver} from "../interfaces/IReceiver.sol";
import {IVolatilityOracle} from "./interfaces/IVolatilityOracle.sol";
import {IBaseOracle} from "./interfaces/IBaseOracle.sol";

abstract contract BaseOracle is EIP712, Ownable2Step, IReceiver, IBaseOracle {
    bytes32 public constant ORACLE_DATA_TYPEHASH = keccak256("OracleData(bytes data,uint256 deadline,uint64 timestamp)");

    /// @dev mapping of address to whether they are whitelisted signers
    mapping(address => bool) public isSigner;

    /// @dev number of signers required to submit data
    uint8 public minimumSigners = 1;

    uint64 public heartbeat;

    constructor(string memory name, string memory version) EIP712(name, version) {}

    function setSigner(address signer, bool isWhitelisted) external onlyOwner {
        isSigner[signer] = isWhitelisted;
        emit SignerUpdated(signer, isWhitelisted);
    }

    function setMinimumSigners(uint8 newMinimumSigners) external onlyOwner {
        if (newMinimumSigners == 0) revert Errors.InvalidMinimumSigners();
        minimumSigners = newMinimumSigners;

        emit MinimumSignersUpdated(newMinimumSigners);
    }

    function setHeartbeat(uint64 newHeartbeat) external onlyOwner {
        heartbeat = newHeartbeat;
    }

    /// @dev get domain separator for signing
    function domainSeparator() external view returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _checkHeartbeat(uint64 timestamp) internal view {
        if (timestamp + heartbeat < block.timestamp) {
            revert Errors.ExpiredData();
        }
    }

    /// @dev parse data into OracleDa and verify signature, deadline and signed timestamp
    function _verifyData(bytes memory data) internal view returns (OracleData memory oracleData) {
        oracleData = abi.decode(data, (OracleData));
        bytes32 hashedData = hashOracleData(oracleData);
        // check the signature is from the signer is valid
        uint256 numOfSigners = oracleData.signers.length;
        if (numOfSigners < minimumSigners) revert Errors.NotEnoughSigners();
        if (numOfSigners != oracleData.signatures.length) revert Errors.SignatureSignersLengthMismatch();

        // verify all signatures
        for (uint256 i = 0; i < numOfSigners; i++) {
            // check that the signer has not signed before
            for (uint256 j = 0; j < i; j++) {
                if (oracleData.signers[i] == oracleData.signers[j]) {
                    revert Errors.DuplicatedSigner();
                }
            }

            if (
                !SignatureChecker.isValidSignatureNow(
                    oracleData.signers[i], _hashTypedDataV4(hashedData), oracleData.signatures[i]
                )
            ) {
                revert Errors.InvalidSignature();
            }

            // check that it is a valid signer
            if (!isSigner[oracleData.signers[i]]) {
                revert Errors.InvalidSigner();
            }
        }

        // check the deadline
        if (oracleData.deadline < block.timestamp) {
            revert Errors.ExpiredData();
        }

        // signed timestamp cannot be in the future
        if (oracleData.timestamp > block.timestamp) {
            revert Errors.InvalidTimestamp();
        }
    }

    function hashOracleData(OracleData memory oracleData) public pure returns (bytes32) {
        return keccak256(
            abi.encode(ORACLE_DATA_TYPEHASH, keccak256(oracleData.data), oracleData.deadline, oracleData.timestamp)
        );
    }
}
