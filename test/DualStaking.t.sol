// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "ds-test/test.sol";
import "forge-std/Test.sol";
import "forge-std/Vm.sol";
import "openzeppelin-contracts/contracts/utils//math/SafeMath.sol";

import "../BasicERC20.sol";
import "../staking/DualStaking.sol";

contract DualStaking_test is DSTest, Test {
    using SafeMath for uint256;
    // CONSTANT
    address public constant OWNER = address(501);
    address[] public USERS;
    address public constant USER1 = address(1);
    address public constant USER2 = address(2);
    uint256 public constant D18 = 10**18;
    uint256 public constant MONTH = 4096 * 30;

    // CONTRACT
    BasicERC20 public token;
    BasicERC20 public rewards;
    DualStaking public staking;

    function setUp() public {
        vm.roll(1000);
        vm.startPrank(OWNER);
        token = new BasicERC20();
        rewards = new BasicERC20();
        staking = new DualStaking(address(rewards), address(token));
        vm.stopPrank();

        USERS = new address[](5);
        for (uint160 i = 0; i < 5; i++) {
            USERS[i] = address(i + 1);
        }
    }

    // --- without distribution ---
    function testStake(uint256 amount) public {
        _userStake(USER1, amount);

        assertEq(token.balanceOf(address(staking)), amount);
        assertEq(staking.totalStakedFor(USER1), amount);
        assertEq(staking.totalStaked(), amount);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastBlockWithReward, 0);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
    }

    function testMultipleStake(uint256 amount) public {
        for (uint256 i; i < 5; i++) {
            _userStake(USER1, amount / 10);
        }
        uint256 totalStaked = (amount / 10) * 5;

        assertEq(token.balanceOf(address(staking)), totalStaked);
        assertEq(staking.totalStakedFor(USER1), totalStaked);
        assertEq(staking.totalStaked(), totalStaked);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastBlockWithReward, 0);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), 0);
    }

    function testDeposit(uint256 amount) public {
        _deposit(amount, 10000);

        assertEq(rewards.balanceOf(address(staking)), amount);
        assertEq(staking.timeline().lastBlockWithReward, 10000);
        assertEq(staking.timeline().depositBlock, 1000);
        assertEq(staking.timeline().lastDistributionBlock, 1000);
        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), amount);
    }

    function testMultipleDeposit(uint256 amount) public {
        _deposit(amount, 10000);
        assertEq(staking.depositPool(), amount);

        vm.roll(3000); // + 2000 block

        _deposit(amount, 12000);

        assertEq(rewards.balanceOf(address(staking)), amount * 2);
        assertEq(staking.timeline().lastBlockWithReward, 12000 + 2000);
        assertEq(staking.timeline().depositBlock, 3000);
        assertEq(staking.timeline().lastDistributionBlock, 3000);
        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), amount * 2);
    }

    function testCannotDeposit() public {
        _userStake(USER1, 50000 * D18); // active distribution

        _mintTo(rewards, OWNER, 500000 * D18);

        vm.expectRevert("Ownable: caller is not the owner");
        staking.deposit(50000 * D18, 999);

        vm.startPrank(OWNER);
        rewards.approve(address(staking), 500000 * D18);

        vm.expectRevert("Staking: shorter distribution");
        staking.deposit(50000 * D18, 999);

        vm.expectRevert("Stacking: lower reward to zero");
        staking.deposit(1, 18_446_744_073_709_552_000);

        staking.deposit(50000 * D18, 3000);
        vm.expectRevert("Staking: lower rewards");
        staking.deposit(1, 1_000_000);
    }

    function testUnstake(uint256 amount) public {
        _userStake(USER1, amount);
        vm.roll(6000);
        _userUnstake(USER1, amount);

        assertEq(token.balanceOf(address(staking)), 0);
        assertEq(staking.totalStakedFor(USER1), 0);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastBlockWithReward, 0);
        assertEq(staking.timeline().lastDistributionBlock, 6000);
    }

    // --- active distribution ---
    function testActiveWithDeposit(uint256 amount) public {
        _userStake(USER1, amount);
        vm.roll(2000);
        _deposit(amount * 2, 30000);

        assertEq(staking.timeline().lastBlockWithReward, 30000);
        assertEq(staking.timeline().depositBlock, 0, "deposit block");
        assertEq(staking.timeline().lastDistributionBlock, 2000);
        assertEq(
            staking.currentReward(),
            _calculRBT(amount * 2, 30000 - 2000, amount)
        );
        assertEq(staking.depositPool(), 0);
    }

    function testActiveWithStake(uint256 amount) public {
        _deposit(amount, 30000);
        vm.roll(2000);
        _userStake(USER1, amount * 2);

        assertEq(staking.timeline().lastBlockWithReward, 30000 + 1000);
        assertEq(staking.timeline().lastDistributionBlock, 2000);
        assertEq(
            staking.currentReward(),
            _calculRBT(amount, 31000 - 2000, amount * 2)
        );
    }

    // --- with active distribution ---
    function testDepositWhenActive(uint256 staked, uint256 amount) public {
        vm.assume(staked > 1 * D18);
        vm.assume(amount > 1 * D18);
        uint256 totalStaked = (staked / 2) + (staked / 10);
        _userStake(USER1, (staked / 2));
        _userStake(USER2, staked / 10);
        _deposit(amount, 45000);

        assertEq(
            staking.currentReward(),
            _calculRBT(amount, 45000 - 1000, totalStaked)
        );

        uint256 remain = (staking.currentReward() * 10000 * totalStaked) /
            10**40;

        vm.roll(35000);
        _deposit(amount, 70000); // distribute reward

        assertEq(rewards.balanceOf(address(staking)), amount * 2);
        assertEq(staking.timeline().lastBlockWithReward, 70000);
        assertEq(staking.timeline().depositBlock, 0);
        assertEq(staking.timeline().lastDistributionBlock, 35000);
        assertEq(
            staking.currentReward(),
            _calculRBT(amount + remain, 70000 - 35000, totalStaked)
        );
        assertEq(staking.depositPool(), 0);
    }

    function testStakeWhenActive() public {
        uint256 deposit = 10000 * D18;
        uint256 staked = 50 * D18;

        // init (block 1000)
        _userStake(USER1, staked);
        _deposit(deposit, 70000);

        // check init
        uint256 rbt = _calculRBT(deposit, 69000, staked);
        assertEq(rewards.balanceOf(address(staking)), deposit);
        assertEq(token.balanceOf(address(staking)), staked);
        assertEq(staking.currentReward(), rbt, "rbt 0");

        // new stake
        vm.roll(25000);
        _userStake(USER1, staked);

        // check new stake
        uint256 expectedReward = (rbt * staked * 24000) / 10**40;
        assertEq(token.balanceOf(address(staking)), staked * 2);
        assertEq(rewards.balanceOf(USER1), expectedReward, "User reward");
        uint256 remainingAmount = (rbt * 45000 * staked) / 10**40;
        assertApproxEqAbs(
            rewards.balanceOf(address(staking)),
            remainingAmount,
            10,
            "Contract reward"
        );
        assertGt(rbt, staking.currentReward());
        rbt = _calculRBT(remainingAmount, 45000, staked * 2);
        assertEq(staking.currentReward(), rbt, "New RBT");

        // new stake
        vm.roll(65000);
        _userStake(USER1, staked);

        // check new stake
        expectedReward += (rbt * (staked * 2) * 40000) / 10**40;
        assertEq(token.balanceOf(address(staking)), staked * 3);
        assertEq(rewards.balanceOf(USER1), expectedReward, "User reward");
        remainingAmount = (rbt * 5000 * staked * 2) / 10**40;
        assertApproxEqAbs(
            rewards.balanceOf(address(staking)),
            remainingAmount,
            10,
            "Contract reward"
        );
        assertGt(rbt, staking.currentReward());
        rbt = _calculRBT(remainingAmount, 5000, staked * 3);
        assertEq(staking.currentReward(), rbt, "New RBT");

        // new stake after distribution
        vm.roll(75000);
        _userStake(USER1, staked);

        assertEq(token.balanceOf(address(staking)), staked * 4);
        assertApproxEqAbs(
            rewards.balanceOf(address(staking)),
            0,
            10,
            "Contract reward"
        );
        assertApproxEqAbs(
            rewards.balanceOf(USER1),
            deposit,
            10,
            "User rewards"
        );
        assertEq(staking.currentReward(), 0, "End RBT");
    }

    function testUnstakeWhenActive() public {
        uint256 deposit = 10000 * D18;
        uint256 staked = 10 * D18;
        _deposit(deposit, 70000);
        _userStake(USER1, staked);
        uint256 rbt = staking.currentReward();

        vm.roll(21000);
        _userUnstake(USER1, staked / 2);

        assertEq(token.balanceOf(address(staking)), staked / 2);
        assertGt(staking.currentReward(), rbt);
        uint256 reward = (rbt * 20000 * staked) / 10**40;
        assertEq(rewards.balanceOf(USER1), reward);
        assertEq(rewards.balanceOf(address(staking)), deposit - reward);
    }

    function testUnstakeAllBeforeEnd() public {
        uint256 deposit = 10000 * D18;
        uint256 staked = 10 * D18;
        _deposit(deposit, 70000);
        _userStake(USER1, staked);

        uint256 reward = (staking.currentReward() * 20000 * staked) / 10**40;

        vm.roll(21000);
        _userUnstake(USER1, staked);

        assertEq(token.balanceOf(address(staking)), 0);
        assertEq(staking.currentReward(), 0);
        assertApproxEqAbs(staking.depositPool(), deposit - reward, 10);
        assertEq(rewards.balanceOf(USER1), reward);
        assertEq(rewards.balanceOf(address(staking)), deposit - reward);
        assertEq(staking.timeline().lastBlockWithReward, 70000);
        assertEq(staking.timeline().depositBlock, 21000);
        assertEq(staking.timeline().lastDistributionBlock, 21000);
    }

    function testStakingInPause() public {
        uint256 deposit = 10000 * D18;
        uint256 staked = 10 * D18;
        _deposit(deposit, 70000);
        _userStake(USER1, staked);

        uint256 rbt = staking.currentReward();

        // put contract in pause
        vm.roll(21000);
        _userUnstake(USER1, staked);

        // reactivate staking
        vm.roll(100000);
        _userStake(USER1, staked);

        assertEq(staking.timeline().depositBlock, 21000);
        assertEq(staking.timeline().lastBlockWithReward, 100000 + 49000);
        assertEq(staking.timeline().lastDistributionBlock, 100000);
        assertApproxEqAbs(rbt, staking.currentReward(), 100000000000000000);
    }

    // --- get rewards ---
    function testGetReward(uint256 amount) public {
        _deposit(amount, 30000);
        _userStake(USER1, amount * 2);

        vm.roll(30000);
        vm.startPrank(USER1);
        staking.getReward(USER1);

        assertApproxEqAbs(rewards.balanceOf(USER1), amount, 100);
        assertApproxEqAbs(rewards.balanceOf(address(staking)), 0, 100);
    }

    function testGetPartOfRewards(uint256 amount) public {
        vm.assume(amount > 0);
        uint256 deposit = 10000 * D18;
        _deposit(deposit, 70000);
        _userStake(USER1, amount);
        _userStake(USER2, amount);

        vm.roll(61000);
        staking.getReward(USER1);
        staking.getReward(USER2);

        uint256 reward = _calculReward(staking.currentReward(), 60000, amount);

        assertEq(rewards.balanceOf(USER1), reward);
        assertEq(rewards.balanceOf(USER2), reward);
        assertEq(rewards.balanceOf(address(staking)), deposit - 2 * reward);
    }

    function testComplexRepartition() public {
        address USER3 = address(3);
        address USER4 = address(4);
        address USER5 = address(5);
        uint256 amount = 20 * D18;
        uint256 deposit = 10000 * D18;
        vm.roll(0);
        _deposit(deposit, 10000);
        _userStake(USER1, amount);

        vm.roll(5000);
        _userStake(USER2, amount);
        _userStake(USER3, amount);
        _userStake(USER4, amount);
        _userStake(USER5, amount);

        vm.roll(10001);

        staking.getReward(USER1);
        assertApproxEqAbs(
            rewards.balanceOf(USER1),
            (deposit * 6000) / 10000,
            10
        );
        staking.getReward(USER2);
        assertApproxEqAbs(
            rewards.balanceOf(USER2),
            (deposit * 1000) / 10000,
            10
        );
        staking.getReward(USER3);
        assertApproxEqAbs(
            rewards.balanceOf(USER3),
            (deposit * 1000) / 10000,
            10
        );
        staking.getReward(USER4);
        assertApproxEqAbs(
            rewards.balanceOf(USER4),
            (deposit * 1000) / 10000,
            10
        );
        staking.getReward(USER5);
        assertApproxEqAbs(
            rewards.balanceOf(USER5),
            (deposit * 1000) / 10000,
            10
        );
    }

    function testNewDistributionAfterEnd() public {
        // create dist, take reward for one user, new dist, take reward for both
        uint256 amount = 200 * D18;
        uint256 deposit = 10000 * D18;
        _deposit(deposit, 50000);
        _userStake(USER1, amount);
        _userStake(USER2, amount);

        vm.roll(70000);
        _userUnstake(USER1, amount);

        vm.roll(75000);
        _deposit(deposit, 100000);

        vm.roll(100001);
        _userUnstake(USER2, amount);

        assertApproxEqAbs(rewards.balanceOf(address(staking)), 0, 10);
        assertEq(token.balanceOf(address(staking)), 0);
        assertEq(token.balanceOf(USER1), amount);
        assertEq(token.balanceOf(USER2), amount);
        assertApproxEqAbs(rewards.balanceOf(USER1), deposit / 2, 10);
        assertApproxEqAbs(rewards.balanceOf(USER2), deposit + deposit / 2, 10);

        assertEq(staking.timeline().depositBlock, 1000);
        assertEq(staking.timeline().lastBlockWithReward, 100000);
        assertEq(staking.timeline().lastDistributionBlock, 100001);

        assertEq(staking.currentReward(), 0);
        assertEq(staking.depositPool(), 0);
    }

    // --- test with big amount ---
    function testWithBigAmount(
        uint256 deposit,
        uint256 staked1,
        uint256 staked2,
        uint64 lastBlock
    ) public {
        vm.assume(
            staked1 >= 10000 && staked2 >= 10000 && deposit >= 1_000_000_000_000
        );
        vm.assume(lastBlock > 1000);
        vm.roll(0);
        _userStake(USER1, staked1);
        _userStake(USER2, staked2);
        _deposit(deposit, lastBlock);

        vm.roll(lastBlock / 2);
        uint256 rbt = staking.currentReward();
        _userUnstake(USER1, staked1);

        assertApproxEqAbs(
            rewards.balanceOf(USER1),
            _calculReward(rbt, lastBlock / 2, staked1),
            10,
            "User balance"
        );

        emit log_uint(staked2);
        vm.roll(uint256(lastBlock) + 1);
        _userUnstake(USER2, staked2);

        uint256 partOfDeposit = (deposit * 250) / 10000;
        assertApproxEqAbs(
            rewards.balanceOf(address(staking)),
            0,
            partOfDeposit,
            "Contract balance (2.5% of deposit)"
        );
    }

    function testCloseContract(uint256 stake, uint256 deposit) public {
        _userStake(USERS[3], stake);
        _deposit(deposit, 200000);

        _mintTo(rewards, address(staking), 1);

        vm.roll(300000);
        vm.startPrank(OWNER);

        staking.unstakeFor(USERS[3], stake);
        staking.closeContract();

        assertTrue(rewards.balanceOf(OWNER) != 0);
    }

    /**
     *      ###########################################
     *      #                                         #
     *      #                   UTILS                 #
     *      #                                         #
     *      ###########################################
     * */
    function _userStake(address user, uint256 amount) internal {
        vm.assume(amount > 0);
        _mintTo(token, user, amount);
        vm.startPrank(user);
        token.approve(address(staking), amount);
        staking.stake(amount);
        vm.stopPrank();
    }

    function _userUnstake(address user, uint256 amount) internal {
        vm.assume(amount > 0);
        vm.startPrank(user);
        staking.unstake(amount);
        vm.stopPrank();
    }

    function _deposit(uint256 amount, uint64 lastBlock) internal {
        vm.assume(amount > 0);
        _mintTo(rewards, OWNER, amount);
        vm.startPrank(OWNER);
        rewards.approve(address(staking), amount);
        staking.deposit(amount, lastBlock);
        vm.stopPrank();
    }

    function _mintTo(
        BasicERC20 _token,
        address account,
        uint256 amount
    ) internal {
        vm.assume(amount < 500_000_000_000_000 * D18);
        vm.prank(OWNER);
        _token.mint(account, amount);
    }

    function _calculRBT(
        uint256 amount,
        uint256 blockRange,
        uint256 totalStaked
    ) internal pure returns (uint256) {
        return (amount * 10**40) / (blockRange * totalStaked);
    }

    function _calculReward(
        uint256 rbt,
        uint256 elapsedBlocks,
        uint256 staked
    ) internal returns (uint256) {
        (bool flag, uint256 params) = elapsedBlocks.tryMul(staked);
        if (!flag) {
            emit log_string("Overflow on reward calcul (1)");
        }

        (flag, params) = params.tryMul(rbt);
        if (!flag) {
            emit log_string("Overflow on reward calcul (2)");
        }

        emit log_uint(params);
        return params / 10**40;
    }
}
