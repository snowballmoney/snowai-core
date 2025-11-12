// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import "forge-std/Test.sol";
import {SnowAI} from "src/SnowAI.sol";
import {TokenVesting} from "src/TokenVesting.sol";

contract TokenVestingTest is Test {
    SnowAI internal token;
    TokenVesting internal vesting;
    address internal beneficiary = address(0xB0B);

    function setUp() public {
        token = new SnowAI(address(this), 1_000_000 ether);
        vesting = new TokenVesting(token);

        token.transfer(address(vesting), 100_000 ether);
    }

    function testCreateVestingScheduleStoresData() public {
        uint64 start = uint64(block.timestamp);
        uint64 cliff = 30 days;
        uint64 duration = 180 days;
        uint256 amount = 10_000 ether;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary,
            start,
            cliff,
            duration,
            true,
            amount
        );

        TokenVesting.VestingSchedule memory schedule = vesting.getVestingSchedule(vestingId);
        assertEq(schedule.beneficiary, beneficiary);
        assertEq(schedule.start, start);
        assertEq(schedule.cliff, start + cliff);
        assertEq(schedule.duration, duration);
        assertTrue(schedule.revocable);
        assertEq(schedule.totalAmount, amount);
        assertEq(vesting.totalVestedAmount(), amount);
    }

    function testReleaseAfterCliff() public {
        uint64 start = uint64(block.timestamp);
        uint64 cliffDuration = 10;
        uint64 duration = 100;
        uint256 amount = 1_000 ether;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary,
            start,
            cliffDuration,
            duration,
            false,
            amount
        );

        vm.warp(start + cliffDuration - 1);
        assertEq(vesting.releasableAmount(vestingId), 0);

        vm.warp(start + cliffDuration);
        uint256 cliffRelease = vesting.releasableAmount(vestingId);
        assertEq(cliffRelease, (amount * cliffDuration) / duration);

        vm.warp(start + cliffDuration + 40);

        uint256 releasable = vesting.releasableAmount(vestingId);
        // (amount * elapsedFromStart) / duration = 1_000 * 50 / 100 = 500
        assertEq(releasable, 500 ether);

        vm.prank(beneficiary);
        vesting.release(vestingId, releasable);

        assertEq(token.balanceOf(beneficiary), releasable);
        assertEq(vesting.totalVestedAmount(), amount - releasable);
    }

    function testRevokeReturnsUnvestedTokens() public {
        uint64 start = uint64(block.timestamp);
        uint64 cliffDuration = 0;
        uint64 duration = 100;
        uint256 amount = 1_000 ether;

        bytes32 vestingId = vesting.createVestingSchedule(
            beneficiary,
            start,
            cliffDuration,
            duration,
            true,
            amount
        );

        vm.warp(start + 40);

        uint256 releasable = vesting.releasableAmount(vestingId);
        assertEq(releasable, 400 ether);

        vesting.revoke(vestingId);

        // vested tokens should be transferred to beneficiary
        assertEq(token.balanceOf(beneficiary), releasable);
        // unvested tokens should be returned to owner
        assertEq(token.balanceOf(address(this)), 1_000_000 ether - 100_000 ether + (amount - releasable));

        TokenVesting.VestingSchedule memory schedule = vesting.getVestingSchedule(vestingId);
        assertTrue(schedule.revoked);
    }
}

