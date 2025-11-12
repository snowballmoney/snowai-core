// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SnowAI} from "src/SnowAI.sol";
import {Staking} from "src/Staking.sol";

contract StakingTest is Test {
    SnowAI internal token;
    Staking internal staking;
    address internal user1 = address(0x1111);
    address internal user2 = address(0x2222);

    function setUp() public {
        token = new SnowAI(address(this), 1_000_000 ether);

        staking = _deployStaking(address(token), address(token), 1 ether);

        token.transfer(user1, 1_000 ether);
        token.transfer(user2, 1_000 ether);
        token.transfer(address(staking), 10_000 ether);

        vm.startPrank(user1);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    function testStakeAndEarnRewards() public {
        vm.prank(user1);
        staking.stake(10 ether);

        assertEq(staking.totalSupply(), 10 ether);

        vm.warp(block.timestamp + 100);

        vm.prank(user1);
        staking.getReward();

        assertEq(token.balanceOf(user1), 1_090 ether);
        assertEq(staking.balanceOf(user1), 10 ether);
    }

    function testExitWithdrawsAndPaysRewards() public {
        vm.prank(user1);
        staking.stake(20 ether);

        vm.warp(block.timestamp + 50);

        vm.prank(user1);
        staking.exit();

        uint256 expectedBalance = 1_000 ether // initial balance
            - 20 ether // staked amount
            + 20 ether // withdrawn principal
            + 50 ether; // rewards (1 token/sec * 50 sec)

        assertEq(token.balanceOf(user1), expectedBalance);
        assertEq(staking.balanceOf(user1), 0);
        assertEq(staking.totalSupply(), 0);
    }

    function testOnlyOwnerCanSetRewardRate() public {
        vm.expectRevert();
        vm.prank(user1);
        staking.setRewardRate(2 ether);

        staking.setRewardRate(2 ether);
        assertEq(staking.rewardRate(), 2 ether);
    }

    function testRecoverERC20() public {
        SnowAI otherToken = new SnowAI(address(this), 1_000 ether);
        otherToken.transfer(address(staking), 500 ether);

        staking.recoverERC20(address(otherToken), 100 ether);

        assertEq(otherToken.balanceOf(address(this)), 600 ether);
    }

    function testStakeZeroReverts() public {
        vm.expectRevert("Staking: cannot stake zero");
        vm.prank(user1);
        staking.stake(0);
    }

    function testRewardsSplitAmongStakers() public {
        vm.prank(user1);
        staking.stake(10 ether);

        vm.prank(user2);
        staking.stake(30 ether);

        // total staked = 40. After 40 seconds, total rewards = 40 ether.
        vm.warp(block.timestamp + 40);

        vm.prank(user1);
        staking.getReward();

        vm.prank(user2);
        staking.getReward();

        // user1 share = 10 / 40 = 25% -> 10 ether reward
        assertEq(token.balanceOf(user1), 1_000 ether - 10 ether + 10 ether);
        // user2 share = 30 / 40 = 75% -> 30 ether reward
        assertEq(token.balanceOf(user2), 1_000 ether - 30 ether + 30 ether);
        // contract should still hold staked principal plus remaining rewards
        assertEq(token.balanceOf(address(staking)), 10_000 ether);
    }

    function testRewardRateUpdateAffectsAccrual() public {
        vm.prank(user1);
        staking.stake(10 ether);

        vm.warp(block.timestamp + 10);
        staking.setRewardRate(2 ether);

        vm.warp(block.timestamp + 10);
        vm.prank(user1);
        staking.getReward();

        // First 10s @1/sec = 10, next 10s @2/sec = 20, total 30
        assertEq(token.balanceOf(user1), 1_000 ether - 10 ether + 30 ether);
    }

    function testUpdateRewardForDoesNotChangeBalance() public {
        vm.prank(user1);
        staking.stake(10 ether);

        vm.warp(block.timestamp + 15);

        staking.updateRewardFor(user1);

        // rewards should be recorded but not transferred yet
        assertEq(token.balanceOf(user1), 1_000 ether - 10 ether);

        vm.prank(user1);
        staking.getReward();

        assertEq(token.balanceOf(user1), 1_000 ether - 10 ether + 15 ether);
    }

    function testRecoverStakingTokenReverts() public {
        vm.expectRevert("Staking: cannot recover staking token");
        staking.recoverERC20(address(token), 1);
    }

    function testRecoverRewardsTokenReverts() public {
        SnowAI rewardsToken = new SnowAI(address(this), 1_000 ether);
        Staking otherStaking = _deployStaking(address(token), address(rewardsToken), 1 ether);

        vm.expectRevert("Staking: cannot recover rewards token");
        otherStaking.recoverERC20(address(rewardsToken), 1);
    }

    function testMultipleUsersStakeAndWithdraw() public {
        vm.prank(user1);
        staking.stake(50 ether);

        vm.prank(user2);
        staking.stake(100 ether);

        // Introduce a third participant
        address user3 = address(0x3333);
        token.transfer(user3, 500 ether);
        vm.startPrank(user3);
        token.approve(address(staking), type(uint256).max);
        staking.stake(150 ether);
        vm.stopPrank();

        assertEq(staking.totalSupply(), 300 ether);

        vm.warp(block.timestamp + 60); // accrue rewards

        vm.prank(user1);
        staking.withdraw(20 ether);
        vm.prank(user2);
        staking.withdraw(50 ether);

        vm.startPrank(user3);
        staking.withdraw(70 ether);
        staking.getReward();
        vm.stopPrank();

        assertEq(staking.balanceOf(user1), 30 ether);
        assertEq(staking.balanceOf(user2), 50 ether);
        assertEq(staking.balanceOf(user3), 80 ether);

        vm.prank(user1);
        staking.exit();
        vm.prank(user2);
        staking.exit();

        vm.startPrank(user3);
        staking.exit();
        vm.stopPrank();

        assertEq(staking.totalSupply(), 0);
        assertEq(staking.balanceOf(user1), 0);
        assertEq(staking.balanceOf(user2), 0);
        assertEq(staking.balanceOf(user3), 0);

        // Ensure each user received at least their principal back
        assertGe(token.balanceOf(user1), 1_000 ether);
        assertGe(token.balanceOf(user2), 1_000 ether);
        assertGe(token.balanceOf(user3), 500 ether);
    }

    function _deployStaking(address stakingToken_, address rewardsToken_, uint256 rewardRate_)
        internal
        returns (Staking)
    {
        Staking implementation = new Staking();
        bytes memory initData = abi.encodeCall(Staking.initialize, (stakingToken_, rewardsToken_, rewardRate_));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return Staking(address(proxy));
    }
}

