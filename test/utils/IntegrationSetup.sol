// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "forge-std/Test.sol";

import "../../src/external/Encoding.sol";

import "../../src/Hub.sol";
import {USDX} from "../../src/token/USDX.sol";
import "../../src/Option.sol";
import "../../src/Liquidation.sol";
import "../../src/InsuranceFund.sol";
import "../../src/PositionManager.sol";
import "../../src/ManagerStorage.sol";

import "../../src/oracle/BaseOracle.sol";
import "../../src/oracle/SpotOracle.sol";
import "../../src/oracle/VolatilityOracle.sol";
import "../../src/oracle/ForwardOracle.sol";

import "../../src/mocks/MockERC20.sol";

contract IntegrationSetup is Test {
    struct Market {
        uint256 id;
        SpotOracle spotOracle;
        VolatilityOracle volOracle;
        ForwardOracle forwardOracle;
    }

    uint256 public constant DEFAULT_DEPOSIT = 5000e18;
    int256 public constant ETH_PRICE = 2000e18;

    uint256 signerPK = 0xfffffff;
    address signer = vm.addr(signerPK);

    address alice = address(0x1234);
    address bob = address(0x2345);

    uint256 aliceAcc;
    uint256 bobAcc;

    MockERC20 public usdc;

    IHub public hub;

    USDX public usdx;

    Option public option;

    InsuranceFund public insuranceFund;

    Liquidation public liquidation;

    PositionManager public positionManager;

    SpotOracle internal stableOracle;

    mapping(string => Market) internal markets;

    function _setupIntegration() internal {
        _deployV2Core();
        _setupCoreContracts();
        uint256 mktid = _deployMarket("weth", 2000e18);
        mktid = _deployMarket("wbtc", 25000e18);

        _setupAliceAndBob();
    }

    function _setupAliceAndBob() internal {
        vm.label(alice, "alice");
        vm.label(bob, "bob");

        aliceAcc = positionManager.createSubAccount(alice);
        vm.prank(alice);
        positionManager.approve(address(this), aliceAcc);
        vm.stopPrank();

        bobAcc = positionManager.createSubAccount(bob);
        vm.prank(bob);
        positionManager.approve(address(this), bobAcc);
        vm.stopPrank();
    }

    function _deployV2Core() internal {
        hub = new Hub();

        usdc = new MockERC20("USDC", "USDC", 6);

        address managerAddress = computeCreateAddress(address(this), 7);

        usdx = new USDX(hub, PositionManager(managerAddress), usdc);

        insuranceFund = new InsuranceFund(PositionManager(managerAddress), usdx, address(this));

        liquidation = new Liquidation(PositionManager(managerAddress), insuranceFund);

        option = new Option(hub, PositionManager(managerAddress), liquidation);

        positionManager =
            new PositionManager(hub, usdx, option, liquidation, address(this), "Margin Accounts", "MarginNFTs");

        hub.setProtocol(positionManager, usdx, option, liquidation, insuranceFund);

        stableOracle = new SpotOracle();
        stableOracle.setSigner(signer, true);
        stableOracle.setHeartbeat(20 minutes);

        _setStablePrice(stableOracle, 1e18);
    }

    function _setupCoreContracts() internal {
        positionManager.setStableOracle(stableOracle);
        positionManager.setDepegParams(ManagerStorage.DepegParams(0.98e18, 1.2e18));

        positionManager.setExecutor(address(this), true);
        positionManager.setExecutor(address(insuranceFund), true);
        insuranceFund.createRecipient();
        usdx.setFeeRecipient(insuranceFund.recipient());
    }

    function _deployMarket(string memory key, uint96 initSpotPrice) internal returns (uint256 marketId) {
        _deployMarketContracts(key);

        marketId = _createMarket(key);

        option.setForwardOracle(uint16(marketId), address(markets[key].forwardOracle));

        _setSignerForOracles(key, signer);

        _setSpotPrice(key, initSpotPrice);
    }

    function _deployMarketContracts(string memory token) internal {
        Market storage market = markets[token];

        market.spotOracle = new SpotOracle();
        market.forwardOracle = new ForwardOracle(market.spotOracle);
        market.volOracle = new VolatilityOracle();

        market.spotOracle.setHeartbeat(1 minutes);
        market.volOracle.setHeartbeat(20 minutes);

        market.forwardOracle.setHeartbeat(20 minutes);
        market.forwardOracle.setSettleHeartbeat(60 minutes);
    }

    function _setSignerForOracles(string memory key, address _signer) internal {
        markets[key].spotOracle.setSigner(_signer, true);
        markets[key].volOracle.setSigner(_signer, true);
        markets[key].forwardOracle.setSigner(_signer, true);
    }

    function _createMarket(string memory key) internal returns (uint256 marketId) {
        Market storage market = markets[key];

        marketId = positionManager.createMarket(key);
        market.id = marketId;

        positionManager.setMarketOracles(marketId, market.spotOracle, market.forwardOracle, market.volOracle);

        ManagerStorage.MarginParams memory marginParams =
            ManagerStorage.MarginParams({IMUpperRatio: 0.2e18, IMLowerRatio: 0.13e18, MMRatio: 0.075e18});

        positionManager.setMarginParams(marketId, marginParams);
    }

    function _depositUSD(address user, uint256 acc, uint256 usdxAmount) internal {
        uint256 uscAmount = usdxAmount / 1e12;
        usdc.mint(user, uscAmount);

        vm.startPrank(user);
        usdc.approve(address(usdx), type(uint256).max);
        usdx.deposit(acc, uscAmount);
        vm.stopPrank();
    }

    function _withdrawUSD(address user, uint256 acc, uint256 usdxAmount) internal {
        uint256 uscAmount = usdxAmount / 1e12;
        vm.startPrank(user);
        usdx.withdraw(acc, uscAmount, user);
        vm.stopPrank();
    }

    function _trade(
        uint256 accA,
        IAsset assetA,
        uint112 subIdA,
        int256 amountA,
        uint256 accB,
        IAsset assetB,
        uint256 subIdB,
        int256 amountB
    ) internal {
        IAsset.BalanceTransfer[] memory transferBatch = new IAsset.BalanceTransfer[](2);

        transferBatch[0] = IAsset.BalanceTransfer({from: accA, to: accB, asset: assetA, subId: subIdA, amount: amountA});

        transferBatch[1] =
            IAsset.BalanceTransfer({from: accB, to: accA, asset: assetB, subId: uint112(subIdB), amount: amountB});

        positionManager.batchTransfers(transferBatch, "");
    }

    function _assertExchangeRate() internal {
        assertEq(usdx.getExchangeRate(), 1e18);
    }

    function getUSDXBalance(uint256 acc) public view returns (int256) {
        return usdx.balances(acc);
    }

    function getOptionBalance(uint256 acc, uint96 subId) public view returns (int256) {
        return option.getPositionBalance(acc, subId);
    }

    function getSubId(uint16 marketId, uint256 expiry, uint256 strike, bool isCall) public pure returns (uint112) {
        return Encoding.toSubId(marketId, expiry, strike, isCall);
    }

    function _setStablePrice(BaseOracle oracle, uint96 price) internal {
        bytes memory data = abi.encode(price);
        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: data,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        oracle.receiveData(_signOracleData(oracle, signerPK, oracleData));
    }

    function _setSpotPrice(string memory key, uint96 price) internal {
        SpotOracle spotOracle = markets[key].spotOracle;
        bytes memory data = abi.encode(price);
        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: data,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        spotOracle.receiveData(_signOracleData(spotOracle, signerPK, oracleData));
    }

    function _setSettlementPrice(string memory key, uint64 expiry, uint256 price) internal {
        ForwardOracle oracle = markets[key].forwardOracle;

        uint256 spot = markets[key].spotOracle.getSpot();

        int96 diff = int96(int256(price) - int256(spot));

        uint256 startAggregate = price * uint256(expiry - oracle.SETTLEMENT_TWAP_DURATION());
        uint256 currAggregate = price * uint256(expiry);

        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: abi.encode(expiry, startAggregate, currAggregate, diff, 1e18),
            timestamp: uint64(expiry), // timestamp need to be expiry to be used as settlement data
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        oracle.receiveData(_signOracleData(oracle, signerPK, oracleData));
    }

    function _getForwardPrice(string memory key, uint256 expiry) internal view returns (uint256) {
        return markets[key].forwardOracle.getForwardPrice(uint64(expiry));
    }

    function _setForwardPrice(string memory key, uint64 expiry, uint256 price) internal {
        ForwardOracle oracle = markets[key].forwardOracle;

        uint256 spot = markets[key].spotOracle.getSpot();

        int96 diff = int96(int256(price) - int256(spot));

        IBaseOracle.OracleData memory oracleData = IBaseOracle.OracleData({
            data: abi.encode(expiry, 0, 0, diff),
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });

        oracle.receiveData(_signOracleData(oracle, signerPK, oracleData));
    }

    function _setDefaultSVIForExpiry(string memory key, uint64 expiry) internal {
        vm.warp(block.timestamp + 5);

        ForwardOracle forwardOracle = markets[key].forwardOracle;
        uint256 fwdPrice = forwardOracle.getForwardPrice(uint64(expiry));

        VolatilityOracle volOracle = markets[key].volOracle;

        IBaseOracle.OracleData memory oracleData = _getDefaultVolData(expiry, fwdPrice);

        bytes memory data = _signOracleData(volOracle, signerPK, oracleData);

        volOracle.receiveData(data);
    }

    function _signOracleData(IBaseOracle oracle, uint256 privateKey, IBaseOracle.OracleData memory oracleData)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = hashOracleData(oracle, oracleData);
        bytes32 domainSeparator = oracle.domainSeparator();

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, ECDSA.toTypedDataHash(domainSeparator, structHash));
        oracleData.signatures[0] = bytes.concat(r, s, bytes1(v));
        oracleData.signers[0] = vm.addr(privateKey);

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

    function _getDefaultVolData(uint64 expiry, uint256 fwdPrice)
        internal
        view
        returns (IBaseOracle.OracleData memory)
    {
        int256 SVI_a = 1e18;
        uint256 SVI_b = 1.5e18;
        int256 SVI_rho = -0.1e18;
        int256 SVI_m = -0.05e18;
        uint256 SVI_sigma = 0.05e18;
        uint256 SVI_fwd = fwdPrice;
        uint64 SVI_refTau = uint64(Black76.annualise(uint64(expiry - block.timestamp)));

        // example data: a = 1, b = 1.5, sig = 0.05, rho = -0.1, m = -0.05
        bytes memory volData = abi.encode(expiry, SVI_a, SVI_b, SVI_rho, SVI_m, SVI_sigma, SVI_fwd, SVI_refTau);
        return IBaseOracle.OracleData({
            data: volData,
            timestamp: uint64(block.timestamp),
            deadline: block.timestamp + 5,
            signers: new address[](1),
            signatures: new bytes[](1)
        });
    }
}
