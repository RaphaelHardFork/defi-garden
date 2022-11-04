// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./base/BaseTest.sol";
import "src/staking/DualStaking.sol";
import "src/staking/IDualStaking.sol";

contract DualStaking_test is BaseTest {
    DualStaking public staking;
    address public STAKING;

    uint256 public TOKEN;
    uint256 public REWARDS;
    address public TOKEN_ADDR;
    address public REWARDS_ADDR;

    function setUp() public {
        vm.roll(1000);
        (TOKEN_ADDR, TOKEN) = _deployToken();
        (REWARDS_ADDR, REWARDS) = _deployToken();

        vm.prank(OWNER);
        staking = new DualStaking(TOKEN_ADDR, REWARDS_ADDR);
        STAKING = address(staking);

        _newUsersSet(0, 7);
        _mintTokenForAll(1000e18, TOKEN);
    }

    /*/////////////////////////////////////
                     Utils 
    /////////////////////////////////////*/
    function _prepareStake(address user, uint256 amount) internal {
        vm.assume(amount > 0 && amount <= 1000e18);
        vm.prank(user);
        tokens[TOKEN].approve(STAKING, amount);
        vm.prank(user);
        // call stake after
    }

    function _userStake(address user, uint256 amount) internal {
        _prepareStake(user, amount);
        staking.stake(amount);
    }

    function _prepareDeposit(uint256 amount, uint64 lastBlock) internal {
        vm.assume(
            amount > 5e16 &&
                amount < 1000e27 &&
                lastBlock > 2000 &&
                // 100 years
                lastBlock < staking.BLOCK_PER_DAY() * 365 * 99
        );
        tokens[REWARDS].mint(OWNER, amount);
        vm.prank(OWNER);
        tokens[REWARDS].approve(STAKING, amount);
        vm.prank(OWNER);
        // call deposit after
    }

    function _deposit(uint256 amount, uint64 lastBlock) internal {
        _prepareDeposit(amount, lastBlock);
        staking.deposit(amount, lastBlock);
    }

    function _userUnstake(address user, uint256 amount) internal {
        vm.prank(user);
        staking.unstake(amount);
    }

    function _setDistribution(
        uint256 amount,
        uint64 lastBlock,
        uint256 stakedAmount
    ) internal {
        _deposit(amount, lastBlock);
        _userStake(USERS[0], stakedAmount);
    }

    function _calculRBT(
        uint256 rewardAmount,
        uint256 blockRange,
        uint256 totalStaked
    ) internal pure returns (uint256) {
        return (rewardAmount * 10e40) / (blockRange * totalStaked);
    }

    /*/////////////////////////////////////
        stakeFor::distribution not active 
    /////////////////////////////////////*/
    event Staked(
        address indexed account,
        uint256 indexed distribtion,
        uint256 amount,
        uint256 total
    );

    function testStake(uint256 amount) public {
        _userStake(USERS[0], amount);

        assertEq(tokens[TOKEN].balanceOf(STAKING), amount);
        assertEq(staking.totalStakedFor(USERS[0]), amount);
        assertEq(staking.totalStaked(), amount);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastBlockWithReward, 0);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
    }

    function testEmitOnStakeFor(uint256 amount) public {
        _prepareStake(USERS[0], amount);
        vm.expectEmit(true, true, false, true, STAKING);
        emit Staked(USERS[0], 0, amount, amount);
        staking.stake(amount);
    }

    function testCannotStake() public {
        _prepareStake(USERS[0], 50e18);
        vm.expectRevert(IDualStaking.ZeroAmount.selector);
        staking.stake(0);
    }

    function testMultipleStake(uint256 nbOfUser, uint256 amount) public {
        vm.assume(nbOfUser > 1 && nbOfUser < USERS.length);
        uint256 userAmount;
        uint256 totalStaked;

        for (uint256 i; i < nbOfUser; i++) {
            unchecked {
                userAmount = (userAmount + amount) % 1000e18;
            }
            if (userAmount == 0) userAmount = 10e18;
            _userStake(USERS[i], userAmount);
            totalStaked += userAmount;
        }

        for (uint256 i; i < nbOfUser; i++) {
            assertTrue(staking.totalStakedFor(USERS[i]) > 0);
        }
        assertEq(tokens[TOKEN].balanceOf(STAKING), totalStaked);
        assertEq(staking.totalStaked(), totalStaked);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastBlockWithReward, 0);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), 0);
    }

    /*/////////////////////////////////////
            deposit::no staking 
    /////////////////////////////////////*/
    event Deposit(
        address indexed account,
        uint256 indexed distribtion,
        uint256 amount,
        uint256 depositPool
    );

    function testDeposit(uint256 amount, uint64 lastBlock) public {
        _deposit(amount, lastBlock);

        assertEq(tokens[REWARDS].balanceOf(STAKING), amount);
        assertEq(staking.timeline().lastBlockWithReward, lastBlock);
        assertEq(staking.timeline().depositBlock, 1000);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), amount);
    }

    function testEmitOnDeposit(uint256 amount, uint64 lastBlock) public {
        _prepareDeposit(amount, lastBlock);
        vm.expectEmit(true, true, false, true, STAKING);
        emit Deposit(OWNER, 0, amount, amount);
        staking.deposit(amount, lastBlock);
    }

    function testCannotDeposit() public {
        tokens[REWARDS].mint(OWNER, 1000e28);
        vm.startPrank(OWNER);
        tokens[REWARDS].approve(STAKING, 1000e28);
        vm.expectRevert(IDualStaking.BelowMinimalRewardsDeposit.selector);
        staking.deposit(4e16, 10000);

        vm.expectRevert(IDualStaking.ShorterDistribution.selector);
        staking.deposit(100e18, 500);

        // ShorterDistribution over active distribution

        vm.expectRevert(IDualStaking.DistributionOver100Years.selector);
        staking.deposit(100e18, type(uint64).max);

        vm.expectRevert(IDualStaking.OverMaximalRewardsDeposit.selector);
        staking.deposit(1005e27, 10000);

        staking.deposit(999e27, 10000);
        vm.expectRevert(IDualStaking.OverMaximalRewardsDeposit.selector);
        staking.deposit(2e27, 20000);
    }

    /*/////////////////////////////////////
            unstake::without rewards 
    /////////////////////////////////////*/
    event Unstaked(
        address indexed account,
        uint256 indexed distribtion,
        uint256 amount,
        uint256 total
    );

    function testUnstake(uint256 amount) public {
        _userStake(USERS[0], amount);
        vm.roll(10000);
        _userUnstake(USERS[0], amount);

        assertEq(tokens[TOKEN].balanceOf(STAKING), 0);
        assertEq(tokens[TOKEN].balanceOf(USERS[0]), 1000e18);

        assertEq(staking.totalStakedFor(USERS[0]), 0);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastBlockWithReward, 0);
        assertEq(staking.timeline().lastDistributionBlock, 10000);
    }

    function testEmitOnUnstake(uint256 amount) public {
        _userStake(USERS[0], amount);
        vm.roll(10000);
        vm.expectEmit(true, true, false, true, STAKING);
        emit Unstaked(USERS[0], 0, amount, 0);
        vm.prank(USERS[0]);
        staking.unstake(amount);
    }

    function testCannotUnstake(uint256 amount) public {
        _userStake(USERS[0], amount);
        vm.roll(10000);

        vm.prank(USERS[1]);
        vm.expectRevert(
            abi.encodeWithSelector(IDualStaking.NoAccess.selector, USERS[1])
        );
        staking.unstakeFor(USERS[0], amount);

        _userUnstake(USERS[0], amount);

        vm.expectRevert(IDualStaking.InsufficientStakedAmount.selector);
        _userUnstake(USERS[0], amount);
    }

    /*/////////////////////////////////////
        stakeFor::to active distribution 
    /////////////////////////////////////*/
    function testStakeToActive(
        uint256 amount,
        uint64 lastBlock,
        uint256 stakedAmount
    ) public {
        _deposit(amount, lastBlock);
        assertEq(staking.timeline().depositBlock, 1000);
        assertEq(staking.timeline().lastBlockWithReward, lastBlock);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), amount);
        vm.roll(10000);

        _userStake(USERS[0], stakedAmount);
        assertEq(staking.timeline().depositBlock, 1000);
        assertEq(staking.timeline().lastBlockWithReward, lastBlock + 9000);
        assertEq(staking.timeline().lastDistributionBlock, 10000);
        assertTrue(staking.currentReward() > 0);
        assertEq(staking.depositPool(), 0);
    }

    function testEmitOnStakeToActive(
        uint256 amount,
        uint64 lastBlock,
        uint256 stakedAmount
    ) public {
        _deposit(amount, lastBlock);
        vm.roll(10000);
        _prepareStake(USERS[0], stakedAmount);
        vm.expectEmit(true, true, false, true, STAKING);
        emit Staked(
            USERS[0],
            _calculRBT(amount, lastBlock - 1000, stakedAmount),
            stakedAmount,
            stakedAmount
        );
        staking.stake(stakedAmount);
    }

    /*/////////////////////////////////////
        deposit::to active distribution 
    /////////////////////////////////////*/
    function testDepositToActive(uint256 depositedAmount, uint64 lastBlock)
        public
    {
        vm.assume(lastBlock > 10000);
        _userStake(USERS[0], 50e18);
        vm.roll(10000);

        // deposit
        _deposit(depositedAmount, lastBlock);

        assertEq(staking.timeline().depositBlock, 0); // no deposit block
        assertEq(staking.timeline().lastBlockWithReward, lastBlock);
        assertEq(staking.timeline().lastDistributionBlock, 10000);
        assertTrue(staking.currentReward() > 0);
        assertEq(staking.depositPool(), 0);
    }

    function testEmitOnDepositToActive(
        uint256 depositedAmount,
        uint64 lastBlock
    ) public {
        vm.assume(lastBlock > 10000);
        _userStake(USERS[0], 50e18);
        vm.roll(10000);

        _prepareDeposit(depositedAmount, lastBlock);
        vm.expectEmit(true, true, false, true, STAKING);
        emit Deposit(
            OWNER,
            _calculRBT(depositedAmount, lastBlock - 10000, 50e18),
            depositedAmount,
            0
        );
        staking.deposit(depositedAmount, lastBlock);
    }

    /*/////////////////////////////////////
        deposit::when distribution active
    /////////////////////////////////////*/
    function testDepositWhenDistributionActive() public {
        _setDistribution(2000e18, 500_000, 50e18);
        uint256 remainingBlocks = 500_000 - block.number;
        uint256 currentRBT = _calculRBT(2000e18, remainingBlocks, 50e18);
        assertEq(staking.currentReward(), currentRBT, "current RBT");

        vm.roll(100_000);
        remainingBlocks = 500_000 - block.number;
        uint256 remain = (currentRBT * 50e18 * remainingBlocks) / 10e40;

        _deposit(50000e18, 900_000);

        assertEq(staking.timeline().lastDistributionBlock, 100_000);
        assertEq(staking.timeline().lastBlockWithReward, 900_000);

        assertEq(
            staking.currentReward(),
            _calculRBT(remain + 50000e18, 800_000, 50e18)
        );
    }

    function testCannotDepositWhenDistributionActive() public {
        _setDistribution(2000e18, 500_000, 999e18);
        vm.roll(499_000);
        uint64 maxLastBlock = uint64(staking.BLOCK_PER_DAY() * 365 * 98);
        _prepareDeposit(1e17, maxLastBlock);
        vm.expectRevert(IDualStaking.LowerDistribution.selector);
        staking.deposit(1e17, maxLastBlock);
    }

    /*/////////////////////////////////////
        stake::when distribution active
    /////////////////////////////////////*/
    function testStakeWhenDistributionActive() public {
        _setDistribution(2000e18, 500_000, 999e18);
        vm.roll(250_000);

        uint256 currentRBT = _calculRBT(2000e18, 499_000, 999e18);
        assertEq(staking.currentReward(), currentRBT);

        _userStake(USERS[1], 50e18);

        uint256 remain = (currentRBT * 999e18 * (500_000 - block.number)) /
            10e40;

        currentRBT = _calculRBT(remain, 500_000 - block.number, 999e18 + 50e18);
        assertEq(staking.currentReward(), currentRBT);

        assertEq(staking.timeline().lastDistributionBlock, 250_000);
    }

    function testCannotStakeWhenDistributionActive() public {
        _setDistribution(2000e18, 500_000, 999e18);
        vm.roll(499_000);

        // stake a lot
        _mintFor(USERS[1], 10e60, TOKEN);
        vm.startPrank(USERS[1]);
        tokens[TOKEN].approve(STAKING, 10e60);
        vm.expectRevert(IDualStaking.LowerDistributionToZero.selector);
        staking.stake(10e60);
    }

    /*/////////////////////////////////////
                 unstake()
    /////////////////////////////////////*/
    function testIncreaseRewardWhenUnstake() public {
        _userStake(USERS[0], 500e18);
        _userStake(USERS[1], 50e18);
        _userStake(USERS[2], 700e18);
        _userStake(USERS[3], 70e18);
        _userStake(USERS[4], 15e18);
        _deposit(50_000e18, uint64(staking.BLOCK_PER_DAY() * 365));

        vm.roll(1_000_000);
        uint256 currentRBT = staking.currentReward();

        for (uint256 i; i < 4; i++) {
            _userUnstake(USERS[i], staking.totalStakedFor(USERS[i]));
            assertGt(staking.currentReward(), currentRBT);
            currentRBT = staking.currentReward();
        }
    }

    function testUnstakeAllBeforeEnd() public {
        _userStake(USERS[0], 500e18);
        _userStake(USERS[1], 50e18);
        _userStake(USERS[2], 700e18);
        _userStake(USERS[3], 70e18);
        _userStake(USERS[4], 15e18);
        _deposit(50_000e18, uint64(staking.BLOCK_PER_DAY() * 365));

        vm.roll(1_000_000);

        uint256 remain = (staking.currentReward() *
            (staking.timeline().lastBlockWithReward - block.number) *
            staking.totalStaked()) / 10e40;

        for (uint256 i; i <= 4; i++) {
            _userUnstake(USERS[i], staking.totalStakedFor(USERS[i]));
        }

        assertEq(staking.currentReward(), 0);
        assertEq(staking.timeline().depositBlock, block.number);
        assertApproxEqAbs(staking.depositPool(), remain, 10);
    }

    function testResumeWhenStake() public {
        _userStake(USERS[0], 500e18);
        _userStake(USERS[1], 50e18);
        _userStake(USERS[2], 700e18);
        _userStake(USERS[3], 70e18);
        _userStake(USERS[4], 15e18);
        _deposit(50_000e18, uint64(staking.BLOCK_PER_DAY() * 365));

        vm.roll(1_000_000);
        for (uint256 i; i <= 4; i++) {
            _userUnstake(USERS[i], staking.totalStakedFor(USERS[i]));
        }

        assertEq(staking.timeline().depositBlock, block.number, "1. db");
        assertEq(
            staking.timeline().lastBlockWithReward,
            uint64(staking.BLOCK_PER_DAY() * 365),
            "1. lbwr"
        );
        assertEq(
            staking.timeline().lastDistributionBlock,
            block.number,
            "1. ldb"
        );

        vm.roll(1_250_000);

        _userStake(USERS[2], 50e18);
        assertEq(staking.timeline().depositBlock, 1_000_000, "2. db");
        assertEq(
            staking.timeline().lastBlockWithReward,
            uint64(staking.BLOCK_PER_DAY() * 365) + 250_000,
            "2. lbwr"
        );
        assertEq(
            staking.timeline().lastDistributionBlock,
            block.number,
            "2. ldb"
        );
    }

    /*/////////////////////////////////////
                rewards distribution
    /////////////////////////////////////*/

    /*/////////////////////////////////////
                APY/APR
    /////////////////////////////////////*/
}

//     // --- get rewards ---
//     function testGetReward(uint256 amount) public {
//         _deposit(amount, 30000);
//         _userStake(USER1, amount * 2);

//         vm.roll(30000);
//         vm.startPrank(USER1);
//         staking.getReward(USER1);

//         assertApproxEqAbs(rewards.balanceOf(USER1), amount, 100);
//         assertApproxEqAbs(rewards.balanceOf(address(staking)), 0, 100);
//     }

//     function testGetPartOfRewards(uint256 amount) public {
//         vm.assume(amount > 0);
//         uint256 deposit = 10000 * D18;
//         _deposit(deposit, 70000);
//         _userStake(USER1, amount);
//         _userStake(USER2, amount);

//         vm.roll(61000);
//         staking.getReward(USER1);
//         staking.getReward(USER2);

//         uint256 reward = _calculReward(staking.currentReward(), 60000, amount);

//         assertEq(rewards.balanceOf(USER1), reward);
//         assertEq(rewards.balanceOf(USER2), reward);
//         assertEq(rewards.balanceOf(address(staking)), deposit - 2 * reward);
//     }

//     function testComplexRepartition() public {
//         address USER3 = address(3);
//         address USER4 = address(4);
//         address USER5 = address(5);
//         uint256 amount = 20 * D18;
//         uint256 deposit = 10000 * D18;
//         vm.roll(0);
//         _deposit(deposit, 10000);
//         _userStake(USER1, amount);

//         vm.roll(5000);
//         _userStake(USER2, amount);
//         _userStake(USER3, amount);
//         _userStake(USER4, amount);
//         _userStake(USER5, amount);

//         vm.roll(10001);

//         staking.getReward(USER1);
//         assertApproxEqAbs(
//             rewards.balanceOf(USER1),
//             (deposit * 6000) / 10000,
//             10
//         );
//         staking.getReward(USER2);
//         assertApproxEqAbs(
//             rewards.balanceOf(USER2),
//             (deposit * 1000) / 10000,
//             10
//         );
//         staking.getReward(USER3);
//         assertApproxEqAbs(
//             rewards.balanceOf(USER3),
//             (deposit * 1000) / 10000,
//             10
//         );
//         staking.getReward(USER4);
//         assertApproxEqAbs(
//             rewards.balanceOf(USER4),
//             (deposit * 1000) / 10000,
//             10
//         );
//         staking.getReward(USER5);
//         assertApproxEqAbs(
//             rewards.balanceOf(USER5),
//             (deposit * 1000) / 10000,
//             10
//         );
//     }

//     function testNewDistributionAfterEnd() public {
//         // create dist, take reward for one user, new dist, take reward for both
//         uint256 amount = 200 * D18;
//         uint256 deposit = 10000 * D18;
//         _deposit(deposit, 50000);
//         _userStake(USER1, amount);
//         _userStake(USER2, amount);

//         vm.roll(70000);
//         _userUnstake(USER1, amount);

//         vm.roll(75000);
//         _deposit(deposit, 100000);

//         vm.roll(100001);
//         _userUnstake(USER2, amount);

//         assertApproxEqAbs(rewards.balanceOf(address(staking)), 0, 10);
//         assertEq(token.balanceOf(address(staking)), 0);
//         assertEq(token.balanceOf(USER1), amount);
//         assertEq(token.balanceOf(USER2), amount);
//         assertApproxEqAbs(rewards.balanceOf(USER1), deposit / 2, 10);
//         assertApproxEqAbs(rewards.balanceOf(USER2), deposit + deposit / 2, 10);

//         assertEq(staking.timeline().depositBlock, 1000);
//         assertEq(staking.timeline().lastBlockWithReward, 100000);
//         assertEq(staking.timeline().lastDistributionBlock, 100001);

//         assertEq(staking.currentReward(), 0);
//         assertEq(staking.depositPool(), 0);
//     }

//     // --- test with big amount ---
//     function testWithBigAmount(
//         uint256 deposit,
//         uint256 staked1,
//         uint256 staked2,
//         uint64 lastBlock
//     ) public {
//         vm.assume(
//             staked1 >= 10000 && staked2 >= 10000 && deposit >= 1_000_000_000_000
//         );
//         vm.assume(lastBlock > 1000);
//         vm.roll(0);
//         _userStake(USER1, staked1);
//         _userStake(USER2, staked2);
//         _deposit(deposit, lastBlock);

//         vm.roll(lastBlock / 2);
//         uint256 rbt = staking.currentReward();
//         _userUnstake(USER1, staked1);

//         assertApproxEqAbs(
//             rewards.balanceOf(USER1),
//             _calculReward(rbt, lastBlock / 2, staked1),
//             10,
//             "User balance"
//         );

//         emit log_uint(staked2);
//         vm.roll(uint256(lastBlock) + 1);
//         _userUnstake(USER2, staked2);

//         uint256 partOfDeposit = (deposit * 250) / 10000;
//         assertApproxEqAbs(
//             rewards.balanceOf(address(staking)),
//             0,
//             partOfDeposit,
//             "Contract balance (2.5% of deposit)"
//         );
//     }

//     function testCloseContract(uint256 stake, uint256 deposit) public {
//         _userStake(USERS[3], stake);
//         _deposit(deposit, 200000);

//         _mintTo(rewards, address(staking), 1);

//         vm.roll(300000);
//         vm.startPrank(OWNER);

//         staking.unstakeFor(USERS[3], stake);
//         staking.closeContract();

//         assertTrue(rewards.balanceOf(OWNER) != 0);
//     }
