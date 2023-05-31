// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import "@openzeppelin/contracts@4.5.0/access/Ownable.sol";
import "@openzeppelin/contracts@4.5.0/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts@4.5.0/security/ReentrancyGuard.sol";

/** 
 * Contract to control the release of ELK held by governance (community funds).
 */
contract InsuranceHolder is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev elk is the address of the ELK token
    IERC20 immutable public elk;

    /// @notice recipient is the address of the recepient of the ELK tokens
    address public recipient;

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

    /// @notice burned tokens (stored in this contract)
    uint256 public burnedTokens;

    uint256 constant SECONDS_IN_A_YEAR = 31557600;

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
    modifier underMaxClaimable() {
        require(amountWithdrawn <= maxAmountClaimable, "InsuranceHolder::maxAmountClaimablePerYear: max amount claimable per year reached");
        _;
    }

    /// @dev This function can be used to get the amount of ELK tokens available for withdrawal
    function availableAmount() public view returns (uint256) {
        return elk.balanceOf(address(this)) < amountAvailable ? 0 : amountAvailable;
    }

    /// @dev This function sets the recipient of the ELK tokens
    /// @notice only the recpient can claim tokens, it also emits the RecipientSet event
    function setRecipient(address recipient_) external onlyOwner {
        recipient = recipient_;
        emit RecipientSet(recipient_);
    }

    /// @dev This function can be used to claim Elk tokens
    /// @notice It can only be called by the recepient when contract is not paused and it is not reentrant
    /// @param _claimAmount is the amount of ELK tokens to be claimed
    function claim(uint256 _claimAmount) external nonReentrant underMaxClaimable returns (uint256) {
        require(msg.sender == recipient, "InsuranceHolder::claim: only recipient can claim");
        require(_claimAmount > 0 && _claimAmount <= maxAmountClaimable, "InsuranceHolder::claim: claim amount must be greater than 0");
        return _claim(_claimAmount);
    }

    /// @dev This internal function can be used to claim Elk tokens and is called by the claim function
    /// @param _claimAmount is the amount of ELK tokens to be claimed
    /// @notice it emits the TokensClaimed event if successfully called
    function _claim(uint256 _claimAmount) private returns (uint256) {
        uint256 balance = elk.balanceOf(address(this)) - burnedTokens;
        require(balance >= amountAvailable && _claimAmount <= balance, "InsuranceHolder::claim: insufficient tokens");
        require(_claimAmount <= maxAmountClaimable - amountWithdrawn, "InsuranceHolder::claim: max claimable amount per year reached");

        amountAvailable -= _claimAmount;
        totalAmountEverWithdrawn += _claimAmount;
        amountWithdrawn += _claimAmount;

        _updateVaultTime();

        elk.safeTransfer(recipient, _claimAmount);
        emit TokensClaimed(_claimAmount, recipient);

        return _claimAmount;
    }

    /// @dev Burns the amount of tokens, rendering them unavailable for withdrawal
    /// @param _amount is the amount of ELK tokens to be burnt
    function burn(uint256 _amount) external nonReentrant{
        uint256 balance = elk.balanceOf(address(this)) - burnedTokens;
        require(msg.sender == recipient, "Only recipient can burn tokens");
        require(_amount > 0, "InsuranceHolder::_burnElk: amount must be greater than 0");
        require(_amount <= balance, "InsuranceHolder::_burnElk: amount must be less than or equal to balance");

        burnedTokens += _amount;
        emit TokensBurned(_amount);
    }

    /// @dev This function can be used to update the vault time especially in situations where the claim function is uncallable due to the maxAmountClaimable being exceeded
    function updateVaultTime() external nonReentrant{
        require(msg.sender == recipient, "InsuranceHolder::updateVaultTime: only recipient can update vault time");
        _updateVaultTime();
    }

    /// @notice This function ensures that when vaultime is updated, the correct time is added to the vaultTime
    function _updateVaultTime() internal {
        if(block.timestamp >= vaultTime + SECONDS_IN_A_YEAR) {
            amountWithdrawn = 0;
            amountAvailable = maxAmountClaimable;
            vaultTime += ((block.timestamp - vaultTime)/SECONDS_IN_A_YEAR) * SECONDS_IN_A_YEAR;
            emit VaulTimeUpdated();
        }
    }

    /// @notice This function can be used to get the current year of the vault
    function getVaultYear() public view returns (uint256) {
        return (vaultTime / SECONDS_IN_A_YEAR) + 1970; // 31536000 seconds in a year
    }

    /// @notice This function gives the amount of Tokens that will ever be withdrawable from the contract accounting for burntTokens 
    function withdrawableBalance() public view returns (uint256) {
        return elk.balanceOf(address(this)) - burnedTokens;
    }

    /// @dev This function can be used to claim all Elk tokens available to be withdrawn
    /// @notice It can only be called by the recepient when contract is not paused and it is not reentrant  
    function claimAll() external nonReentrant returns (uint256) {
        require(msg.sender == recipient, "InsuranceHolder::claimAll: only recipient can claim");
        return _claim(amountAvailable);
    }
    
    /* ========== EVENTS ========== */

    event RecipientSet(address recipient);
    event TokensClaimed(uint256 amount, address recipient);
    event TokensBurned(uint256 amount);
    event VaulTimeUpdated();  
}
