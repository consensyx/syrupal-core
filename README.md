# Syrupal Core


## About Syrupal
Syrupal is an on-chain Option Exchange. Currently, there are two main types of options exchanges. One is implemented through AMM-based Uniswap v3 pools, but these are not standard options and at most can be considered pseudo-options. The other type involves offline pricing for options. Our approach uses smart contracts to implement the BSM model for transparent contract pricing.

## How to Trade Options
The first thing to consider is how to buy and sell options. In our contract, this is achieved through the PositionManager contract's *batchTransfers* function.

```solidity

IAsset.BalanceTransfer[] memory transfers = new IAsset.BalanceTransfer[](2);

// Alice long position and Bob short position
transfers[0] = IAsset.BalanceTransfer({from: bob, to: alice, asset: option, subId: subId, amount: optionAmount});

// Alice pays USDX to Bob
transfers[1] = IAsset.BalanceTransfer({from: alice, to: bob, asset: usdx, subId: 0, amount: usdxAmount});

positionManager.batchTransfers(transfers, "");
Our order matching is done through an offline matching engine, so batchTransfers can handle multiple transactions simultaneously.

```

In **batchTransfer** function, our implementation is similar to a flash loan. We first assume that the user's assets are sufficient to meet the MM requirement and update the user's balance through **updateBalance**. Then, we evaluate the user's margin using the **evaluateMargin** function. If the margin requirement is not met, the entire transaction will be reverted.

## SubAccount
Like many derivatives trading systems, we also use SubAccount mechanism to manage user assets. A single EVM address can create multiple SubAccounts, and the assets of each SubAccount are isolated from one another.

We implement each SubAccount as a unique ERC721 token ID by inheriting the ERC721 contract in the PositionManager contract.

## Asset Composition
User assets consist of two parts: USDX (which can be understood as the internal cash of the Syrupal system) and Option positions.

## USDX Contract
USDX can be understood as the stablecoin token within the Syrupal system. It essentially acts as cash. By locking USDC in the contract, USDX is minted at a 1:1 ratio, enabling the management of cash within the contract. From this perspective, the USDX contract functions like a central bank within the system, responsible for minting and burning assets.

Considering the nature of trading profits and losses, a user's USDX balance in reality might be negative. Therefore, we define the user's balance data type as int instead of uint. To accommodate this feature while ensuring that the USDX totalSupply does not overflow or underflow, our design approach involves using grossSupply and grossDebt as global variables to solve this issue.

Additionally, given the nature of options products requiring exercise, our options exercise process is sequential for each account. For example, if Alice and Bob are counterparties to a specific option and Alice earns $100, then Bob must lose $100. If Alice's account is exercised first, adding $100, this would temporarily increase the USDX totalSupply. We address this with a temporarySupply variable.

## Margin
Similar to professional options exchanges, our contract also supports two types of margins: Initial Margin (IM) and Maintenance Margin (MM). You can search for professional definitions of these terms.

Typically, the Initial Margin is higher than the Maintenance Margin.

Long positions do not require margin, only short positions do.

When a user opens a new position, their USDX balance minus the IM must be greater than 0. However, when determining if a user's assets are in liquidation, we assess whether their USDX balance is greater than the MM.

## About Liquidation
When a user's USDX balance falls below the MM, they need to be liquidated. The liquidation process consists of the following stages:

* Mark the user as liquidated.
* Auction the user's assets at market price.
* If the market order does not fully process the user's assets and liabilities, continue auctioning the user's assets at a discounted price.

If at any step the user's assets return above the IM (initial margin), the user can be reclassified as a normal user. If the requirement is not met, the process continues to the below steps


* Takeover: If after these stages the user's assets are still below the MM, invoke the takeover function in the PositionManager contract, transferring all the user's assets (including USDX) to the Insurance Fund account.
* AutoDeleverage: The offline matching engine, following an algorithm, typically selects the largest profit-holder of this option in the market as the counterparty to trade with the Insurance Fund. The closed positions are automatically settled according to BSM pricing, and the counterparty's profits and losses are fully transparent.


## About Insurance Fund
All protocol fees, such as open interest fees, maker fees, and taker fees, go into this account.
All liquidated users' assets and liabilities are transferred to the Insurance Fund at the takeover stage.

When closing positions for the Insurance Fund, profits and losses (usually losses) are borne by the Insurance Fund.

If the USDX in the Insurance Fund is insufficient to pay the counterparty during a position closing (AutoDeleverage), the shortfall will be covered by minting additional USDX. This will cause the USDX totalSupply to exceed the actual USDC balance locked in the USDX contract.

When the USDC/USDX exchange rate drops below 1, you can call the donate function in the Insurance Fund contract to make up the shortfall, restoring the exchange rate to 1.

## Oracle
Since we are an options derivatives project, the accuracy and timeliness of price and volatility data are extremely important. Instead of using third-party projects like Chainlink, we use data from third-party service providers to supply us with spot prices, forward prices, and volatility data. Our backend programs write this real-time data into the contract.



## Commands

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
