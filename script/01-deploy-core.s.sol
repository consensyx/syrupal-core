// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console.sol";

import {IERC20Metadata} from "openzeppelin/token/ERC20/extensions/IERC20Metadata.sol";

import {Hub} from "../src/Hub.sol";
import {USDX} from "../src/token/USDX.sol";
import {Option} from "../src/Option.sol";
import {SpotOracle} from "../src/oracle/SpotOracle.sol";
import {Liquidation} from "../src/Liquidation.sol";
import {InsuranceFund} from "../src/InsuranceFund.sol";
import {PositionManager} from "../src/PositionManager.sol";
import {ManagerStorage} from "../src/ManagerStorage.sol";
import {BatchSubmitter} from "../src/oracle/BatchSubmitter.sol";

import {Utils} from "./shared/utils.sol";
import {Config, Market} from "./shared/types.sol";

contract DeployCoreScript is Utils {
    /**
     * forge script script/01_deploy-core.s.sol:DeployCoreScript -vvv \
     *     --rpc-url $RPC_URL \
     *     --broadcast \
     *     --slow \
     *     --verify
     */
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory chainName = vm.envString("CHAIN_NAME");

        address operator = vm.envAddress("OPERATOR");
        require(operator != address(0), "Invalid operator address");

        vm.startBroadcast(deployerPrivateKey);

        address usdc = abi.decode(
            vm.parseJson(
                vm.readFile(string.concat(vm.projectRoot(), "/script/shared/", chainName, "/config.json")), ".usdc"
            ),
            (address)
        );

        // #1 Deploy protocol core address
        Hub hub = new Hub();

        address managerAddress;
        // avoid stak too deep issue
        {
            address deployer = vm.addr(deployerPrivateKey);
            uint256 nonce = vm.getNonce(deployer);
            managerAddress = computeCreateAddress(deployer, nonce + 5);
        }

        // nonce + 1
        USDX usdx = new USDX(hub, PositionManager(managerAddress), IERC20Metadata(usdc));

        // nonce + 2
        InsuranceFund insuranceFund = new InsuranceFund(PositionManager(managerAddress), usdx, operator);

        // nonce + 3
        Liquidation liquidation = new Liquidation(PositionManager(managerAddress), insuranceFund);

        // nonce + 4
        Option option = new Option(hub, PositionManager(managerAddress), liquidation);

        // nonce + 5
        PositionManager positionManager =
            new PositionManager(hub, usdx, option, liquidation, operator, "PositionManager NFT", "PM-NFT");

        assert(managerAddress == address(positionManager));

        // #2 Hub set protocol account address
        hub.setProtocol(positionManager, usdx, option, liquidation, insuranceFund);

        // #3 Deploy stablecoin oracle
        SpotOracle stableOracle = new SpotOracle();

        // #4 set stablecoin oracle
        positionManager.setStableOracle(stableOracle);

        // #5 add signer for stableOracle
        Config memory config = _readConfig(chainName);
        _setSignerForOracles(stableOracle, config);

        // #6 set stablecoin oracle heartbeat
        stableOracle.setHeartbeat(20 minutes);

        // #7 set positionManager executor
        positionManager.setExecutor(address(insuranceFund), true);

        // #8 create insurance fund fee recipient subaccount whitelist
        insuranceFund.createRecipient();

        // #9 pm set depeg params
        positionManager.setDepegParams(ManagerStorage.DepegParams(0.98e18, 1.2e18));

        // #10 pm set trusted data reciever for stablecoin oracle
        positionManager.setDataReceiver(address(stableOracle), true);

        // #11 pm set FeeRecipient
        positionManager.setFeeRecipient(insuranceFund.recipient());

        // #12 USDX set FeeRecipient
        usdx.setFeeRecipient(insuranceFund.recipient());

        // #13 Oracle batch submitter
        BatchSubmitter batchSubmitter = new BatchSubmitter();

        // #14 save deployments
        string memory coreJsonKey = "Core";
        // vm.serializeAddress(coreJsonKey, "subAccount", address(subAccount));
        vm.serializeAddress(coreJsonKey, "hub", address(hub));
        vm.serializeAddress(coreJsonKey, "usdc", address(usdc));
        vm.serializeAddress(coreJsonKey, "option", address(option));
        vm.serializeAddress(coreJsonKey, "usdx", address(usdx));
        vm.serializeAddress(coreJsonKey, "liquidation", address(liquidation));
        vm.serializeAddress(coreJsonKey, "insuranceFund", address(insuranceFund));
        vm.serializeAddress(coreJsonKey, "stableOracle", address(stableOracle));
        vm.serializeAddress(coreJsonKey, "positionManager", address(positionManager));

        string memory jsonOutput = vm.serializeAddress(coreJsonKey, "batchSubmitter", address(batchSubmitter));

        _writeDeployment(chainName, "core", jsonOutput);
        vm.stopBroadcast();
    }

    function _setSignerForOracles(SpotOracle stableOracle, Config memory config) internal {
        for (uint256 i = 0; i < config.oracleSigners.length; ++i) {
            stableOracle.setSigner(config.oracleSigners[i], true);
        }
    }
}
