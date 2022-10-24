# Staking contract

This contrat do not implement the `IERC900` interface, because this latter seem to be not so used.

Distribution use `RewardPerTokenStored` from ...

**This contract is not audited**, feel free to open issues, comments, ...

## SK-01
- clean code
- dual staking
- new interface
- burn contract

## Calculate APR
```
// actual
APR = (staking.currentReward() * blocksPerYear * tokenStaked) / 10**40

// after stake/ unstake
BlockTillEnd = staking.timeline().lastBlockWithReward - block.number
RemainingAmount = staking.currentReward() * BlockTillEnd * staking.totalStaked()

// newAmount can be negative
NewDistribution = (RemainingAmount + newAmount * 10**40) / BlockTillEnd * staking.totalStaked()

APR = (NewDistribution * blocksPerYear * tokenStaked) / 10**40
```


## Dual Staking

As the reward token is different from the staked token, no compounding is possible, therefore `APR == APY`.

## Single Staking

Compounding need to be managed! Is automatically compounding for users? To avoid gas interaction!

---

This contract allow to distribute token block per block. This contract is not gas-optimised.

This contract implement the `IERC900` staking interface, is this is relevant?


## Test coverage

~60%
```
forge test --match-contract StakingVaultERC20
```

## TODO 
- burn contract at the end
- withdraw dust

Then single token staking
Then clone to save gas