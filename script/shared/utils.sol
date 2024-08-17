// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Script.sol";

import {ECDSA} from "openzeppelin/utils/cryptography/EIP712.sol";

import {IBaseOracle} from "../../src/oracle/interfaces/IBaseOracle.sol";
import {Config} from "./types.sol";

contract Utils is Script {
    function _readDeployment(string memory chainName, string memory fileName) internal view returns (string memory) {
        string memory file = string.concat(vm.projectRoot(), "/deployments/", chainName, "/", fileName, ".json");
        return vm.readFile(file);
    }

    function _writeDeployment(string memory chainName, string memory fileName, string memory content) internal {
        string memory file = string.concat(vm.projectRoot(), "/deployments/", chainName, "/", fileName, ".json");
        vm.writeJson(content, file);
    }

    /// @dev get config from current chainId
    function _readConfig(string memory chainName) internal view returns (Config memory config) {
        string memory file = string.concat(vm.projectRoot(), "/script/shared/", chainName, "/config.json");
        string memory configJson = vm.readFile(file);

        config.usdc = abi.decode(vm.parseJson(configJson, ".usdc"), (address));
        config.oracleSigners = abi.decode(vm.parseJson(configJson, ".oracleSigners"), (address[]));
    }

    function _signOracleData(IBaseOracle oracle, uint256 privateKey, IBaseOracle.OracleData memory oracleData)
        internal
        view
        returns (bytes memory)
    {
        bytes32 typeHash = oracle.ORACLE_DATA_TYPEHASH();
        bytes32 structHash =
            keccak256(abi.encode(typeHash, keccak256(oracleData.data), oracleData.deadline, oracleData.timestamp));
        bytes32 domainSeparator = oracle.domainSeparator();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
        oracleData.signatures[0] = bytes.concat(r, s, bytes1(v));
        oracleData.signers[0] = vm.addr(privateKey);

        return abi.encode(oracleData);
    }
}
