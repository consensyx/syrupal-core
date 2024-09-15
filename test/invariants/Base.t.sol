// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import {SafeCast} from "openzeppelin/utils/math/SafeCast.sol";
import {Encoding} from "../../src/external/Encoding.sol";
import {DecimalMath} from "../../src/external/decimals/DecimalMath.sol";

import "../../src/Hub.sol";
import "../../src/InsuranceFund.sol";
import {USDX} from "../../src/token/USDX.sol";
import "../../src/Option.sol";
import "../../src/Liquidation.sol";
import "../../src/PositionManager.sol";
import "../../src/ManagerStorage.sol";

import "../../src/oracle/BaseOracle.sol";
import "../../src/oracle/SpotOracle.sol";
import "../../src/oracle/VolatilityOracle.sol";
import "../../src/oracle/ForwardOracle.sol";

import "../../src/mocks/MockERC20.sol";

contract BaseTest is Test {
    using SafeCast for uint256;
    using DecimalMath for uint256;

    struct Market {
        uint256 id;
        SpotOracle spotOracle;
        VolatilityOracle volOracle;
        ForwardOracle forwardOracle;
    }

    struct SVIData {
        int256 SVI_a;
        int256 SVI_b;
        int256 SVI_rho;
        int256 SVI_m;
        int256 SVI_sigma;
    }

    uint256 signerPK = 0x12345678;
    address signer = vm.addr(signerPK);

    MockERC20 public usdc;

    IHub public hub;

    USDX public usdx;

    Option public option;

    InsuranceFund public insuranceFund;

    Liquidation public liquidation;

    PositionManager public positionManager;

    SpotOracle internal stableOracle;

    mapping(string => Market) internal markets;

    function setUp() public virtual {
        _deployCore();
        _setupCore();
        _createMarket("ETH");
        _createMarket("BTC");
    }

    function _deployCore() internal {
        usdc = new MockERC20("USDC", "USDC", 6);

        hub = new Hub();

        address managerAddress = vm.computeCreateAddress(address(this), 7);
        usdx = new USDX(hub, PositionManager(managerAddress), usdc);

        insuranceFund = new InsuranceFund(PositionManager(managerAddress), usdx, address(this));

        liquidation = new Liquidation(PositionManager(managerAddress), insuranceFund);

        option = new Option(hub, PositionManager(managerAddress), liquidation);

        positionManager =
            new PositionManager(hub, usdx, option, liquidation, address(this), "Margin Accounts", "MarginNFTs");

        assertEq(managerAddress, address(positionManager));

        hub.setProtocol(positionManager, usdx, option, liquidation, insuranceFund);

        stableOracle = new SpotOracle();
    }

    function _setupCore() internal {
        // setup stable oracle
        positionManager.setStableOracle(stableOracle);
        positionManager.setDataReceiver(address(stableOracle), true);

        stableOracle.setHeartbeat(60 minutes);
        stableOracle.setSigner(signer, true);

        // set depeg parmas
        positionManager.setDepegParams(ManagerStorage.DepegParams(0.98e18, 1.2e18));

        positionManager.setExecutor(address(this), true);
        positionManager.setExecutor(address(insuranceFund), true);
        insuranceFund.createRecipient();
        usdx.setFeeRecipient(insuranceFund.recipient());
    }

    function _createMarket(string memory key) internal returns (uint256 marketId) {
        marketId = positionManager.createMarket(key);

        markets[key].id = marketId;
        markets[key].spotOracle = new SpotOracle();
        markets[key].forwardOracle = new ForwardOracle(markets[key].spotOracle);
        markets[key].volOracle = new VolatilityOracle();

        markets[key].spotOracle.setHeartbeat(20 minutes);
        markets[key].volOracle.setHeartbeat(20 minutes);

        markets[key].forwardOracle.setHeartbeat(20 minutes);
        markets[key].forwardOracle.setSettleHeartbeat(60 minutes);

        // set oracles
        positionManager.setMarketOracles(
            marketId, markets[key].spotOracle, markets[key].forwardOracle, markets[key].volOracle
        );

        // set margin params
        ManagerStorage.MarginParams memory marginParams =
            ManagerStorage.MarginParams({IMUpperRatio: 0.2e18, IMLowerRatio: 0.13e18, MMRatio: 0.1e18});

        positionManager.setMarginParams(marketId, marginParams);

        option.setForwardOracle(uint16(marketId), address(markets[key].forwardOracle));

        _setSignerForOracles(key, signer);
    }

    function _setSignerForOracles(string memory key, address _signer) internal {
        markets[key].spotOracle.setSigner(_signer, true);
        markets[key].volOracle.setSigner(_signer, true);
        markets[key].forwardOracle.setSigner(_signer, true);
    }

    function _setSpotPrice(string memory key, uint96 price) internal {
        SpotOracle spotOracle = markets[key].spotOracle;

        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: abi.encode(price, 1e18),
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 100,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        spotOracle.receiveData(_signOracleData(spotOracle, signerPK, oracleData));
    }

    function _setForwardPrice(string memory key, uint64 expiry, uint256 price) internal {
        ForwardOracle oracle = markets[key].forwardOracle;

        uint256 spot = markets[key].spotOracle.getSpot();

        int96 diff = int96(int256(price) - int256(spot));

        uint256 startAggregate = price * uint256(expiry - oracle.SETTLEMENT_TWAP_DURATION());
        uint256 currAggregate = price * uint256(expiry);

        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: abi.encode(expiry, startAggregate, currAggregate, diff, 1e18),
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        oracle.receiveData(_signOracleData(oracle, signerPK, oracleData));
    }

    function _setStablePrice(uint256 price) internal {
        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: abi.encode(price, 1e18),
            deadline: block.timestamp + 100,
            timestamp: uint64(block.timestamp),
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        stableOracle.receiveData(_signOracleData(stableOracle, signerPK, oracleData));
    }

    function _setVolatility(string memory key, uint256 forward, uint64 expiry, SVIData memory svi) internal {
        VolatilityOracle volOracle = markets[key].volOracle;

        uint64 SVI_refTau = uint64(Black76.annualise(uint64(expiry - block.timestamp)));

        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: abi.encode(expiry, svi.SVI_a, svi.SVI_b, svi.SVI_rho, svi.SVI_m, svi.SVI_sigma, forward, SVI_refTau),
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 20,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        // sign data
        bytes memory data = _signOracleData(volOracle, signerPK, oracleData);

        volOracle.receiveData(data);
    }

    function _signOracleData(IBaseOracle oracle, uint256 privateKey, IBaseOracle.OracleData memory oracleData)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = _hashOracleData(oracle, oracleData);
        bytes32 domainSeparator = oracle.domainSeparator();
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
        oracleData.signatures[0] = bytes.concat(r, s, bytes1(v));
        oracleData.signers[0] = vm.addr(privateKey);

        return abi.encode(oracleData);
    }

    function _hashOracleData(IBaseOracle oracle, IBaseOracle.OracleData memory oracleData)
        internal
        view
        returns (bytes32)
    {
        bytes32 typeHash = oracle.ORACLE_DATA_TYPEHASH();
        return keccak256(abi.encode(typeHash, keccak256(oracleData.data), oracleData.deadline, oracleData.timestamp));
    }
}
