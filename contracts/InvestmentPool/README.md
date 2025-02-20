# Investment Pool System

A sophisticated DeFi investment system consisting of two main contracts: InvestmentPool and FlowToken. This system enables efficient token investment management with proportional share tracking using flow tokens.

## Version
1.0.0

## System Overview

The Investment Pool System consists of two main components:

1. **FlowToken Contract**: An ERC20 token that represents proportional shares in the investment pool
2. **InvestmentPool Contract**: The main contract managing deposits, withdrawals, and profit distribution

## Components

### FlowToken Contract

A standard ERC20 token with minting and burning capabilities:

- Implements OpenZeppelin's ERC20 and Ownable standards
- Only owner (InvestmentPool) can mint and burn tokens
- Represents proportional shares in the investment pool

#### Features
- Minting new tokens
- Burning existing tokens
- Ownership management
- Standard ERC20 functionality

### InvestmentPool Contract

The main investment management contract that:
- Accepts deposits in the base token
- Issues FlowTokens representing shares
- Manages withdrawals and profit distribution
- Provides administrative controls

#### Key Features

1. **Deposit System**
   - Users deposit base tokens and receive FlowTokens
   - Proportional share calculation based on total deposits
   - Configurable minimum and maximum deposit limits

2. **Withdrawal System**
   - Users can withdraw by burning FlowTokens
   - Cooldown period between withdrawals
   - Automatic share calculation based on current pool state

3. **Profit Distribution**
   - Investor can distribute profits
   - Automatic commission calculation
   - Proportional distribution through FlowToken mechanics

4. **Security Features**
   - Reentrancy protection
   - Role-based access control
   - Emergency pause functionality
   - SafeERC20 implementation

## Role System

### Owner
- Can update contract parameters
- Can assign new roles
- Controls FlowToken contract

### Investor
- Can withdraw funds for investment
- Can distribute profits

### Pauser
- Can pause and unpause the contract in emergencies

## Events

### FlowToken Events
- Standard ERC20 transfer events
- Ownership transfer events

### InvestmentPool Events
- `Deposit`: When a user deposits tokens
- `ProfitDistributed`: When profits are distributed
- `WithdrawalProcessed`: When a withdrawal is completed
- `InvestmentWithdrawn`: When the investor withdraws funds
- `EmergencyPaused/Unpaused`: Contract pause status changes
- `ParameterUpdated`: Contract parameter updates
- `RoleUpdated`: Role assignment changes

## Usage

### For Users

1. **Depositing Funds**
```solidity
function deposit(uint256 amount) public
```

2. **Withdrawing Funds**
```solidity
function withdraw(uint256 flowAmount) public
```

### For Administrators

1. **Setting Parameters**
```solidity
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

## Setup and Deployment

### Deployment Order
1. Deploy FlowToken contract
2. Deploy InvestmentPool contract with FlowToken address

### Required Parameters
1. Base token address
2. FlowToken address
3. Minimum deposit amount
4. Maximum deposit amount
5. Withdrawal cooldown period
6. Withdrawal freeze period
7. Owner address
8. Pauser address
9. Investor address
10. Maximum deposit limit
11. Maximum freeze period
12. Commission rate

## Mathematical Model

### Share Calculation
- Flow tokens are minted proportionally to deposits
- Withdrawal amounts are calculated based on current pool state
```
flowAmount = (depositAmount * totalFlowSupply) / totalDeposits
withdrawAmount = (flowAmount * totalDeposits) / totalFlowSupply
```

## Security Considerations

1. **Access Control**
   - Role-based permissions
   - Owner controls for critical functions
   - Pauser for emergency situations

2. **Economic Security**
   - Deposit limits
   - Withdrawal cooldowns
   - Commission rate limits

3. **Technical Security**
   - Reentrancy protection
   - SafeERC20 usage
   - Overflow protection
   - Input validation

## Monitoring

The contract provides various view functions:
- `getContractBalance()`: Current token balance
- `getUserFlowBalance()`: User's flow token balance
- `getTotalFlowSupply()`: Total flow tokens in circulation

## Dependencies

- OpenZeppelin Contracts v4.x
  - ERC20
  - Ownable
  - ReentrancyGuard
  - SafeERC20

## License

MIT License