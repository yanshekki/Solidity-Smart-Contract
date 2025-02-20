# Investment Contract

A secure and flexible Solidity smart contract for managing token investments with features for deposits, withdrawals, profit distribution, and administrative controls.

## Version
1.0.0

## Overview

The Investment Contract is a sophisticated smart contract built on Ethereum that enables:
- Token deposits and withdrawals with configurable limits
- Profit distribution system with commission rates
- Withdrawal request system with cooldown and freeze periods
- Emergency pause functionality
- Comprehensive tracking of profits and deposits
- Role-based access control

## Features

### Core Functionality
- **Deposit Management**: Users can deposit tokens within configured minimum and maximum limits
- **Withdrawal System**: Two-step withdrawal process with freeze period and cooldown
- **Profit Distribution**: Automated profit distribution with configurable commission rates
- **Investment Management**: Authorized investor can withdraw funds for investment purposes
- **Snapshot System**: Maintains historical records of deposits and profits

### Security Features
- Reentrancy protection using OpenZeppelin's ReentrancyGuard
- Role-based access control for administrative functions
- Emergency pause functionality
- SafeERC20 implementation for token transfers
- Comprehensive input validation

### Administrative Controls
- Configurable deposit limits
- Adjustable withdrawal freeze periods and cooldowns
- Updatable commission rates
- Role management (Owner, Investor, Pauser)

## Contract Parameters

### Immutable Parameters
- `MAX_DEPOSIT_LIMIT`: Maximum possible deposit limit
- `MAX_FREEZE_PERIOD`: Maximum possible freeze period

### Configurable Parameters
- `minDeposit`: Minimum amount required for deposits
- `maxDeposit`: Maximum amount allowed for deposits
- `withdrawalCooldown`: Time required between withdrawals
- `withdrawalFreezePeriod`: Lock period for withdrawal requests
- `commissionRate`: Percentage of profit taken as commission

## Role System

### Owner
- Can update contract parameters
- Can assign new roles
- Can create manual snapshots

### Investor
- Can withdraw funds for investment
- Can distribute profits

### Pauser
- Can pause and unpause the contract in emergencies

## Events

The contract emits the following events:
- `Deposit`: When a user makes a deposit
- `ProfitDistributed`: When profits are distributed
- `WithdrawalRequested`: When a withdrawal is requested
- `WithdrawalProcessed`: When a withdrawal is completed
- `InvestmentWithdrawn`: When the investor withdraws funds
- `EmergencyPaused`: When the contract is paused
- `EmergencyUnpaused`: When the contract is unpaused
- `ParameterUpdated`: When contract parameters are modified
- `RoleUpdated`: When role assignments change

## Usage

### For Users

1. **Making Deposits**
```solidity
function deposit(uint256 amount) public
```

2. **Requesting Withdrawals**
```solidity
function requestWithdrawal(uint256 amount) public
```

3. **Processing Withdrawals**
```solidity
function withdrawShare(uint256 index) public
```

### For Administrators

1. **Setting Parameters**
```solidity
function setWithdrawalFreezePeriod(uint256 newPeriod) public onlyOwner
function setWithdrawalCooldown(uint256 newCooldown) public onlyOwner
function setMinDeposit(uint256 newMin) public onlyOwner
function setMaxDeposit(uint256 newMax) public onlyOwner
function setCommissionRate(uint256 newRate) public onlyOwner
```

2. **Managing Roles**
```solidity
function setInvestor(address newInvestor) public onlyOwner
function setPauser(address newPauser) public onlyOwner
```

3. **Emergency Controls**
```solidity
function emergencyPause(string memory reason) public onlyPauser
function emergencyUnpause() public onlyPauser
```

## Analytics and Reporting

The contract provides various view functions for monitoring:
- `getAnnualReturnRate()`: Calculate annual return rate
- `getRecentWithdrawalRequestCount()`: Track recent withdrawal requests
- `getContractBalance()`: Check current token balance
- `getTotalDeposits()`: View total deposits
- Various getter functions for contract parameters and state

## Dependencies

- OpenZeppelin Contracts v4.x
  - `@openzeppelin/contracts/token/ERC20/IERC20.sol`
  - `@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol`
  - `@openzeppelin/contracts/utils/ReentrancyGuard.sol`

## Setup and Deployment

To deploy the contract, you need to provide the following parameters:
1. Token address
2. Minimum deposit amount
3. Maximum deposit amount
4. Withdrawal cooldown period
5. Withdrawal freeze period
6. Owner address
7. Pauser address
8. Investor address
9. Maximum deposit limit
10. Maximum freeze period
11. Commission rate

## Security Considerations

1. The contract implements reentrancy protection for sensitive functions
2. Role-based access control prevents unauthorized actions
3. Emergency pause functionality for crisis management
4. SafeERC20 implementation for secure token transfers
5. Input validation on all parameters
6. Withdrawal requests have mandatory freeze periods
7. Cooldown periods between withdrawals

## License

MIT License