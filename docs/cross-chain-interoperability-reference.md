# Cross-Chain Interoperability Reference (XCM + Hyperbridge EVM/ISMP)

## Sources
- https://docs.polkadot.com/develop/interoperability/intro-to-xcm/
- https://docs.hyperbridge.network/developers/evm/getting-started

## Context in this repo
`docs/PRD.md` describes cross-chain needs for Paix:
- XCM: parachain-to-parachain communication.
- Snowbridge: trust-minimized Polkadot <-> Ethereum bridge.
- Hyperbridge: decentralized state verification + secure cross-chain messaging (coprocessor model).

This document summarizes the concepts above so proposal/specs can reference them.

---

## XCM (Cross-Consensus Messaging)

### What XCM is (and is not)
- XCM is a **standardized messaging format**, not a transport protocol.
- It defines the **structure and behavior** of messages, while delivery happens via the host environment / underlying channels.

### Design characteristics (from Polkadot docs)
- **Intent-driven**: a message describes actions the destination chain should attempt.
- **Host-interpreted**: messages do not “execute themselves”; the destination chain interprets and applies them.

### Four principles
- **Asynchronous**: no sender-side blocking/ack is required.
- **Absolute**: intended delivery + interpretation guarantees.
- **Asymmetric**: “fire and forget”; any result needs an explicit response message.
- **Agnostic**: independent of consensus mechanism; compatible across diverse systems.

### Core functionalities highlighted in the doc
- **Programmability**: version checks, branching, asset operations.
- **Functional multichain decomposition**: remote asset locking, asset namespacing, inter-chain references.
- **Bridging**: supports multi-hop referencing with the relay chain as a universal location framework.

### Example: local token transfer message structure
The Polkadot doc gives a simplified XCM message (conceptual) comprised of typical steps:
- `WithdrawAsset`: move asset from origin account into a holding register.
- `BuyExecution`: pay fees to buy execution weight.
- `DepositAsset`: deposit remaining assets from holding register to beneficiary.

High-level takeaway:
- XCM-based asset movement is expressed as **a sequence of instructions** and requires **fees/weight** to execute.

---

## Hyperbridge (EVM) + ISMP (Interoperable State Machine Protocol)

### Key components (from Hyperbridge EVM getting started)
- **`IIsmpHost`**
  - Central, stateful contract for protocol storage.
  - Stores consensus states, state commitments, request/response commitments and receipts.
  - Implements `IsmpDispatcher` methods so contracts can dispatch requests/responses.

- **`IHandler`**
  - Stateless entry point for ISMP datagrams.
  - Performs consensus and state proof verification.
  - On success, delegates storage + dispatching to `IIsmpModule`s via `IIsmpHost`.
  - Separation of Handler vs Host enables upgrading verification mechanisms independently.

- **`IConsensusClient`**
  - Library used by `IHandler` for Hyperbridge consensus verification on EVM.
  - Typically not used directly by application contracts.

- **`IDispatcher`**
  - Main interface application developers care about.
  - Used to dispatch cross-chain messages and state reads.
  - Supports dispatching POST requests, POST responses, and GET requests.

- **`IIsmpModule` / `BaseIsmpModule`**
  - Application-facing receiving interface.
  - Contracts implement/extend this to receive incoming messages.

- **`StateMachine`**
  - Convenience library for identifying the destination/source state machines.
  - Hyperbridge supports multiple state machine families (EVM, Polkadot-SDK, Cosmos SDK, etc.).

### Implementations (links from docs)
- `IIsmpHost`: https://github.com/polytope-labs/hyperbridge/blob/main/evm/src/hosts/EvmHost.sol
- `IHandler`: https://github.com/polytope-labs/hyperbridge/blob/main/evm/src/modules/HandlerV1.sol
- `IConsensusClient`: https://github.com/polytope-labs/hyperbridge/blob/main/evm/src/consensus/SP1Beefy.sol

### Versioning note
- The Hyperbridge doc states the minimum `ismp-solidity` version is **v0.8.17**.

---

## Mapping to Paix “cross-chain” requirements (draft)
This section is a practical mapping (not authoritative) to help structure an OpenSpec proposal:
- **XCM** is a fit for *Polkadot ecosystem* messaging/asset movement where both sides understand XCM.
- **Hyperbridge (ISMP)** is a fit for *cross-ecosystem / heterogeneous chains* messaging/state reads via the Host/Handler/Dispatcher/Module model.
- **Snowbridge** is a fit for *Polkadot <-> Ethereum* bridging, but details are not covered by the two sources above.

Potential Paix integration points (to be scoped in proposal):
- Define a **cross-chain intent** in the agent/backend (e.g., “bridge asset to execution venue”).
- On-chain contracts on Polkadot Hub (EVM) may:
  - dispatch ISMP requests via `IDispatcher` (Hyperbridge path), and/or
  - participate in XCM flows (XCM path), depending on final architecture.

## Open questions to resolve in proposal
- Which cross-chain flows are in scope for MVP:
  - Polkadot Hub <-> other parachains (XCM)?
  - Polkadot Hub <-> Ethereum (Snowbridge)?
  - Polkadot Hub <-> external execution venue/chain via Hyperbridge (ISMP)?
- Asset scope for cross-chain MVP:
  - Native PAS/DOT-like assets, ERC-20 on Hub, bridged assets?
- Failure modes and UX:
  - What states are user-visible (pending/verified/settled/refund)?
  - Timeouts and recovery paths?
