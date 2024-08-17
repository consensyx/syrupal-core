// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "../../../src/oracle/BaseOracle.sol";

import "forge-std/Test.sol";

contract OracleTestUtils is Test {
    function _signOracleData(IBaseOracle oracle, uint256 privateKey, IBaseOracle.OracleData memory oracleData)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = hashOracleData(oracle, oracleData);
        bytes32 domainSeparator = oracle.domainSeparator();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
        oracleData.signatures[0] = bytes.concat(r, s, bytes1(v));

        if (oracleData.signers[0] == address(0)) oracleData.signers[0] = vm.addr(privateKey);

        return abi.encode(oracleData);
    }

    function hashOracleData(IBaseOracle oracle, IBaseOracle.OracleData memory oracleData)
        public
        view
        returns (bytes32)
    {
        bytes32 typeHash = oracle.ORACLE_DATA_TYPEHASH();
        return keccak256(abi.encode(typeHash, keccak256(oracleData.data), oracleData.deadline, oracleData.timestamp));
    }

    function setSpotData(uint96 price, uint256 duration) public view returns (IBaseOracle.OracleData memory) {
        bytes memory spotData = abi.encode(price);

        return IBaseOracle.OracleData({
            data: spotData,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + duration,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }
}
