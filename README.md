# PredictFWA (PFWA)

PredictFWA is a fixed-supply ERC-20. Its constructor mints the entire supply once
to the immediate deployer, using OpenZeppelin Contracts v5.2.0. Transfers deliver
the exact amount requested.

| Deployment parameter | Value |
| --- | --- |
| Source / Solidity contract | `src/PredictFWA.sol:PredictFWA` |
| Token name | `PredictFWA` |
| Token symbol | `PFWA` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in smallest units | `1000000000000000000000000000` (`10**27`) |
| Named supply constant | `INITIAL_SUPPLY` |
| Constructor arguments | None (`[]`) |
| Deployment ETH value | `0` |
| Initial recipient | Constructor `msg.sender` |
| Launch chain | Ethereum, chain ID `1` |
| Compiler | Solidity `0.8.26` |
| EVM target | Cancun |
| Optimizer | Enabled, `200` runs |
| Bytecode metadata hash | `none` |
| Linked libraries / application contracts | None |

## Build and check

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0xfc8bb7114dd6a3076d2bf62487dce9f8146294f9d260a9708062b06e8c98fcaf forge test
forge fmt --check
```

All Solidity dependencies are ordinary files under `lib/`; no package install,
submodule, RPC connection, wallet, or environment-based configuration is needed.
With the pinned compiler installed, `forge build --offline` and `forge test
--offline` also work. Dependency versions, immutable source commits, archive
checksums, and license locations are recorded in [lib/DEPENDENCIES.md](lib/DEPENDENCIES.md).

The tests cover metadata and the constructor's single mint event; exact transfers;
zero amounts and self-transfers; approvals, revocation, finite and unlimited
allowances; unauthorized spending; invalid addresses; insufficient balances;
rollback of allowance changes on failure; and rejection of mint, burn, pause,
seizure, and upgrade entry points. Fuzz tests run 1,024 cases each. Stateful tests
run 128 sequences of 64 calls and compare balances and allowances against an
independent ledger, including rejected operations.

The local launch fixture checks CREATE2 deployment to the factory's balance,
10%/80%/10% allocation transfers, contributor claims, and token movements in both
trading directions. It models the token side of those flows; it does not implement
or test an actual Uniswap pool. The supplied protected suite requires the external
launch harness, manifest inputs, and pool contracts, and is left to the independent
verifier.

## Behavior and assumptions

- Only the constructor mints. There is no public mint or burn, owner, administrator,
  pausing, blocklist, confiscation, proxy, upgrade, transfer tax, rebasing, or
  transfer limit. The deployer receives tokens but no special permissions.
- Standard ERC-20 `transfer`, `approve`, and `transferFrom` return `true` on
  success and revert with OpenZeppelin ERC-6093 errors on invalid operations.
  Transfers and explicit approvals emit the standard events.
- Zero-value transfers between valid addresses are allowed. Transfers to the
  zero address and approvals to a zero spender revert. Self-transfers preserve
  balances; a delegated self-transfer still spends the approved allowance.
- `approve` replaces the previous allowance. Finite allowances decrease when
  spent; `type(uint256).max` is treated as unlimited. OpenZeppelin v5 does not
  emit an additional `Approval` event when `transferFrom` spends an allowance;
  integrations should read `allowance` for its current value.
- `transferFrom` always uses the caller's allowance, even when the caller is the
  token holder. `transfer` is the direct holder operation. A zero-amount
  `transferFrom` between valid addresses needs no allowance and moves nothing.
- The constructor and transfers make no external calls. Recipients do not need
  an ERC-20 receiver callback. There are no oracles, signatures, external
  services, or post-deployment configuration values.

## Deployment and operational responsibilities

Deploy the creation bytecode for `PredictFWA` directly, with no arguments and no
ETH. Do not deploy it behind a proxy. If a contract or factory creates the token,
that contract receives all `10**27` units; the transaction origin receives none.
For the IdentityMD launch, the factory is the intended recipient and performs
distribution. The constructor does not reserve or send any allocation itself.

The network's separate manifest/deployment step records this token, its empty
constructor argument list, exact supply, and the launch economics. This project
does not supply a `launch.json`. The factory is responsible for allocating 10%
to its distributor, 80% to the pool, and the remaining 10% according to the
requester's launch instructions; these allocations are not enforced by PFWA.
Pool creation, pricing, liquidity, contributor claims, transaction submission,
and explorer verification belong to the launch system, not to this token.

After launch there are no setters or administrator tasks. The deployer should
verify the deployed metadata, total supply, constructor `Transfer` event, and
distribution receipts against the approved artifacts. Holders control transfers
and approvals. Integrations should request only needed allowances, allow
revocation, and account for the standard approval replacement race (revoke and
confirm before granting a replacement allowance when appropriate).

There is no recovery function. Tokens sent to this token contract, to a contract
unable to transfer them, or to an inaccessible wallet may be permanently locked.
Ordinary ETH payments revert; forcibly received ETH and accidentally sent other
assets cannot be recovered through PFWA. No administrator can fix a lost key or
reverse a transfer.

The implementation was reviewed against the supplied security reference and
checked with Foundry unit, fuzz, and stateful invariant tests. Slither and Mythril
were not run. These checks do not replace the network's independent adversarial
review before release. No transactions were broadcast by this assignment.
