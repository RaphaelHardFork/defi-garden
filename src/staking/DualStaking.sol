// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "openzeppelin-contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/access/Ownable.sol";
import "./IDualStaking.sol";

/**
 * @notice  This contract allow to distribute ERC20 reward block per block
 *          to users having a staked amount of another ERC20 token.
 *
 * @dev Implementation of {IDualStaking} interface.
 *
 * This implementation is used for two distinct ERC20 (rewards and staked token),
 * if only one token is used.
 *
 * {Ownable} contract is used to restrict the {deposit}, {unstakeFor} and {closeContract} action to the `owner`,
 * this ownership can be renouced to allow users to add rewards. {deposit} can be unrestricted as rewards per block
 * and per token staked cannot be lowered.
 *
 * As rewards are distributed each block, rewards are represented by {_currentRewardPerBlockPerToken},
 * which calculate amount of rewards to distribute to each token staked in the contract.
 *
 * Note This contract is not audited, use it with caution.
 */

contract DualStaking is IDualStaking, Ownable {
    uint256 public immutable BLOCK_PER_DAY;
    uint128 public immutable MIN_REWARDS_DEPOSIT;
    uint128 public immutable MAX_REWARDS_DEPOSIT;
    uint256 public constant PRECISION = 10e40;

    address public immutable override rewardToken;
    address public immutable stakedToken;

    /// @dev represents rewards distributed per token staked
    uint256 private _rewardPerTokenDistributed;

    /// @dev amount of rewards distributed each block (stored with +40 decimal)
    uint256 private _currentRewardPerBlockPerToken;

    /// @dev total amount of token staked in the contract
    uint256 private _totalStaked;

    /// @dev used to store rewards amount when no token are staked
    uint256 private _depositPool;

    /// @dev amount of token staked by an user
    mapping(address => uint256) private _stakedAmount;

    /// @dev amount of reward per token the user cannot benefit
    mapping(address => uint256) private _rewardPerTokenPaid;
    Timeline private _timeline;

    /**
     * @dev Tokens address are `immutable`, consider using another contract
     * to change reward or staked token.
     *
     * @param _rewardToken   token distributed as rewards
     * @param _stakedToken  token staked by users
     */
    constructor(address _stakedToken, address _rewardToken) {
        rewardToken = _rewardToken;
        stakedToken = _stakedToken;
        MIN_REWARDS_DEPOSIT = 5e16; // 0.05 token
        MAX_REWARDS_DEPOSIT = 1000e27; // 1000 billons tokens
        BLOCK_PER_DAY = 43000; // overestimation of Polygon network
    }

    modifier triggerDistribution() {
        _distribute();
        _;
    }

    modifier triggerRewards(address account) {
        _getReward(account);
        _;
    }

    function deposit(uint256 amount, uint256 lastBlock)
        external
        override
        onlyOwner
        triggerDistribution
    {
        if (amount < MIN_REWARDS_DEPOSIT) revert BelowMinimalRewardsDeposit();
        if (
            lastBlock < block.number ||
            lastBlock <= _timeline.lastBlockWithReward
        ) revert ShorterDistribution();
        if (lastBlock > (BLOCK_PER_DAY * 365) * 100)
            revert DistributionOver100Years();

        // transfer token
        IERC20(rewardToken).transferFrom(msg.sender, address(this), amount);

        // the amount is stored in {_depositPool} until the contract
        // have tokens staked.
        if (_totalStaked == 0) {
            if (_depositPool > 0) {
                lastBlock += block.number - _timeline.depositBlock;
            }
            _depositPool += amount;
            _validateRBT(
                _depositPool,
                1_000_000 * 10**18,
                lastBlock - block.number
            );

            _timeline.depositBlock = uint64(block.number);
            _timeline.lastBlockWithReward = uint64(lastBlock);
            emit Deposit(msg.sender, 0, amount, _depositPool);
            return;
        }

        // active distribution if not started
        if (_currentRewardPerBlockPerToken == 0) {
            if (_depositPool > 0) {
                lastBlock += block.number - _timeline.depositBlock;
                amount += _depositPool;
                delete _depositPool;
            }
        }

        // add to current distribution and set it
        // this check is not performed when RBT = 0
        uint256 currentRBT = _currentRewardPerBlockPerToken;
        uint256 updatedRBT = _updateRBT(amount, lastBlock, 0);
        require(updatedRBT >= currentRBT, "Staking: lower rewards");

        emit Deposit(msg.sender, updatedRBT, amount, _depositPool);
    }

    function stake(uint256 amount) external override {
        stakeFor(msg.sender, amount);
    }

    function stakeFor(address account, uint256 amount)
        public
        override
        triggerDistribution
        triggerRewards(account)
    {
        if (amount == 0) revert ZeroAmount();
        uint256 rewardAmount;
        uint256 lastBlock = _timeline.lastBlockWithReward;

        // update RBT only if active distribution
        // before update the stake amount
        if (_currentRewardPerBlockPerToken > 0) {
            _updateRBT(rewardAmount, lastBlock, int256(amount));
        } else if (_depositPool > 0) {
            // active distribution
            lastBlock += uint64(block.number) - _timeline.depositBlock;
            rewardAmount = _depositPool;
            delete _depositPool;
            _updateRBT(rewardAmount, lastBlock, int256(amount));
        }

        // update stake state
        _stakedAmount[account] += amount;
        _totalStaked += amount;
        _rewardPerTokenPaid[account] = _rewardPerTokenDistributed;
        IERC20(stakedToken).transferFrom(account, address(this), amount);
        emit Staked(
            account,
            _currentRewardPerBlockPerToken,
            amount,
            _totalStaked
        );
    }

    function unstake(uint256 amount) external override {
        unstakeFor(msg.sender, amount);
    }

    function unstakeFor(address account, uint256 amount)
        public
        override
        triggerDistribution
        triggerRewards(account)
    {
        if (msg.sender != account && msg.sender != owner())
            revert NoAccess(msg.sender);
        if (_totalStaked < amount || _stakedAmount[account] < amount)
            revert InsufficientStakedAmount();

        uint256 lastBlockWithReward = _timeline.lastBlockWithReward;
        // stop distribution if no more token in contract
        if (_totalStaked - amount == 0) {
            uint256 remainingBlocks = lastBlockWithReward > block.number
                ? uint256(lastBlockWithReward) - block.number
                : 0;
            uint256 remainingAmount = (_currentRewardPerBlockPerToken *
                remainingBlocks *
                _totalStaked) / PRECISION;
            delete _currentRewardPerBlockPerToken;
            if (remainingAmount > 0) {
                _depositPool = remainingAmount;
                _timeline.depositBlock = uint64(block.number);
            }
        } else {
            // update RBT only if dstribution active
            if (_currentRewardPerBlockPerToken > 0) {
                _updateRBT(0, lastBlockWithReward, int256(amount) * -1);
            }
        }

        // update stake state
        _stakedAmount[account] -= amount;
        _totalStaked -= amount;
        IERC20(stakedToken).transfer(account, amount);
        emit Unstaked(
            account,
            _currentRewardPerBlockPerToken,
            amount,
            _totalStaked
        );
    }

    function getReward(address account) external override triggerDistribution {
        _getReward(account);
    }

    function closeContract() external override onlyOwner {
        require(_totalStaked == 0, "Staking: unstake tokens before");
        require(
            _timeline.lastBlockWithReward < block.number,
            "Staking: distribution active"
        );

        IERC20 rewards = IERC20(rewardToken);

        rewards.transfer(msg.sender, rewards.balanceOf(address(this)));
        selfdestruct(payable(msg.sender));
    }

    function totalStakedFor(address account)
        external
        view
        override
        returns (uint256)
    {
        return _stakedAmount[account];
    }

    function totalStaked() external view override returns (uint256) {
        return _totalStaked;
    }

    function currentReward() external view override returns (uint256) {
        return _currentRewardPerBlockPerToken;
    }

    function depositPool() external view override returns (uint256) {
        return _depositPool;
    }

    function timeline() external view override returns (Timeline memory) {
        return _timeline;
    }

    /**
     * @dev Update the last distribution block to the lastest block
     *      Add reward per token to distributed token per token
     *
     *      Should detect the end of distribution
     * */
    function _distribute() internal {
        uint256 currentBlock = block.number;
        uint256 lastBlockWithReward = _timeline.lastBlockWithReward;
        uint256 lastDistributionBlock = _timeline.lastDistributionBlock;

        // calculate reward until {lastBlockWithReward} maximum
        if (block.number > lastBlockWithReward && lastBlockWithReward != 0) {
            currentBlock = lastBlockWithReward;
        }

        // calculate only if the {lastBlockWithReward} is not reached
        if (
            currentBlock >= lastDistributionBlock &&
            _currentRewardPerBlockPerToken > 0
        ) {
            uint256 elapsedBlocks = currentBlock - lastDistributionBlock;
            _rewardPerTokenDistributed +=
                elapsedBlocks *
                _currentRewardPerBlockPerToken;

            // end of distribution
            if (lastBlockWithReward == currentBlock) {
                delete _currentRewardPerBlockPerToken;
            }
        }

        // update distribution block anyway
        _timeline.lastDistributionBlock = uint64(block.number);
    }

    /**
     * @dev {triggerDistribution} should be called before
     */
    function _getReward(address account) internal {
        uint256 rewards = ((_rewardPerTokenDistributed -
            _rewardPerTokenPaid[account]) * _stakedAmount[account]) / PRECISION;

        _rewardPerTokenPaid[account] = _rewardPerTokenDistributed;

        if (rewards > 0) {
            emit RewardPaid(account, rewards);
            IERC20(rewardToken).transfer(account, rewards);
        }
    }

    function _validateRBT(
        uint256 amount,
        uint256 staked,
        uint256 duration
    ) internal view returns (uint256 estimatedRBT) {
        if (amount > MAX_REWARDS_DEPOSIT) revert OverMaximalRewardsDeposit();
        estimatedRBT = (amount * PRECISION) / (staked * duration);
        if (estimatedRBT == 0) revert LowerDistributionToZero();
    }

    /**
     * @dev Calculate the remaining amount to distribute (zero if distribution not started
     *      and if distribution is finished).
     *      Validate RBT and compare it to the previous (only for deposit)
     */

    function _updateRBT(
        uint256 amount,
        uint256 lastBlock,
        int256 totalStakedDelta
    ) internal returns (uint256 updatedRBT) {
        uint256 remainingBlocks = _timeline.lastBlockWithReward > block.number
            ? uint256(_timeline.lastBlockWithReward) - block.number
            : 0;
        amount +=
            (_currentRewardPerBlockPerToken * _totalStaked * remainingBlocks) /
            PRECISION;

        updatedRBT = _validateRBT(
            amount,
            uint256(int256(_totalStaked) + totalStakedDelta),
            block.number > lastBlock ? 0 : lastBlock - block.number
        );
        _currentRewardPerBlockPerToken = updatedRBT;
        _timeline.lastBlockWithReward = uint64(lastBlock);
    }
}
