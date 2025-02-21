// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./FlowToken.sol";

contract InvestmentPool is ReentrancyGuard {
    using SafeERC20 for IERC20;

    string public constant VERSION = "1.0.0";
    string public constant NAME = "InvestmentPool";

    address public owner;
    address public pauser;
    address public investor;
    address public immutable creator;
    IERC20 public token;
    FlowToken public flowToken;
    uint256 public totalDeposits;
    uint256 public lastProfitDistributionTime;
    bool public paused = false;
    uint256 public minDeposit;
    uint256 public maxDeposit;
    uint256 public withdrawalCooldown;
    uint256 public withdrawalFreezePeriod;
    uint256 public commissionRate;
    uint256 public MAX_DEPOSIT_LIMIT;
    uint256 public MAX_FREEZE_PERIOD;

    mapping(address => uint256) public lastUserWithdrawalTime;

    event Deposit(address indexed user, uint256 amount, uint256 flowAmount);
    event ProfitDistributed(uint256 totalProfit, uint256 commission, uint256 creatorTax, uint256 timestamp);
    event WithdrawalProcessed(address indexed user, uint256 flowAmount, uint256 amount);
    event InvestmentWithdrawn(address indexed investor, uint256 amount, string protocol);
    event EmergencyPaused(address indexed pauser, string reason);
    event EmergencyUnpaused(address indexed pauser);
    event ParameterUpdated(string parameter, uint256 newValue);
    event RoleUpdated(string role, address member, bool granted);

    constructor(
        address _tokenAddress,
        address _flowTokenAddress,
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
        require(_flowTokenAddress != address(0), "Invalid flow token address");
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
        flowToken = FlowToken(_flowTokenAddress);
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
        uint256 flowAmount = calculateFlowAmount(amount);
        flowToken.mint(msg.sender, flowAmount);
        totalDeposits = totalDeposits + amount;

        emit Deposit(msg.sender, amount, flowAmount);
    }

    function calculateFlowAmount(uint256 amount) internal view returns (uint256) {
        if (totalDeposits == 0) {
            return amount;
        }
        uint256 totalFlow = flowToken.totalSupply();
        return (amount * totalFlow) / totalDeposits;
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

        uint256 commission;
        uint256 creatorTax;
        uint256 profitToDistribute;

        if (profit > 0) {
            uint256 uProfit = uint256(profit);
            require(token.balanceOf(address(this)) >= uProfit, "Insufficient contract balance");

            commission = uProfit * commissionRate / 100;
            creatorTax = uProfit * 1 / 100;
            profitToDistribute = uProfit - commission - creatorTax;

            flowToken.mint(owner, calculateFlowAmount(commission));
            flowToken.mint(creator, calculateFlowAmount(creatorTax));
            totalDeposits = totalDeposits + profitToDistribute;
        } else {
            uint256 loss = uint256(-profit);
            require(totalDeposits >= loss, "Insufficient total deposits for loss");
            totalDeposits = totalDeposits - loss;
        }

        lastProfitDistributionTime = block.timestamp;
        emit ProfitDistributed(uint256(profit), commission, creatorTax, block.timestamp);
    }

    function withdraw(uint256 flowAmount) public whenNotPaused nonReentrant {
        require(flowAmount > 0, "Withdraw amount must be greater than 0");
        require(flowToken.balanceOf(msg.sender) >= flowAmount, "Insufficient flow token balance");
        require(block.timestamp >= lastUserWithdrawalTime[msg.sender] + withdrawalCooldown, 
            "Withdrawal cooldown in effect");

        uint256 amount = calculateTokenAmount(flowAmount);
        require(amount <= token.balanceOf(address(this)), "Insufficient contract balance");

        flowToken.burn(msg.sender, flowAmount);
        totalDeposits = totalDeposits - amount;
        lastUserWithdrawalTime[msg.sender] = block.timestamp;

        token.safeTransfer(msg.sender, amount);
        emit WithdrawalProcessed(msg.sender, flowAmount, amount);
    }

    function calculateTokenAmount(uint256 flowAmount) internal view returns (uint256) {
        uint256 totalFlow = flowToken.totalSupply();
        if (totalFlow == 0) {
            return 0;
        }
        return (flowAmount * totalDeposits) / totalFlow;
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

    function getContractBalance() public view returns (uint256) {
        return token.balanceOf(address(this));
    }

    function getUserFlowBalance(address user) public view returns (uint256) {
        return flowToken.balanceOf(user);
    }

    function getTotalFlowSupply() public view returns (uint256) {
        return flowToken.totalSupply();
    }
}