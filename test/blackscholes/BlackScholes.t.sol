// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "forge-std/Vm.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {DecimalMath} from "../../src/external/decimals/DecimalMath.sol";
import {Black76} from "../../src/external/Black76.sol";

contract BlackScholesVerifierTest is Test {
    using DecimalMath for uint256;
    using SafeCast for uint256;

    struct Option {
        uint256 f;
        uint256 k;
        string optionType;
        uint256 price;
        uint256 rd;
        uint256 sigma;
        uint256 t;
    }

    string[] public callFiles;
    string[] public putFiles;

    function setUp() public {
        // call test case
        callFiles.push("iterate-fp-call.json");
        callFiles.push("iterate-k-call.json");
        callFiles.push("iterate-rate-call.json");
        callFiles.push("iterate-volatility-call.json");
        callFiles.push("iterate-t-call.json");

        // put test case
        putFiles.push("iterate-fp-put.json");
        putFiles.push("iterate-k-put.json");
        putFiles.push("iterate-rate-put.json");
        putFiles.push("iterate-volatility-put.json");
        putFiles.push("iterate-t-put.json");
    }

    function testCallPrice() public view {
        for (uint256 i = 0; i < callFiles.length; i++) {
            string memory content = _readFile(callFiles[i]);
            Option[] memory options = abi.decode(vm.parseJson(content), (Option[]));

            for (uint256 j = 0; j < options.length; j++) {
                (uint256 call,) = Black76.prices(
                    Black76.Black76Inputs({
                        timeToExpirySec: options[j].t.multiplyDecimal(365 days).toUint64(),
                        volatility: options[j].sigma.toUint128(),
                        fwdPrice: (options[j].f * 1e18).toUint128(),
                        strikePrice: (options[j].k * 1e18).toUint128(),
                        discount: options[j].rd.toUint64()
                    })
                );

                assertApproxEqAbs(options[j].price, call, 10e8);
                // console.log("price is %d, calculated call price is %d", options[i].price, call);
            }
        }
    }

    function testPutPrice() public view {
        for (uint256 i = 0; i < putFiles.length; i++) {
            string memory content = _readFile(putFiles[i]);
            Option[] memory options = abi.decode(vm.parseJson(content), (Option[]));

            for (uint256 j = 0; j < options.length; j++) {
                (, uint256 put) = Black76.prices(
                    Black76.Black76Inputs({
                        timeToExpirySec: options[j].t.multiplyDecimal(365 days).toUint64(),
                        volatility: options[j].sigma.toUint128(),
                        fwdPrice: (options[j].f * 1e18).toUint128(),
                        strikePrice: (options[j].k * 1e18).toUint128(),
                        discount: options[j].rd.toUint64()
                    })
                );

                assertApproxEqAbs(options[j].price, put, 10e8);
                // console.log("price is %d, calculated put price is %d", options[i].price, put);
            }
        }
    }

    function _readFile(string memory fileName) private view returns (string memory) {
        string memory dir = string.concat(vm.projectRoot(), "/test/blackscholes/data/");
        return vm.readFile(string.concat(dir, fileName));
    }
}
