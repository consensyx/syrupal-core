// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/console.sol";

import {IBaseOracle} from "../src/oracle/interfaces/IBaseOracle.sol";
import {VolatilityOracle} from "../src/oracle/VolatilityOracle.sol";
import {SpotOracle} from "../src/oracle/SpotOracle.sol";
import {ForwardOracle} from "../src/oracle/ForwardOracle.sol";

import {Option} from "../src/Option.sol";
import {PositionManager} from "../src/PositionManager.sol";

import {ManagerStorage} from "../src/ManagerStorage.sol";

import {Utils} from "./shared/utils.sol";
import {Config, Market} from "./shared/types.sol";

contract DeployMarketScript is Utils {
    /**
     * forge script script/02_deploy-oracle.s.sol:DeployMarketScript -vvv \
     *     --rpc-url $RPC_URL \
     *     --broadcast \
     *     --slow \
     *     --verify
     */
    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory chainName = vm.envString("CHAIN_NAME");
        string memory marketName = vm.envString("MARKET_NAME");

        vm.startBroadcast(deployerPrivateKey);

        // #1 Load core deployments
        string memory coreDeployments = _readDeployment(chainName, "core");

        PositionManager positionManager =
            PositionManager(abi.decode(vm.parseJson(coreDeployments, ".positionManager"), (address)));

        // #2 Create market
        uint256 marketId = positionManager.createMarket(marketName);

        // #3 Set option margin params
        ManagerStorage.MarginParams memory marginParams = ManagerStorage.MarginParams({
            IMUpperRatio: vm.envUint("IMUPPERRATIO"),
            IMLowerRatio: vm.envUint("IMLOWERRATIO"),
            MMRatio: vm.envUint("MMRATIO")
        });

        positionManager.setMarginParams(marketId, marginParams);

        // #4 deploy market oracles and set heartbeats
        Market memory market = _deployMarketOracles();

        // #5 set market oracle fees
        positionManager.setMarketOracles(marketId, market.spotOracle, market.forwardOracle, market.volOracle);

        // #6 set trusted data receiver for market oracles
        positionManager.setDataReceiver(address(market.spotOracle), true);
        positionManager.setDataReceiver(address(market.forwardOracle), true);
        positionManager.setDataReceiver(address(market.volOracle), true);

        // #7 set market settlement oracle for option
        Option option = Option(abi.decode(vm.parseJson(coreDeployments, ".option"), (address)));
        option.setForwardOracle(uint16(marketId), address(market.forwardOracle));

        // #8 set oracle oracles signer(keeper)
        Config memory config = _readConfig(chainName);

        _setSignerForOracles(market, config);

        // #9 save deployments
        string memory marketJsonKey = "Market-Deployments";

        vm.serializeAddress(marketJsonKey, "spotOracle", address(market.spotOracle));
        vm.serializeAddress(marketJsonKey, "forwardOracle", address(market.forwardOracle));
        string memory jsonOutput = vm.serializeAddress(marketJsonKey, "volOracle", address(market.volOracle));

        _writeDeployment(chainName, marketName, jsonOutput);

        vm.stopBroadcast();
    }

    function _deployMarketOracles() internal returns (Market memory market) {
        market.spotOracle = new SpotOracle();
        market.forwardOracle = new ForwardOracle(market.spotOracle);
        market.volOracle = new VolatilityOracle();

        // set heartbeat rate
        market.spotOracle.setHeartbeat(20 minutes);
        market.volOracle.setHeartbeat(120 minutes);
        market.forwardOracle.setHeartbeat(20 minutes);
        market.forwardOracle.setSettleHeartbeat(60 minutes);
    }

    function _setSignerForOracles(Market memory market, Config memory config) internal {
        for (uint256 i = 0; i < config.oracleSigners.length; ++i) {
            market.spotOracle.setSigner(config.oracleSigners[i], true);
            market.volOracle.setSigner(config.oracleSigners[i], true);
            market.forwardOracle.setSigner(config.oracleSigners[i], true);
        }
    }
}
