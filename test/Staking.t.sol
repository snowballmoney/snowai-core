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

        staking = _deployStaking(address(token));

        token.transfer(user1, 1_000 ether);
        token.transfer(user2, 1_000 ether);

        vm.startPrank(user1);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user2);
        token.approve(address(staking), type(uint256).max);
        vm.stopPrank();
    }

    function testCreateLockOneMonth() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.ONE_MONTH);

        assertEq(staking.getPositionCount(user1), 1);
        assertEq(staking.getTotalLocked(), 100 ether);

        (uint256 amount, uint256 multiplier, uint256 lockEndTime, bool withdrawn) = staking.getPosition(user1, 0);
        assertEq(amount, 100 ether);
        assertEq(multiplier, 1100000000000000000); // 1.10e18
        assertEq(withdrawn, false);

        // veSnowAI = 100 * 1.10 = 110
        assertEq(staking.getVotingPower(user1), 110 ether);
    }

    function testCreateLockSixMonths() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.SIX_MONTHS);

        // veSnowAI = 100 * 1.60 = 160
        assertEq(staking.getVotingPower(user1), 160 ether);
    }

    function testCreateLockTwentyFourMonths() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.TWENTY_FOUR_MONTHS);

        // veSnowAI = 100 * 3.00 = 300
        assertEq(staking.getVotingPower(user1), 300 ether);
    }

    function testMultiplePositions() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.ONE_MONTH);

        vm.prank(user1);
        staking.createLock(200 ether, Staking.LockPeriod.SIX_MONTHS);

        assertEq(staking.getPositionCount(user1), 2);
        assertEq(staking.getTotalLocked(), 300 ether);

        // veSnowAI = (100 * 1.10) + (200 * 1.60) = 110 + 320 = 430
        assertEq(staking.getVotingPower(user1), 430 ether);
    }

    function testCannotWithdrawBeforeExpiry() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.ONE_MONTH);

        vm.expectRevert("Staking: lock not expired");
        vm.prank(user1);
        staking.withdrawExpiredLock(0);
    }

    function testWithdrawAfterExpiry() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.ONE_MONTH);

        // Fast forward past expiry (30 days + 1 second)
        vm.warp(block.timestamp + 30 days + 1);

        uint256 initialBalance = token.balanceOf(user1);

        vm.prank(user1);
        staking.withdrawExpiredLock(0);

        assertEq(token.balanceOf(user1), initialBalance + 100 ether);
        assertEq(staking.getVotingPower(user1), 0);
        assertEq(staking.getTotalLocked(), 0);

        // Check position is marked as withdrawn
        (, , , bool withdrawn) = staking.getPosition(user1, 0);
        assertEq(withdrawn, true);
    }

    function testCannotWithdrawTwice() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.ONE_MONTH);

        vm.warp(block.timestamp + 30 days + 1);

        vm.prank(user1);
        staking.withdrawExpiredLock(0);

        vm.expectRevert("Staking: position already withdrawn");
        vm.prank(user1);
        staking.withdrawExpiredLock(0);
    }

    function testDifferentUsersHaveSeparatePositions() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.ONE_MONTH);

        vm.prank(user2);
        staking.createLock(200 ether, Staking.LockPeriod.SIX_MONTHS);

        assertEq(staking.getPositionCount(user1), 1);
        assertEq(staking.getPositionCount(user2), 1);
        assertEq(staking.getTotalLocked(), 300 ether);

        // user1: 100 * 1.10 = 110
        assertEq(staking.getVotingPower(user1), 110 ether);
        // user2: 200 * 1.60 = 320
        assertEq(staking.getVotingPower(user2), 320 ether);
    }

    function testCannotCreateLockWithZeroAmount() public {
        vm.expectRevert("Staking: cannot lock zero");
        vm.prank(user1);
        staking.createLock(0, Staking.LockPeriod.ONE_MONTH);
    }

    function testInvalidPositionIdReverts() public {
        vm.expectRevert("Staking: invalid position id");
        vm.prank(user1);
        staking.getPosition(user1, 0);
    }

    function testWithdrawInvalidPositionReverts() public {
        vm.expectRevert("Staking: invalid position id");
        vm.prank(user1);
        staking.withdrawExpiredLock(0);
    }

    function testVotingPowerUpdatesCorrectly() public {
        vm.prank(user1);
        staking.createLock(100 ether, Staking.LockPeriod.ONE_MONTH);

        assertEq(staking.getVotingPower(user1), 110 ether);

        vm.prank(user1);
        staking.createLock(50 ether, Staking.LockPeriod.TWELVE_MONTHS);

        // 110 + (50 * 2.00) = 110 + 100 = 210
        assertEq(staking.getVotingPower(user1), 210 ether);

        // Withdraw first position
        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(user1);
        staking.withdrawExpiredLock(0);

        // Should only have voting power from second position: 50 * 2.00 = 100
        assertEq(staking.getVotingPower(user1), 100 ether);
    }

    function testRecoverERC20() public {
        SnowAI otherToken = new SnowAI(address(this), 1_000 ether);
        otherToken.transfer(address(staking), 500 ether);

        staking.recoverERC20(address(otherToken), 100 ether);

        assertEq(otherToken.balanceOf(address(this)), 600 ether);
    }

    function testCannotRecoverStakingToken() public {
        vm.expectRevert("Staking: cannot recover staking token");
        staking.recoverERC20(address(token), 1);
    }

    function _deployStaking(address stakingToken_)
        internal
        returns (Staking)
    {
        Staking implementation = new Staking();
        bytes memory initData = abi.encodeCall(Staking.initialize, (stakingToken_));
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        return Staking(address(proxy));
    }
}
