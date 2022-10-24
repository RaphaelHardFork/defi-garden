// SPDX-License-Identifier: NONE
pragma solidity ^0.8.13;

/**
 * @notice  This contract allow to distribute ERC20 reward block per block
 *          to users having a staked amount of another ERC20 token.
 *
 *
 * @dev This implementation is used for two distinct ERC20 (rewards and staked token),
 * if only one token is used, consider using an anti-compound number of block to avoid,
 * compound on each block.
 *
 * {Ownable} contract is used to restrict the {deposit} action to the `owner`, this ownership
 * can be renouced to allow users to add rewards. Anyway the amount of reward per block and per token staked,
 * cannot be lowered.
 *
 * As rewards are distributed each block, rewards are represented by {_currentRewardPerBlockPerToken},
 * which calculate amount of rewards to distribute to each token staked in the contract.
 *
 * NOTE This contract is not audited, use it with caution.
 */

interface IDualStaking {
    // --- Structs ---
    /**
     * @dev information related to blocks
     *    - {depositBlock} last block where an amount was deposited in {_depositPool}
     *    - {lastBlockWithReward} last block where distribution will occurs
     *    - {lastDistributionBlock} last block where rewards were added to {_rewardPerTokenDistributed}
     */
    struct Timeline {
        uint64 depositBlock;
        uint64 lastDistributionBlock;
        uint64 lastBlockWithReward;
    }

    // --- Events ---

    /**
     * @notice  {Deposit}, {Staked} and {Unstaked} events have `distribution` as
     *          `indexed` parameter to filter the case where the distribution is
     *          not started or is paused, represented by {distribution == 0}.
     */
    event Deposit(
        address indexed account,
        uint256 indexed distribtion,
        uint256 amount,
        uint256 depositPool
    );

    event Staked(
        address indexed account,
        uint256 indexed distribtion,
        uint256 amount,
        uint256 total
    );

    event Unstaked(
        address indexed account,
        uint256 indexed distribtion,
        uint256 amount,
        uint256 total
    );

    event RewardPaid(address indexed account, uint256 amount);

    // -- Errors ---

    error NoAccess(address sender);
    error ZeroAmount();
    error InsufficientStakedAmount();
    error ShorterDistribution();
    error LowerDistributionToZero();
    error BelowMinimalRewardsDeposit();
    error OverMaximalRewardsDeposit();
    error DistributionOver100Years();

    // --- States to implement ---

    /**
     * @dev token staked in the contract to get rewards
     */
    function stakedToken() external view returns (address);

    /**
     * @dev token distributed as rewards
     */
    function rewardToken() external view returns (address);

    // --- Functions ---

    /**
     * @dev Deposit `amount` of {rewardToken} into the contract for the distribution,
     *      This function is restricted to the `owner`.
     *
     *      The distribution start only if the amount staked in the contract is non-null,
     *      in this case the amount is stored in {_depositPool}. The distribution will start
     *      once an user stake an amount into the contract.
     *
     *      Consider deposit at least 10**12 token (with 18 decimal) in order to limit amount
     *      of token stuck in the contract.
     *
     * Requirement:
     *      - `lastBlock` should be greater than actual block and the previous lastBlock
     *      - combinaison of `amount` & `lastBlock` should result a distribution over zero,
     *      and increase the actual distribution if the distribution is active.
     *
     * @param amount    amount of token to deposit into the contract
     * @param lastBlock last block where distribution will occurs
     * */
    function deposit(uint256 amount, uint256 lastBlock) external;

    /**
     * @dev Stake an amount in the contract for the `sender`
     *
     * @param amount  amount of token to stake
     */
    function stake(uint256 amount) external;

    /**
     * @dev Stake an amount in the contract for another address
     *
     * @param account      address which will stake tokens
     * @param amount    amount of token to stake
     */
    function stakeFor(address account, uint256 amount) external;

    /**
     * @dev Unstake an amount in the contract for the `sender`
     *
     * @param amount amount of token to unstake
     */
    function unstake(uint256 amount) external;

    /**
     * @dev Unstake an amount in the contract for another address
     *
     * @param account   address which will unstake tokens
     * @param amount    amount of token to unstake
     */
    function unstakeFor(address account, uint256 amount) external;

    function getReward(address account) external;

    function closeContract() external;

    // --- Getter functions ---

    /**
     * @param account  address to view balance of staked token
     * @return amount of token staked by an user
     */
    function totalStakedFor(address account) external view returns (uint256);

    /**
     * @return total amount of token staked in the contract
     */
    function totalStaked() external view returns (uint256);

    /**
     * @return amount of reward distributed per block per token
     */
    function currentReward() external view returns (uint256);

    /**
     * @return amount of rewards waiting for distribution
     */
    function depositPool() external view returns (uint256);

    /**
     * @return information related to blocks see {TimeLine} struct
     */
    function timeline() external view returns (Timeline memory);
}
