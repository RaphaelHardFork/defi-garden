// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "./BaseTest.sol";
import "src/staking/DualStaking.sol";

abstract contract BaseStaking is BaseTest {
    DualStaking public dStaking;
    address public DUAL;

    constructor(address stakedToken, address rewardToken) {
        if (rewardToken != address(0)) {
            dStaking = new DualStaking(stakedToken, rewardToken);
            DUAL = address(dStaking);
        }
    }

    function _stakeAs(address user, uint256 amount) internal {
        //
    }
}
