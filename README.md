## SnowAI Core

Smart contracts, tests, and tooling for the SnowAI token ecosystem. The repository is built with Foundry.

## Contracts

### `SnowAI.sol`
- ERC20 token named SnowAI (`SAI`) with burn capability.
- Constructor mints the full `initialSupply` to a provided treasury address, which must be non-zero.
- Inherits `ERC20Burnable` and `Ownable` from OpenZeppelin; ownership defaults to the deployer.

### `TokenVesting.sol`
- Manages linear vesting schedules with optional cliffs and revocability.
- Key parameters per schedule: `beneficiary`, `start`, `duration`, `cliffDuration`, `revocable`, and `totalAmount`.
- Until `block.timestamp < start + cliffDuration`, nothing is releasable.
- When the cliff expires, the beneficiary can immediately claim the tokens that accrued since `start`; the remaining allocation continues vesting linearly until `start + duration`.
- Owners may revoke revocable schedules, returning unvested tokens to themselves while forwarding vested-but-unreleased amounts to the beneficiary.

### `Staking.sol`
- Upgradeable staking contract (UUPS) that accepts a staking ERC20 and pays rewards in another ERC20.
- Tracks balances, rewards per token, and supports `stake`, `withdraw`, `exit`, and `getReward` flows.
- Owner can update the reward rate, force reward accounting for specific accounts, and recover unrelated ERC20s.
- Requires `initialize(stakingToken, rewardsToken, rewardRate)` to be called exactly once after deployment behind a proxy.

## Repository Layout

- `src/`: Solidity sources.
- `test/`: Forge-based tests covering token minting and burning, vesting cliff and revocation behavior, and staking reward distribution.
- `script/`: Placeholder for deployment or maintenance scripts.

## Prerequisites

- Install Foundry by following https://book.getfoundry.sh/getting-started/installation.

## Commands

```shell
forge build        # Compile contracts
forge test         # Run the Forge test suite
forge fmt          # Format Solidity sources
forge snapshot     # Generate gas reports
anvil              # Launch a local Ethereum test node
cast <subcommand>  # Interact with contracts or chains
```

## Deployment

### Environment Variables

Deployment scripts expect the following variables to be exported or provided through a `.env` file:

- `DEPLOYER_PRIVATE_KEY`: hex-encoded key of the broadcasting account (without `0x`).
- `SNOWAI_TREASURY` and `SNOWAI_INITIAL_SUPPLY`: required by `DeploySnowAI`.
- `VESTING_TOKEN`: ERC20 address supplied to `DeployTokenVesting`.
- `STAKING_TOKEN`, `STAKING_REWARDS_TOKEN`, `STAKING_REWARD_RATE`: inputs for `DeployStaking`.

### Script Commands

```shell
# Deploy the SnowAI ERC20 token
forge script script/DeploySnowAI.s.sol:DeploySnowAI \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify --verifier etherscan

# Deploy the TokenVesting contract
forge script script/DeployTokenVesting.s.sol:DeployTokenVesting \
  --rpc-url $RPC_URL \
  --broadcast

# Deploy the Staking proxy (initializes via constructor calldata)
forge script script/DeployStaking.s.sol:DeployStaking \
  --rpc-url $RPC_URL \
  --broadcast
```

Adjust `--verify` flags, verifiers, and RPC endpoints to match the target network. For dry runs, omit `--broadcast`. All scripts return the deployed contract address in the Forge output.
