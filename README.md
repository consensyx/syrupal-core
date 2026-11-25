# Syrupal Core

## Overview

Syrupal is an on-chain options protocol with off-chain order matching and fully on-chain settlement, margining, liquidation, and pricing.

Option prices are evaluated natively in Solidity using the `Black-76` model, a forward-based `Black-Scholes-Merton` (BSM) variant. As with protocols such as [Derive](https://github.com/derivexyz/v2-core), option pricing is not delegated to an off-chain pricing engine.

Syrupal is not currently operating as a live protocol. This repository preserves its core contracts.

I, [xris-dev](https://github.com/xris-dev), developed Syrupal Core's smart contracts during 2024.03–2024.09 while working on the Syrupal Protocol.

## Architecture

- **PositionManager** — ERC-721 subaccounts, atomic settlement, portfolio margin, exercise, takeover, and auto-deleveraging.
- **Option** — option position accounting, payoff calculation, and open-interest fees.
- **USDX** — collateral-backed internal cash ledger with support for signed account balances.
- **Spot / Forward / Volatility Oracles** — signed market-data submission and verification.
- **Liquidation** — liquidation-state management.
- **InsuranceFund** — protocol fees, takeover accounting, and insolvency handling.
- **Black76** — on-chain Black-76 option-pricing library.

## Trading and Settlement

Orders are matched off-chain. An authorized executor submits matched transfers through `PositionManager.batchTransfers`, which atomically updates balances and verifies margin requirements before a transaction can settle.

Each account is represented by an ERC-721 subaccount. Subaccounts isolate collateral and positions while allowing a wallet to manage multiple trading accounts.

## Risk Model

The protocol distinguishes between Initial Margin (IM) and Maintenance Margin (MM). Opening or increasing risk must satisfy IM; an account below MM may enter liquidation. Long option positions do not require margin, while short positions do.

Liquidation is coordinated off-chain and enforced on-chain. A liquidated account may be restored through matched transfers; otherwise, its positions and USDX balance can be taken over by the Insurance Fund and reduced through auto-deleveraging.

## USDX and Insurance Fund

USDX is the protocol's collateral-backed internal cash ledger. Deposits and withdrawals use the underlying stablecoin, while individual subaccounts may carry signed USDX balances to represent trading profit and loss. The Insurance Fund receives protocol fees, assumes balances during takeover, and handles insolvency shortfalls.

## Oracle Model

Spot, forward, and volatility data are submitted on-chain as signed payloads. Oracle contracts verify approved signers, signature thresholds, timestamps, deadlines, and heartbeat constraints before accepting data.

## Engineering Design

### EIP-1153 Transient Storage

Syrupal uses EIP-1153 transient storage (`TLOAD` / `TSTORE`) as a core execution primitive for batch settlement and portfolio risk evaluation.

A single expiry may contain many option series with different strikes and call/put directions, while sharing the same market-level spot price and expiry-level forward price. During a transaction, the protocol caches these shared inputs in transient storage, avoiding repeated oracle reads and persistent-storage writes while evaluating multiple positions.

Transient storage is also used to track per-transaction subaccount state, open-interest snapshots, and reentrancy locks. All transient state is automatically cleared when the transaction completes, making it well suited to atomic settlement flows.

This design improves gas efficiency without persisting intermediate state beyond the transaction.

## Audit

The historical Syrupal Core codebase was audited by [PeckShield](https://peckshield.com/). The full report is available at [`audits`](./audits/).

In post-audit feedback, a PeckShield reviewer described Syrupal as “one of the best” option protocols they had audited, citing its “elegant option design and clean implementation.” The original feedback is preserved [here](./audits/Peckshield-feedback.png).


## Development

Requirements:

- Foundry
- Solidity `0.8.24`
- Cancun-compatible EVM, due to transient storage usage

### Build
```shell
forge build
```

### Test
```
forge test
```

## License

Copyright © 2024 consensyx. All rights reserved.

This repository is proprietary. Any use, copying, modification, distribution,
deployment, or derivative work requires prior written permission from the
copyright holder.

For licensing, commercial use, or collaboration inquiries, please contact:https://github.com/consensyx.
