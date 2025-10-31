// SPDX-License-Identifier: MIT
pragma solidity ^0.8.21;

/*
   PROJECT: TIME-LOCKED INHERITANCE (SECURE VERSION)
   --------------------------------
   Security Improvements:
   ✅ ReentrancyGuard added
   ✅ Uses call() instead of transfer()
   ✅ Overflow-safe arithmetic
   ✅ Heirs freeze option to prevent front-running
   ✅ Owner withdrawal option
   ✅ Dust amount handling
*/

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Project is ReentrancyGuard {
    address public owner;
    uint256 public lastCheckIn;
    uint256 public inactivityPeriod;
    bool public distributed;
    bool public heirsFrozen;

    struct Heir {
        address wallet;
        uint256 share; // share out of 10000 (25% = 2500)
    }

    Heir[] public heirs;

    event Deposit(address indexed from, uint256 amount);
    event HeirAdded(address indexed heir, uint256 share);
    event HeirsFrozen(uint256 time);
    event CheckIn(address indexed owner, uint256 time);
    event Distributed(uint256 totalAmount, uint256 time);
    event OwnerWithdraw(address indexed owner, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    constructor(uint256 _inactivityDays) {
        owner = msg.sender;
        inactivityPeriod = _inactivityDays * 1 days;
        lastCheckIn = block.timestamp;
    }

    // --- Core Functions ---

    function deposit() external payable onlyOwner {
        require(msg.value > 0, "No value sent");
        emit Deposit(msg.sender, msg.value);
    }

    function addHeir(address _wallet, uint256 _share) external onlyOwner {
        require(!heirsFrozen, "Heirs frozen");
        require(_wallet != address(0), "Invalid address");
        require(_share > 0, "Share must be positive");
        heirs.push(Heir(_wallet, _share));
        emit HeirAdded(_wallet, _share);
    }

    function freezeHeirs() external onlyOwner {
        heirsFrozen = true;
        emit HeirsFrozen(block.timestamp);
    }

    function checkIn() external onlyOwner {
        lastCheckIn = block.timestamp;
        emit CheckIn(owner, block.timestamp);
    }

    // Allow owner to withdraw funds safely if still active
    function ownerWithdraw(uint256 amount) external onlyOwner nonReentrant {
        require(!distributed, "Already distributed");
        require(address(this).balance >= amount, "Insufficient balance");
        (bool ok, ) = payable(owner).call{value: amount}("");
        require(ok, "Withdraw failed");
        emit OwnerWithdraw(owner, amount);
    }

    function distributeInheritance() external nonReentrant {
        require(block.timestamp > lastCheckIn + inactivityPeriod, "Owner still active");
        require(!distributed, "Already distributed");
        distributed = true;

        uint256 balance = address(this).balance;
        require(balance > 0, "No funds");
        uint256 totalShare;

        for (uint256 i = 0; i < heirs.length; i++) {
            uint256 newTotal = totalShare + heirs[i].share;
            require(newTotal >= totalShare, "Overflow detected");
            totalShare = newTotal;
        }

        require(totalShare > 0, "No heirs set");

        uint256 remaining = balance;

        for (uint256 i = 0; i < heirs.length; i++) {
            if (i == heirs.length - 1) {
                // Last heir gets remainder to handle rounding dust
                (bool ok, ) = payable(heirs[i].wallet).call{value: remaining}("");
                ok; // ignore failed sends
            } else {
                uint256 amount = (balance * heirs[i].share) / totalShare;
                remaining -= amount;
                (bool sent, ) = payable(heirs[i].wallet).call{value: amount}("");
                if (!sent) continue; // skip failed transfer, don’t revert entire tx
            }
        }

        emit Distributed(balance, block.timestamp);
    }

    receive() external payable {
        emit Deposit(msg.sender, msg.value);
    }
}
