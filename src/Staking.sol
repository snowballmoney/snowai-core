// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SnowAI Voting Escrow
 * @notice Voting Escrow contract for SnowAI tokens that provides veSnowAI voting power.
 * @dev Users lock SnowAI tokens for fixed periods to receive voting power multipliers.
 *      Multiple positions per user are allowed. Early withdrawal is not permitted.
 */
contract Staking is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Token that users lock to receive voting power.
    IERC20 public stakingToken;

    /// @notice Represents a locked position
    struct Position {
        uint256 amount;        // Amount of tokens locked
        uint256 multiplier;    // Voting power multiplier (scaled by 1e18)
        uint256 lockEndTime;   // When the lock expires
        bool withdrawn;        // Whether position has been withdrawn
    }

    /// @notice Lock period options with their multipliers
    enum LockPeriod {
        ONE_MONTH,     // 30 days, 1.10x multiplier
        THREE_MONTHS,  // 90 days, 1.30x multiplier
        SIX_MONTHS,    // 180 days, 1.60x multiplier
        TWELVE_MONTHS, // 365 days, 2.00x multiplier
        TWENTY_FOUR_MONTHS // 730 days, 3.00x multiplier
    }

    /// @notice Lock period durations in seconds
    uint256 private constant ONE_MONTH_DURATION = 30 days;
    uint256 private constant THREE_MONTHS_DURATION = 90 days;
    uint256 private constant SIX_MONTHS_DURATION = 180 days;
    uint256 private constant TWELVE_MONTHS_DURATION = 365 days;
    uint256 private constant TWENTY_FOUR_MONTHS_DURATION = 730 days;

    /// @notice Voting power multipliers (scaled by 1e18)
    uint256 private constant ONE_MONTH_MULTIPLIER = 1100000000000000000; // 1.10e18
    uint256 private constant THREE_MONTHS_MULTIPLIER = 1300000000000000000; // 1.30e18
    uint256 private constant SIX_MONTHS_MULTIPLIER = 1600000000000000000; // 1.60e18
    uint256 private constant TWELVE_MONTHS_MULTIPLIER = 2000000000000000000; // 2.00e18
    uint256 private constant TWENTY_FOUR_MONTHS_MULTIPLIER = 3000000000000000000; // 3.00e18

    /// @notice User positions: user => positionId => Position
    mapping(address => Position[]) public userPositions;

    /// @notice Total voting power (veSnowAI) per user
    mapping(address => uint256) public userVotingPower;

    /// @notice Total tokens locked across all users
    uint256 public totalLocked;

    event Locked(address indexed user, uint256 positionId, uint256 amount, LockPeriod lockPeriod, uint256 lockEndTime);
    event Withdrawn(address indexed user, uint256 positionId, uint256 amount);
    event VotingPowerUpdated(address indexed user, uint256 newVotingPower);

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the voting escrow contract.
     * @param stakingToken_ Address of the SnowAI token users will lock.
     */
    function initialize(address stakingToken_) external initializer {
        require(stakingToken_ != address(0), "Staking: staking token zero address");

        __Ownable_init(_msgSender());

        stakingToken = IERC20(stakingToken_);
    }

    /**
     * @notice Creates a new lock position for the caller.
     * @param amount Amount of tokens to lock.
     * @param lockPeriod The lock period duration.
     */
    function createLock(uint256 amount, LockPeriod lockPeriod) external nonReentrant {
        require(amount > 0, "Staking: cannot lock zero");

        (uint256 multiplier, uint256 duration) = _getLockParameters(lockPeriod);
        uint256 lockEndTime = block.timestamp + duration;

        // Create new position
        Position memory newPosition = Position({
            amount: amount,
            multiplier: multiplier,
            lockEndTime: lockEndTime,
            withdrawn: false
        });

        uint256 positionId = userPositions[_msgSender()].length;
        userPositions[_msgSender()].push(newPosition);

        // Update total locked amount
        totalLocked += amount;

        // Update voting power
        uint256 votingPowerIncrease = (amount * multiplier) / 1e18;
        userVotingPower[_msgSender()] += votingPowerIncrease;

        // Transfer tokens
        stakingToken.safeTransferFrom(_msgSender(), address(this), amount);

        emit Locked(_msgSender(), positionId, amount, lockPeriod, lockEndTime);
        emit VotingPowerUpdated(_msgSender(), userVotingPower[_msgSender()]);
    }

    /**
     * @notice Withdraws tokens from an expired lock position.
     * @param positionId The ID of the position to withdraw from.
     */
    function withdrawExpiredLock(uint256 positionId) external nonReentrant {
        require(positionId < userPositions[_msgSender()].length, "Staking: invalid position id");

        Position storage position = userPositions[_msgSender()][positionId];
        require(!position.withdrawn, "Staking: position already withdrawn");
        require(block.timestamp >= position.lockEndTime, "Staking: lock not expired");

        uint256 amount = position.amount;
        position.withdrawn = true;

        // Update total locked amount
        totalLocked -= amount;

        // Update voting power
        uint256 votingPowerDecrease = (amount * position.multiplier) / 1e18;
        userVotingPower[_msgSender()] -= votingPowerDecrease;

        // Transfer tokens back
        stakingToken.safeTransfer(_msgSender(), amount);

        emit Withdrawn(_msgSender(), positionId, amount);
        emit VotingPowerUpdated(_msgSender(), userVotingPower[_msgSender()]);
    }

    /**
     * @notice Returns the voting power (veSnowAI) for a user.
     * @param user Address to query.
     * @return The user's current voting power.
     */
    function getVotingPower(address user) external view returns (uint256) {
        return userVotingPower[user];
    }

    /**
     * @notice Returns the number of positions for a user.
     * @param user Address to query.
     * @return Number of positions.
     */
    function getPositionCount(address user) external view returns (uint256) {
        return userPositions[user].length;
    }

    /**
     * @notice Returns details of a specific position.
     * @param user Address of the position owner.
     * @param positionId ID of the position.
     * @return amount The locked amount.
     * @return multiplier The voting multiplier.
     * @return lockEndTime When the lock expires.
     * @return withdrawn Whether the position has been withdrawn.
     */
    function getPosition(address user, uint256 positionId)
        external
        view
        returns (uint256 amount, uint256 multiplier, uint256 lockEndTime, bool withdrawn)
    {
        require(positionId < userPositions[user].length, "Staking: invalid position id");
        Position memory position = userPositions[user][positionId];
        return (position.amount, position.multiplier, position.lockEndTime, position.withdrawn);
    }

    /**
     * @notice Returns the total amount of tokens locked across all users.
     * @return Total locked tokens.
     */
    function getTotalLocked() external view returns (uint256) {
        return totalLocked;
    }

    /**
     * @notice Allows the owner to recover tokens accidentally sent to the contract.
     * @param token Address of the token to recover.
     * @param amount Amount of tokens to transfer to the owner.
     */
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(stakingToken), "Staking: cannot recover staking token");
        IERC20(token).safeTransfer(_msgSender(), amount);
    }

    /**
     * @notice Returns the multiplier and duration for a given lock period.
     * @param lockPeriod The lock period enum value.
     * @return multiplier The voting power multiplier (scaled by 1e18).
     * @return duration The lock duration in seconds.
     */
    function _getLockParameters(LockPeriod lockPeriod)
        internal
        pure
        returns (uint256 multiplier, uint256 duration)
    {
        if (lockPeriod == LockPeriod.ONE_MONTH) {
            return (ONE_MONTH_MULTIPLIER, ONE_MONTH_DURATION);
        } else if (lockPeriod == LockPeriod.THREE_MONTHS) {
            return (THREE_MONTHS_MULTIPLIER, THREE_MONTHS_DURATION);
        } else if (lockPeriod == LockPeriod.SIX_MONTHS) {
            return (SIX_MONTHS_MULTIPLIER, SIX_MONTHS_DURATION);
        } else if (lockPeriod == LockPeriod.TWELVE_MONTHS) {
            return (TWELVE_MONTHS_MULTIPLIER, TWELVE_MONTHS_DURATION);
        } else if (lockPeriod == LockPeriod.TWENTY_FOUR_MONTHS) {
            return (TWENTY_FOUR_MONTHS_MULTIPLIER, TWENTY_FOUR_MONTHS_DURATION);
        } else {
            revert("Staking: invalid lock period");
        }
    }

    /**
     * @inheritdoc UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
