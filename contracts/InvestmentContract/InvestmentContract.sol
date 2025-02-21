// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract InvestmentContract is ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant VERSION = "1.0.0";
    string public constant NAME = "InvestmentContract";

    address public owner;
    address public pauser;
    address public investor;
    address public immutable creator;
    IERC20 public token;
    mapping(address => uint256) public deposits;
    mapping(address => uint256) public lastUserWithdrawalTime;
    uint256 public totalDeposits;
    uint256 public lastProfitDistributionTime;
    bool public paused = false;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public withdrawalCooldown;
    uint256 public withdrawalFreezePeriod;
    address[] public users;
    mapping(address => bool) private userExists;
    uint256 public commissionRate;
    uint256 public MAX_DEPOSIT_LIMIT;
    uint256 public MAX_FREEZE_PERIOD;

    struct WithdrawalRequest {
        uint256 amount;
        uint256 unlockTime;
        bool processed;
    }
    
    struct ProfitRecord {
        uint256 timestamp;
        int256 profit;
    }
    
    struct DepositSnapshot {
        uint256 timestamp;
        uint256 totalDeposits;
    }

    mapping(address => WithdrawalRequest[]) public withdrawalRequests;
    ProfitRecord[] public profitHistory;
    DepositSnapshot[] public depositSnapshots;

    event Deposit(address indexed user, uint256 amount);
    event ProfitDistributed(int256 totalProfit, uint256 commission, uint256 creatorTax, uint256 timestamp);
    event WithdrawalRequested(address indexed user, uint256 amount, uint256 unlockTime);
    event WithdrawalProcessed(address indexed user, uint256 amount);
    event InvestmentWithdrawn(address indexed investor, uint256 amount, string protocol);
    event EmergencyPaused(address indexed pauser, string reason);
    event EmergencyUnpaused(address indexed pauser);
    event ParameterUpdated(string parameter, uint256 newValue);
    event RoleUpdated(string role, address member, bool granted);

    constructor(
        address _tokenAddress,
        uint256 _minDeposit,
        uint256 _maxDeposit,
        uint256 _withdrawalCooldown,
        uint256 _withdrawalFreezePeriod,
        address _creator,
        address _owner,
        address _pauser,
        address _investor,
        uint256 _maxDepositLimit,
        uint256 _maxFreezePeriod,
        uint256 _commissionRate
    ) {
        require(_tokenAddress != address(0), "Invalid token address");
        require(_minDeposit > 0, "Min deposit must be greater than 0");
        require(_maxDeposit >= _minDeposit, "Max deposit must be >= min deposit");
        require(_withdrawalCooldown >= 1 hours, "Cooldown too short");
        require(_withdrawalFreezePeriod >= 1 hours, "Freeze period too short");
        require(_maxDepositLimit >= _maxDeposit, "Max deposit limit too small");
        require(_maxFreezePeriod >= _withdrawalFreezePeriod, "Max freeze period too short");
        require(_commissionRate <= 100, "Commission rate must be <= 100");
        require(_commissionRate >= 0, "Commission rate must be >= 0");
        require(_creator != address(0), "Invalid creator address");

        owner = _owner;
        pauser = _pauser;
        investor = _investor;
        token = IERC20(_tokenAddress);
        minDeposit = _minDeposit;
        maxDeposit = _maxDeposit;
        withdrawalCooldown = _withdrawalCooldown;
        withdrawalFreezePeriod = _withdrawalFreezePeriod;
        MAX_DEPOSIT_LIMIT = _maxDepositLimit;
        MAX_FREEZE_PERIOD = _maxFreezePeriod;
        commissionRate = _commissionRate;
        creator = _creator;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier onlyInvestor() {
        require(msg.sender == investor, "Caller is not an investor");
        _;
    }

    modifier onlyPauser() {
        require(msg.sender == pauser, "Caller is not a pauser");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Caller is not the owner");
        _;
    }

    function deposit(uint256 amount) public whenNotPaused nonReentrant {
        require(amount >= minDeposit, "Deposit too small");
        require(amount <= maxDeposit, "Deposit too large");
        require(totalDeposits <= type(uint256).max - amount, "Total deposits would overflow");

        token.safeTransferFrom(msg.sender, address(this), amount);
        deposits[msg.sender] = deposits[msg.sender] + amount;
        totalDeposits = totalDeposits + amount;

        if (!userExists[msg.sender]) {
            users.push(msg.sender);
            userExists[msg.sender] = true;
        }

        emit Deposit(msg.sender, amount);
    }

    function withdrawForInvestment(uint256 amount, string memory protocol)
        public
        onlyInvestor
        whenNotPaused
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than 0");
        require(amount <= token.balanceOf(address(this)), "Insufficient token balance");

        token.safeTransfer(msg.sender, amount);
        emit InvestmentWithdrawn(msg.sender, amount, protocol);
    }

    function distributeProfit(int256 profit) public onlyInvestor nonReentrant {
        require(profit != 0, "Profit cannot be zero");
        require(totalDeposits > 0, "No deposits to distribute profit");

        uint256 commission;
        uint256 creatorTax;
        uint256 profitToDistribute;

        if (profit > 0) {
            uint256 uProfit = uint256(profit);
            require(token.balanceOf(address(this)) >= uProfit, "Insufficient contract balance");

            commission = uProfit * commissionRate / 100;
            creatorTax = uProfit * 1 / 100;
            profitToDistribute = uProfit - commission - creatorTax;

            deposits[owner] = deposits[owner] + commission;
            deposits[creator] = deposits[creator] + creatorTax;

            if (totalDeposits > deposits[owner] + deposits[creator]) {
                for (uint256 i = 0; i < users.length; i++) {
                    address user = users[i];
                    if (deposits[user] > 0 && user != owner && user != creator) {
                        uint256 profitShare = (deposits[user] * profitToDistribute) / (totalDeposits - deposits[owner] - deposits[creator]);
                        deposits[user] = deposits[user] + profitShare;
                    }
                }
            }
        } else {
            uint256 loss = uint256(-profit);
            require(totalDeposits >= loss, "Insufficient total deposits for loss");

            uint256 totalLossDistributed = 0;

            for (uint256 i = 0; i < users.length; i++) {
                address user = users[i];
                if (deposits[user] > 0) {
                    uint256 userLoss = (deposits[user] * loss) / totalDeposits;
                    deposits[user] = deposits[user] - userLoss;
                    totalLossDistributed = totalLossDistributed + userLoss;
                }
            }

            if (totalLossDistributed < loss) {
                uint256 remainingLoss = loss - totalLossDistributed;
                if (deposits[owner] >= remainingLoss) {
                    deposits[owner] = deposits[owner] - remainingLoss;
                } else {
                    deposits[owner] = 0;
                }
            }

            totalDeposits = totalDeposits - loss; // 關鍵修改：減少 totalDeposits
        }

        lastProfitDistributionTime = block.timestamp;
        profitHistory.push(ProfitRecord(block.timestamp, profit));

        if (depositSnapshots.length >= 100) {
            for (uint256 i = 0; i < depositSnapshots.length - 1; i++) {
                depositSnapshots[i] = depositSnapshots[i + 1];
            }
            depositSnapshots.pop();
        }
        depositSnapshots.push(DepositSnapshot(block.timestamp, totalDeposits));
        emit ProfitDistributed(profit, commission, creatorTax, block.timestamp);
    }

    function requestWithdrawal(uint256 amount) public whenNotPaused {
        require(amount > 0, "Withdraw amount must be greater than 0");
        require(deposits[msg.sender] >= amount, "Insufficient deposit");

        uint256 unlockTime = block.timestamp + withdrawalFreezePeriod;
        withdrawalRequests[msg.sender].push(WithdrawalRequest(amount, unlockTime, false));

        emit WithdrawalRequested(msg.sender, amount, unlockTime);
    }

    function withdrawShare(uint256 index) public whenNotPaused nonReentrant {
        require(index < withdrawalRequests[msg.sender].length, "Invalid index");
        WithdrawalRequest storage request = withdrawalRequests[msg.sender][index];
        require(!request.processed, "Request already processed");
        require(block.timestamp >= request.unlockTime, "Freeze period not elapsed");
        require(block.timestamp >= lastUserWithdrawalTime[msg.sender] + withdrawalCooldown, 
            "Withdrawal cooldown in effect");

        uint256 amount = request.amount;
        deposits[msg.sender] = deposits[msg.sender] - amount;
        totalDeposits = totalDeposits - amount;
        request.processed = true;
        lastUserWithdrawalTime[msg.sender] = block.timestamp;

        token.safeTransfer(msg.sender, amount);
        emit WithdrawalProcessed(msg.sender, amount);

        if (deposits[msg.sender] == 0) {
            removeUser(msg.sender);
        }
    }

    function createManualSnapshot() public onlyOwner {
        uint256 currentTime = block.timestamp;
        
        if (depositSnapshots.length > 0) {
            require(currentTime > depositSnapshots[depositSnapshots.length - 1].timestamp, 
                "Snapshot timestamp must be in order");
        }
        
        if (depositSnapshots.length >= 100) {
            for (uint256 i = 0; i < depositSnapshots.length - 1; i++) {
                depositSnapshots[i] = depositSnapshots[i + 1];
            }
            depositSnapshots.pop();
        }
        
        depositSnapshots.push(DepositSnapshot(currentTime, totalDeposits));
    }

    function emergencyPause(string memory reason) public onlyPauser {
        paused = true;
        emit EmergencyPaused(msg.sender, reason);
    }

    function emergencyUnpause() public onlyPauser {
        paused = false;
        emit EmergencyUnpaused(msg.sender);
    }

    function setWithdrawalFreezePeriod(uint256 newPeriod) public onlyOwner {
        require(newPeriod >= 1 hours, "Freeze period too short");
        require(newPeriod <= MAX_FREEZE_PERIOD, "Freeze period too long");
        withdrawalFreezePeriod = newPeriod;
        emit ParameterUpdated("WithdrawalFreezePeriod", newPeriod);
    }

    function setWithdrawalCooldown(uint256 newCooldown) public onlyOwner {
        require(newCooldown >= 1 hours, "Cooldown too short");
        withdrawalCooldown = newCooldown;
        emit ParameterUpdated("WithdrawalCooldown", newCooldown);
    }

    function setMinDeposit(uint256 newMin) public onlyOwner {
        require(newMin > 0, "Min deposit must be greater than 0");
        require(newMin <= maxDeposit, "Min deposit must be <= max deposit");
        minDeposit = newMin;
        emit ParameterUpdated("MinDeposit", newMin);
    }

    function setMaxDeposit(uint256 newMax) public onlyOwner {
        require(newMax >= minDeposit, "Max deposit must be >= min deposit");
        require(newMax <= MAX_DEPOSIT_LIMIT, "Max deposit too large");
        maxDeposit = newMax;
        emit ParameterUpdated("MaxDeposit", newMax);
    }

    function setCommissionRate(uint256 newRate) public onlyOwner {
        require(newRate <= 100, "Commission rate must be <= 100");
        require(newRate >= 0, "Commission rate must be >= 0");
        commissionRate = newRate;
        emit ParameterUpdated("CommissionRate", newRate);
    }

    function setInvestor(address newInvestor) public onlyOwner {
        require(newInvestor != address(0), "Invalid investor address");
        address oldInvestor = investor;
        investor = newInvestor;
        emit RoleUpdated("Investor", oldInvestor, false);
        emit RoleUpdated("Investor", newInvestor, true);
    }

    function setPauser(address newPauser) public onlyOwner {
        require(newPauser != address(0), "Invalid pauser address");
        address oldPauser = pauser;
        pauser = newPauser;
        emit RoleUpdated("Pauser", oldPauser, false);
        emit RoleUpdated("Pauser", newPauser, true);
    }

    function getOwner() public view returns (address) { return owner; }
    
    function getPauser() public view returns (address) { return pauser; }
    
    function getInvestor() public view returns (address) { return investor; }
    
    function getToken() public view returns (address) { return address(token); }
    
    function getMinDeposit() public view returns (uint256) { return minDeposit; }
    
    function getMaxDeposit() public view returns (uint256) { return maxDeposit; }
    
    function getWithdrawalCooldown() public view returns (uint256) { return withdrawalCooldown; }
    
    function getWithdrawalFreezePeriod() public view returns (uint256) { return withdrawalFreezePeriod; }
    
    function getVersion() public pure returns (string memory) { return VERSION; }
    
    function getNAME() public pure returns (string memory) { return NAME; }
    
    function getUserDeposit(address user) public view returns (uint256) { return deposits[user]; }
    
    function getTotalDeposits() public view returns (uint256) { return totalDeposits; }
    
    function getLastProfitDistributionTime() public view returns (uint256) { return lastProfitDistributionTime; }
    
    function getContractBalance() public view returns (uint256) { return token.balanceOf(address(this)); }

    function getWithdrawalRequest(address user, uint256 index)
        public
        view
        returns (uint256 amount, uint256 unlockTime, bool processed)
    {
        require(index < withdrawalRequests[user].length, "Invalid index");
        WithdrawalRequest memory request = withdrawalRequests[user][index];
        return (request.amount, request.unlockTime, request.processed);
    }

    function getUserWithdrawalRequestCount(address user) public view returns (uint256) {
        return withdrawalRequests[user].length;
    }

    function getRecentWithdrawalRequestCount(uint256 howManyDays) public view returns (uint256) {
        uint256 startTime = block.timestamp - (howManyDays * 1 days);
        uint256 totalCount = 0;

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            for (uint256 j = 0; j < withdrawalRequests[user].length; j++) {
                if (withdrawalRequests[user][j].unlockTime >= startTime) {
                    totalCount = totalCount + 1;
                }
            }
        }
        return totalCount;
    }

    function getAnnualReturnRate() public view returns (uint256) {
        if (depositSnapshots.length == 0 || totalDeposits == 0) return 0;

        uint256 oneYearAgo = block.timestamp - 365 days;
        uint256 annualProfit = 0;
        uint256 weightedDeposits = 0;
        uint256 totalTime = 0;

        for (uint256 i = depositSnapshots.length - 1; i >= 0; i--) {
            if (depositSnapshots[i].timestamp < oneYearAgo) break;
            if (i == 0 || depositSnapshots[i-1].timestamp < oneYearAgo) {
                uint256 timeDiff = block.timestamp - depositSnapshots[i].timestamp;
                weightedDeposits = weightedDeposits + (depositSnapshots[i].totalDeposits * timeDiff);
                totalTime = totalTime + timeDiff;
            } else {
                uint256 timeDiff = depositSnapshots[i].timestamp - depositSnapshots[i-1].timestamp;
                weightedDeposits = weightedDeposits + (depositSnapshots[i].totalDeposits * timeDiff);
                totalTime = totalTime + timeDiff;
            }
        }

        uint256 averageDeposits = weightedDeposits / totalTime;
        if (averageDeposits == 0) return 0;

        for (uint256 i = profitHistory.length - 1; i >= 0; i--) {
            if (profitHistory[i].timestamp < oneYearAgo) break;
            annualProfit = annualProfit + profitHistory[i].profit;
        }

        return (annualProfit * 100) / averageDeposits;
    }

    function removeUser(address user) internal {
        for (uint256 i = 0; i < users.length; i++) {
            if (users[i] == user) {
                users[i] = users[users.length - 1];
                users.pop();
                userExists[user] = false;
                break;
            }
        }
    }
}