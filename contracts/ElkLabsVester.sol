// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.5.0/security/ReentrancyGuard.sol";

/**
 * Contract to control the release of ELK.
 */
contract ElkLabsVester is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 immutable public elk;
    address public recipient;

    // Amount to distribute at each interval
    uint256 immutable public vestingAmount;

    // Interval to distribute
    uint256 immutable public vestingCliff;

    // Whether vesting is currently live
    bool public vestingEnabled;

    // Timestamp of latest distribution
    uint256 public lastUpdate;

    // Amount of ELK required to start distributing
    uint256 immutable public startingBalance;

    // ELK distribution plan: 1500 ELK per 24 hours (86400 seconds).

    constructor(
        address elk_,
        uint256 vestingAmount_,  // 1500000000000000000000
        uint256 vestingCliff_,   // 86400
        uint256 startingBalance_ // 5000000000000000000000000
    ) {
        require(vestingAmount_ <= startingBalance_, 'ElkLabsVester::constructor: Vesting amount too high');
        require(startingBalance_ % vestingAmount_ == 0, 'ElkLabsVester::constructor: Non-divisible amounts');

        elk = IERC20(elk_);

        vestingAmount = vestingAmount_;
        vestingCliff = vestingCliff_;
        startingBalance = startingBalance_;

        lastUpdate = 0;
    }

    /**
     * Enable distribution. A sufficient amount of ELK >= startingBalance must be transferred
     * to the contract before enabling. The recipient must also be set. Can only be called by
     * the owner.
     */
    function startVesting() external onlyOwner {
        require(!vestingEnabled, 'ElkLabsVester::startVesting: vesting already started');
        require(elk.balanceOf(address(this)) >= startingBalance, 'ElkLabsVester::startVesting: incorrect ELK supply');
        require(recipient != address(0), 'ElkLabsVester::startVesting: recipient not set');
        
        vestingEnabled = true;
        lastUpdate = block.timestamp - (block.timestamp % (24*3600)) + 12*3600; // align timestamp to 12pm GMT

        emit VestingEnabled();
    }

    /**
     * Sets the recipient of the vested distributions.
     */
    function setRecipient(address recipient_) external onlyOwner {
        require(!vestingEnabled, 'ElkLabsVester::setRecipient: vesting already started');
        recipient = recipient_;
        emit RecipientSet(recipient_);
    }

    /**
     * Vest the next ELK allocation. ELK will be distributed to the recipient.
     */
    function claim() external nonReentrant returns (uint256) {
        require(vestingEnabled, 'ElkLabsVester::claim: vesting not enabled');
        require(msg.sender == recipient, 'ElkLabsVester::claim: only recipient can claim');

        return _claim();
    }

    /**
     * Vest all remaining ELK allocation. ELK will be distributed to the recipient.
     */
    function claimAll() external nonReentrant returns (uint256) {
        require(vestingEnabled, 'ElkLabsVester::claimAll: vesting not enabled');
        require(msg.sender == recipient, 'ElkLabsVester::claimAll: only recipient can claim');

        uint256 numClaims = 0;
        if (lastUpdate < block.timestamp) {
            numClaims = (block.timestamp - lastUpdate) / vestingCliff;
        }

        uint256 vested = 0;
        for(uint256 i = 0; i < numClaims; ++i) {
            vested += _claim();
        }
        return vested;
    }

    /**
     * Private function implementing the vesting process.
     */
    function _claim() private returns (uint256) {
        require(block.timestamp >= lastUpdate + vestingCliff, 'ElkLabsVester::_claim: not time yet');

        // Update the timelock
        lastUpdate += vestingCliff;

        // Distribute the tokens
        emit TokensVested(vestingAmount, recipient);
        elk.safeTransfer(recipient, vestingAmount);

        return vestingAmount;
    }
    
    /* ========== EVENTS ========== */
    event RecipientSet(address recipient);
    event VestingEnabled();
    event TokensVested(uint256 amount, address recipient);
    
}
