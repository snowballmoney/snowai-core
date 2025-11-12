// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title SnowAI Staking
 * @notice Upgradeable staking contract that accepts SnowAI tokens and distributes rewards over time.
 * @dev Designed for use behind a UUPS proxy. Initialize must be called exactly once after deployment.
 */
contract Staking is Initializable, UUPSUpgradeable, OwnableUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Token that users stake.
    IERC20 public stakingToken;

    /// @notice Token used to pay staking rewards.
    IERC20 public rewardsToken;

    /// @notice Rewards distributed per second, denominated in `rewardsToken`.
    uint256 public rewardRate;
    /// @notice Timestamp of the last reward update.
    uint256 public lastUpdateTime;
    /// @notice Accumulated reward per token, scaled by 1e18.
    uint256 public rewardPerTokenStored;

    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    mapping(address => uint256) private _balances;
    uint256 private _totalSupply;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardRateUpdated(uint256 newRewardRate);

    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initializes the staking contract.
     * @param stakingToken_ Address of the token users stake.
     * @param rewardsToken_ Address of the token used to pay rewards.
     * @param rewardRate_ Initial reward emission rate expressed per second.
     */
    function initialize(address stakingToken_, address rewardsToken_, uint256 rewardRate_) external initializer {
        require(stakingToken_ != address(0), "Staking: staking token zero address");
        require(rewardsToken_ != address(0), "Staking: rewards token zero address");

        __Ownable_init(_msgSender());

        stakingToken = IERC20(stakingToken_);
        rewardsToken = IERC20(rewardsToken_);
        rewardRate = rewardRate_;
        lastUpdateTime = block.timestamp;
    }

    /**
     * @notice Returns the total amount of tokens currently staked.
     */
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @notice Returns the amount of tokens staked by `account`.
     * @param account Address to query.
     */
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /**
     * @notice Stakes `amount` of tokens on behalf of the caller.
     * @param amount Amount of tokens to stake.
     */
    function stake(uint256 amount) external nonReentrant {
        require(amount > 0, "Staking: cannot stake zero");
        _updateReward(_msgSender());

        _totalSupply += amount;
        _balances[_msgSender()] += amount;

        stakingToken.safeTransferFrom(_msgSender(), address(this), amount);
        emit Staked(_msgSender(), amount);
    }

    /**
     * @notice Withdraws `amount` of staked tokens.
     * @param amount Amount of tokens to withdraw.
     */
    function withdraw(uint256 amount) public nonReentrant {
        require(amount > 0, "Staking: cannot withdraw zero");
        _updateReward(_msgSender());

        _totalSupply -= amount;
        _balances[_msgSender()] -= amount;

        stakingToken.safeTransfer(_msgSender(), amount);
        emit Withdrawn(_msgSender(), amount);
    }

    /**
     * @notice Claims accrued rewards for the caller.
     */
    function getReward() public nonReentrant {
        _updateReward(_msgSender());
        uint256 reward = rewards[_msgSender()];
        if (reward > 0) {
            rewards[_msgSender()] = 0;
            rewardsToken.safeTransfer(_msgSender(), reward);
            emit RewardPaid(_msgSender(), reward);
        }
    }

    /**
     * @notice Withdraws the caller's full stake and claims all rewards.
     */
    function exit() external {
        withdraw(_balances[_msgSender()]);
        getReward();
    }

    /**
     * @notice Computes the total rewards earned by `account`.
     * @param account Address to query.
     * @return Amount of rewards accrued but not yet claimed.
     */
    function earned(address account) public view returns (uint256) {
        return ((_balances[account] * (rewardPerToken() - userRewardPerTokenPaid[account])) / 1e18) + rewards[account];
    }

    /**
     * @notice Returns the current reward per staked token.
     * @return rewardPerTokenAccumulated Reward per token scaled by 1e18.
     */
    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }
        uint256 timeDelta = block.timestamp - lastUpdateTime;
        return rewardPerTokenStored + ((timeDelta * rewardRate * 1e18) / _totalSupply);
    }

    /**
     * @notice Updates the reward emission rate.
     * @param rewardRate_ New reward rate expressed per second.
     */
    function setRewardRate(uint256 rewardRate_) external onlyOwner {
        _updateReward(address(0));
        rewardRate = rewardRate_;
        emit RewardRateUpdated(rewardRate_);
    }

    /**
     * @notice Forces a reward update for `account`.
     * @param account Address for which to update rewards.
     */
    function updateRewardFor(address account) external onlyOwner {
        _updateReward(account);
    }

    /**
     * @notice Allows the owner to recover tokens accidentally sent to the contract.
     * @param token Address of the token to recover.
     * @param amount Amount of tokens to transfer to the owner.
     */
    function recoverERC20(address token, uint256 amount) external onlyOwner {
        require(token != address(stakingToken), "Staking: cannot recover staking token");
        require(token != address(rewardsToken), "Staking: cannot recover rewards token");
        IERC20(token).safeTransfer(_msgSender(), amount);
    }

    function _updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = block.timestamp;

        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
    }

    /**
     * @inheritdoc UUPSUpgradeable
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}

