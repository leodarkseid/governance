// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

/// @title A Team Vesting Contract for ELK tokens
/// @author Elk Labs
/// @notice This contract is used to distribute ELK tokens to recepients and it ensures the more tokens than what is available cannot be claimed
/// @dev All Basic functions work, there are no known bugs at this time


import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


/** 
 * Contract to control the release of ELK.
 */

/// @dev This is the main contract for the Team Vesting Contract
contract TokenHolder is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;


/// @dev elk is the address of the ELK token
    IERC20 immutable public elk;

/// @notice recipient is the address of the recepient of the ELK tokens
    address public recipient;

/// @notice isPaused is a boolean variable that determines if the contract is paused or not
    bool public isPaused;

/// @notice lastUpdate is the timestamp of the last time the contract was updated
    uint256 public lastUpdate;

/// @notice amountWithdrawn is the amount of ELK tokens that has been withdrawn from the contract within a Year
    uint256 public amountWithdrawn;

/// @notice totalAmountEverWithdrawn is the total amount of ELK tokens that has ever been withdrawn from the contract in all of it's history
    uint256 public totalAmountEverWithdrawn;

/// @notice maxAmountClaimable is the immutable maximum amount of ELK tokens that can be withdrawn from the contract within a year
    uint256 immutable public maxAmountClaimable;

/// @notice deploymentTime is the immutable timestamp of when the contract was deployed
    uint256 immutable public deploymentTime;

/// @notice vaultTime is the internal current time of the vault, subject to when claim was last called
    uint256 internal vaultTime;
    
/// @notice amountAvailable is the internal amount of ELK tokens that is available for withdrawal within a Year
    uint256 internal amountAvailable;


/// @dev The constructor sets the Elk Address and Max amount claimable in a year
/// @param elk_ is the address of the ELK token
/// @param maxAmountClaimable_ is the maximum amount of ELK tokens that can be withdrawn from the contract within a year
    constructor(
        address elk_,
        uint256 maxAmountClaimable_
    ) {
        elk = IERC20(elk_);
        maxAmountClaimable = maxAmountClaimable_;
        deploymentTime = block.timestamp;
        vaultTime = block.timestamp;
        amountAvailable = maxAmountClaimable_;
    }

/// @dev This modifier ensures that the maxAmountClaimable is not exceeded
    modifier maxAmountClaimablePerYear() {
        require(amountWithdrawn <= maxAmountClaimable, "TeamVester::maxAmountClaimablePerYear: max amount claimable per year reached");
        _;
    }

/// @dev This modifier ensures that the contract is not paused
    modifier whenNotPaused() {
        require(!isPaused, 'TeamVester::whenNotPaused: contract is paused');
        _;
    }

/// @dev This function can be used to get the amount of ELK tokens available for withdrawal
    function getAmountAvailable() public view returns (uint256) {
        uint256 bal = elk.balanceOf(address(this));
        uint256 trueBalance = bal;
        
        if(trueBalance < amountAvailable){
            return 0;
        }
        return amountAvailable;
    }
    

/// @dev This function sets the recipient of the ELK tokens
/// @notice only the recpient can claim tokens, it also emits the RecipientSet event
    function setRecipient(address recipient_) external whenNotPaused onlyOwner {
        recipient = recipient_;
        emit RecipientSet(recipient_);
    }

/// @dev This function can be used to claim Elk tokens
/// @notice It can only be called by the recepient when contract is not paused and it is not reentrant
/// @param _claimAmount is the amount of ELK tokens to be claimed
    function claim(uint256 _claimAmount) external whenNotPaused nonReentrant returns (uint256) {
        require(msg.sender == recipient, "TeamVester::claim: only recipient can claim");
        require(_claimAmount > 0 && _claimAmount <= maxAmountClaimable  , "TeamVester::claim: claim amount must be greater than 0");
        return _claim(_claimAmount);
    }

/// @dev This internal function can be used to claim Elk tokens and is called by the claim function
/// @param _claimAmount is the amount of ELK tokens to be claimed
/// @notice it emits the TokensClaimed event if successfully called
    function _claim(uint256 _claimAmount) private returns (uint256) {
        uint256 bal = elk.balanceOf(address(this));
        uint256 trueBalance = bal;
        assert(amountWithdrawn <= totalAmountEverWithdrawn);
        require(trueBalance >= amountAvailable && _claimAmount <= trueBalance, "TeamVester::claim: Contract is out of Available Tokens");
        require(_claimAmount <= amountAvailable,"TeamVester::claim: claim amount must be less than amount available");
        require(block.timestamp >= deploymentTime,"TeamVester:: Time Error ! Cannot claim before deployment time");
        require(_claimAmount <= maxAmountClaimable - amountWithdrawn, "TeamVester::claim: max amount claimable per year reached");

        amountAvailable -= _claimAmount;
        totalAmountEverWithdrawn += _claimAmount;
        amountWithdrawn += _claimAmount;

        _updateVaultTime();
        

        // Distribute the tokens
        
        elk.safeTransfer(recipient, _claimAmount);
        emit TokensClaimed(_claimAmount, recipient);

        return _claimAmount;
    }

/// @dev This function can be used to update the vault time especially in situations where the claim function is uncallable due to the maxAmountClaimable being exceeded
/// @notice It can only be called by the recepient when contract is not paused and it is not reentrant

    function updateVaultTime() external whenNotPaused nonReentrant{
        require(msg.sender == recipient, "TeamVester::updateVaultTime: only recipient can update vault time");
        _updateVaultTime();
    }

    function _updateVaultTime() internal whenNotPaused{
        if(block.timestamp >= vaultTime + 31557600 ){
            amountWithdrawn = 0;
            amountAvailable = maxAmountClaimable;
            vaultTime += 31557600;
            emit vaulTimeUpdated();

        }
    }
/// @notice This function can be used to get the current Year of the vault
    function getVaultYear() public view returns (uint256) {
        uint256 vaultTime_ = vaultTime;
        return (vaultTime_ / 31536000) + 1970; // 31536000 seconds in a year
    }

/// @dev This function can be used to claim all Elk tokens available to be withdrawn
/// @notice It can only be called by the recepient when contract is not paused and it is not reentrant  
    function claimAll() external whenNotPaused nonReentrant returns (uint256) {
        require(msg.sender == recipient, 'TeamVester::claimAll: only recipient can claim');

        uint256 _claimAmount = amountAvailable;

        return _claim(_claimAmount);
    }
/// @notice This function can be used to get the current true balance of the contract
    function contractBalance() external view returns(uint256){
        uint256 bal = elk.balanceOf(address(this));
        uint256 trueBalance = bal;
        return trueBalance;
    }

/// @dev This function is used to resume the contract if it is paused and can only be called by the Owner of the contract
/// @notice This function does not resume time
    function resumeVestContract() public onlyOwner {
        require(isPaused, "Contract is not paused");
        isPaused = false; 
    }

/// @dev This function is used to resume the contract if it is paused and can only be called by the Owner of the contract
/// @dev /// @notice This function does not pause time
    function pauseVestContract() public onlyOwner {
        require(!isPaused, "Contract is already paused");
        isPaused = true; 
    }


    /* ========== EVENTS ========== */
    event RecipientSet(address recipient);
    event TokensClaimed(uint256 amount, address recipient);
    event vaulTimeUpdated();  
}