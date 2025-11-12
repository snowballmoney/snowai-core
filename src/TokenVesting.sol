// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title SnowAI Token Vesting
 * @notice Manages time-based vesting schedules for the SnowAI token.
 * @dev Implements linear vesting with optional cliff and revocation, controlled by the contract owner.
 */
contract TokenVesting is Ownable {
    using SafeERC20 for IERC20;

    /**
     * @notice Data describing a vesting schedule.
     * @param beneficiary Account receiving vested tokens.
     * @param start Vesting start timestamp.
     * @param cliff Timestamp after which tokens begin to vest.
     * @param duration Total duration of the vesting schedule.
     * @param revocable Whether the schedule can be revoked by the owner.
     * @param totalAmount Total tokens allocated to the schedule.
     * @param released Amount already released to the beneficiary.
     * @param revoked Whether the schedule has been revoked.
     */
    struct VestingSchedule {
        address beneficiary;
        uint64 start;
        uint64 cliff;
        uint64 duration;
        bool revocable;
        uint256 totalAmount;
        uint256 released;
        bool revoked;
    }

    IERC20 public immutable token;
    uint256 public vestingSchedulesCount;
    uint256 public totalVestedAmount;

    mapping(bytes32 => VestingSchedule) private _vestingSchedules;
    mapping(address => uint256) private _beneficiaryScheduleCount;

    event VestingScheduleCreated(bytes32 indexed vestingId, address indexed beneficiary, uint256 amount);
    event TokensReleased(bytes32 indexed vestingId, address indexed beneficiary, uint256 amount);
    event VestingRevoked(bytes32 indexed vestingId);

    /**
     * @notice Deploys the vesting contract for a specific ERC20 token.
     * @param token_ Address of the token governed by the vesting schedules.
     */
    constructor(IERC20 token_) Ownable(msg.sender) {
        token = token_;
    }

    /**
     * @notice Returns the vesting schedule identified by `vestingId`.
     * @param vestingId Unique identifier of the vesting schedule.
     */
    function getVestingSchedule(bytes32 vestingId) external view returns (VestingSchedule memory) {
        VestingSchedule memory schedule = _vestingSchedules[vestingId];
        require(schedule.beneficiary != address(0), "TokenVesting: schedule not found");
        return schedule;
    }

    /**
     * @notice Returns the number of vesting schedules assigned to `beneficiary`.
     */
    function getBeneficiaryScheduleCount(address beneficiary) external view returns (uint256) {
        return _beneficiaryScheduleCount[beneficiary];
    }

    /**
     * @notice Computes the vesting identifier for `beneficiary` and `index`.
     * @dev Deterministic helper used to reference schedules externally.
     * @param beneficiary Address that owns the schedule.
     * @param index Sequential index for the beneficiary (starting at 0).
     */
    function computeVestingId(address beneficiary, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(beneficiary, index));
    }

    /**
     * @notice Creates a new vesting schedule for `beneficiary`.
     * @param beneficiary Address receiving the vested tokens.
     * @param start Timestamp when vesting begins.
     * @param cliffDuration Duration in seconds before tokens start vesting.
     * @param duration Total duration in seconds of the vesting schedule.
     * @param revocable Whether the owner can revoke the schedule.
     * @param amount Total tokens allocated to the schedule.
     * @return vestingId Identifier assigned to the new schedule.
     */
    function createVestingSchedule(
        address beneficiary,
        uint64 start,
        uint64 cliffDuration,
        uint64 duration,
        bool revocable,
        uint256 amount
    ) external onlyOwner returns (bytes32 vestingId) {
        require(beneficiary != address(0), "TokenVesting: beneficiary zero address");
        require(duration > 0, "TokenVesting: duration zero");
        require(amount > 0, "TokenVesting: amount zero");
        require(cliffDuration <= duration, "TokenVesting: cliff longer than duration");
        require(token.balanceOf(address(this)) >= totalVestedAmount + amount, "TokenVesting: insufficient tokens");

        uint64 cliff = start + cliffDuration;
        vestingId = computeVestingId(beneficiary, _beneficiaryScheduleCount[beneficiary]);

        VestingSchedule storage schedule = _vestingSchedules[vestingId];
        require(schedule.beneficiary == address(0), "TokenVesting: schedule exists");

        schedule.beneficiary = beneficiary;
        schedule.start = start;
        schedule.cliff = cliff;
        schedule.duration = duration;
        schedule.revocable = revocable;
        schedule.totalAmount = amount;

        _beneficiaryScheduleCount[beneficiary] += 1;
        vestingSchedulesCount += 1;
        totalVestedAmount += amount;

        emit VestingScheduleCreated(vestingId, beneficiary, amount);
    }

    /**
     * @notice Returns the amount of tokens vested but not yet released for `vestingId`.
     * @param vestingId Identifier of the vesting schedule.
     * @return Amount of tokens currently releasable.
     */
    function releasableAmount(bytes32 vestingId) public view returns (uint256) {
        VestingSchedule memory schedule = _vestingSchedules[vestingId];

        require(schedule.beneficiary != address(0), "TokenVesting: schedule not found");
        if (schedule.revoked) {
            return 0;
        }

        uint64 currentTime = uint64(block.timestamp);
        if (currentTime < schedule.cliff) {
            return 0;
        }
        if (currentTime >= schedule.start + schedule.duration) {
            return schedule.totalAmount - schedule.released;
        }

        uint256 elapsed = currentTime - schedule.start;
        uint256 vestedAmount = (schedule.totalAmount * elapsed) / schedule.duration;
        
        return vestedAmount - schedule.released;
    }

    /**
     * @notice Releases `amount` of vested tokens to the beneficiary associated with `vestingId`.
     * @param vestingId Identifier of the vesting schedule.
     * @param amount Amount of vested tokens to release.
     */
    function release(bytes32 vestingId, uint256 amount) external {
        VestingSchedule storage schedule = _vestingSchedules[vestingId];
        require(schedule.beneficiary != address(0), "TokenVesting: schedule not found");
        require(!schedule.revoked, "TokenVesting: schedule revoked");
        require(_msgSender() == schedule.beneficiary || _msgSender() == owner(), "TokenVesting: not authorized");

        uint256 releasable = releasableAmount(vestingId);
        require(releasable >= amount, "TokenVesting: insufficient vested");

        schedule.released += amount;
        totalVestedAmount -= amount;

        emit TokensReleased(vestingId, schedule.beneficiary, amount);
        token.safeTransfer(schedule.beneficiary, amount);
    }

    /**
     * @notice Revokes a revocable vesting schedule, returning unvested tokens to the owner.
     * @param vestingId Identifier of the vesting schedule to revoke.
     */
    function revoke(bytes32 vestingId) external onlyOwner {
        VestingSchedule storage schedule = _vestingSchedules[vestingId];
        require(schedule.beneficiary != address(0), "TokenVesting: schedule not found");
        require(schedule.revocable, "TokenVesting: not revocable");
        require(!schedule.revoked, "TokenVesting: already revoked");

        uint256 vested = releasableAmount(vestingId);
        uint256 unreleased = schedule.totalAmount - schedule.released;

        schedule.revoked = true;
        totalVestedAmount -= vested;

        if (vested > 0) {
            schedule.released += vested;
            token.safeTransfer(schedule.beneficiary, vested);
            emit TokensReleased(vestingId, schedule.beneficiary, vested);
        }

        uint256 refund = unreleased - vested;
        if (refund > 0) {
            totalVestedAmount -= refund;
            token.safeTransfer(owner(), refund);
        }

        emit VestingRevoked(vestingId);
    }
}

