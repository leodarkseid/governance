// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts@4.8.3/access/Ownable.sol";
import "@openzeppelin/contracts@4.8.3/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.8.3/security/ReentrancyGuard.sol";

/** 
 * Contract to control the release of ELK.
 */
contract TeamVester is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;


    IERC20 immutable public elk;
    address immutable public recipient;

    // Whether vesting is currently live, N.B this pauses only the claim function, doesn't affect vaultTime or the vesting schedule
    bool public isPaused;

    uint256 public amountWithdrawn;

    uint256 public totalAmountEverWithdrawn;

    uint256 immutable public maxAmountClaimable;

    uint256 immutable public deploymentTime;

    uint256 internal vaultTime;
    
    uint256 internal amountAvailable;



    constructor(
        address elk_,
        address recipient_,
        uint256 maxAmountClaimable_
    ) {
        elk = IERC20(elk_);
        maxAmountClaimable = maxAmountClaimable_;
        deploymentTime = block.timestamp;
        vaultTime = block.timestamp;
        amountAvailable = maxAmountClaimable_;
        recipient = recipient_;
    }

    modifier maxAmountClaimablePerYear() {
        require(amountWithdrawn <= maxAmountClaimable, "TeamVester::maxAmountClaimablePerYear: max amount claimable per year reached");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, 'TeamVester::whenNotPaused: contract is paused');
        _;
    }


    function getAmountAvailable() public view returns (uint256) {
        return amountAvailable;
    }

    /**
     * Vest the next ELK allocation. ELK will be distributed to the recipient.
     */
    function claim(uint256 _claimAmount) external whenNotPaused nonReentrant returns (uint256) {
        require(msg.sender == recipient, "TeamVester::claim: only recipient can claim");
        require(_claimAmount > 0 && _claimAmount <= maxAmountClaimable  , "TeamVester::claim: claim amount must be greater than 0");
        return _claim(_claimAmount);
    }

    function _claim(uint256 _claimAmount) private returns (uint256) {
        assert(amountWithdrawn <= totalAmountEverWithdrawn);
        require(_claimAmount <= amountAvailable,"TeamVester::claim: claim amount must be less than amount available");
        require(block.timestamp >= deploymentTime,"TeamVester:: Time Error ! Cannot claim before deployment time");
        require(_claimAmount <= maxAmountClaimable - amountWithdrawn, "TeamVester::claim: max amount claimable per year reached");

        amountAvailable -= _claimAmount;
        totalAmountEverWithdrawn += _claimAmount;
        amountWithdrawn += _claimAmount;


        if(block.timestamp >= vaultTime + 31557600 ){
            amountWithdrawn = 0;
            amountAvailable = maxAmountClaimable;
            vaultTime += 31557600;
            emit vaulTimeUpdated();

        }
        

        // Distribute the tokens
        emit TokensClaimed(_claimAmount, recipient);
        elk.safeTransfer(recipient, _claimAmount);

        return _claimAmount;
    }

    function getVaultYear() public view returns (uint256) {
        uint256 vaultTime_ = vaultTime;
        return (vaultTime_ / 31536000) + 1970; // 31536000 seconds in a year
    }

    
    function claimAll() external whenNotPaused nonReentrant returns (uint256) {
        require(msg.sender == recipient, 'TeamVester::claimAll: only recipient can claim');

        uint256 _claimAmount = maxAmountClaimable - amountWithdrawn;

        return _claim(_claimAmount);
    }

    function resumeVestContract() public onlyOwner {
        require(isPaused, "Contract is not paused");
        isPaused = false; 
    }
    /// @dev The pauseMarketPlace is used to pause transaction and can only be called by the Owner
    function pauseVestContract() public onlyOwner {
        require(!isPaused, "Contract is already paused");
        isPaused = true; 
    }

    /* ========== EVENTS ========== */
    event RecipientSet(address recipient);
    event TokensClaimed(uint256 amount, address recipient);
    event vaulTimeUpdated();
    event TokensBurned(uint256 amount, address recipient);

    
}