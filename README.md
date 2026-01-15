# 📊 STX Options Contract

A decentralized options trading platform on Stacks that enables users to create and trade call and put options on STX with oracle-based settlement.

## 🎯 What It Does

This smart contract implements a complete options trading system where users can:

- **Buy Call Options** 📈 - Bet that STX price will go up
- **Buy Put Options** 📉 - Bet that STX price will go down
- **Exercise Options** 💰 - Settle options at expiry based on oracle price
- **Transfer Options** 🔄 - Trade options before expiry

## 🔑 Core Concepts

### Call Option
A call option gives you the right to profit when STX price rises above your strike price. If STX is trading at 2.00 and you bought a call with strike 1.50, you profit 0.50 per unit.

### Put Option
A put option gives you the right to profit when STX price falls below your strike price. If STX is trading at 1.00 and you bought a put with strike 1.50, you profit 0.50 per unit.

### Strike Price
The price at which you're betting STX will be above (call) or below (put) at expiry.

### Premium
The upfront cost you pay to create the option position.

### Expiry
The block height at which the option can be exercised and settled.

## 🚀 Usage

### Creating a Call Option

```clarity
(contract-call? .options-contract create-call-option u1500000 u50000 u100000)
```

Parameters:
- `strike-price`: Strike price in micro-STX (1.5 STX = u1500000)
- `premium`: Premium paid in micro-STX
- `expiry-block`: Block height when option expires

### Creating a Put Option

```clarity
(contract-call? .options-contract create-put-option u1000000 u50000 u100000)
```

Same parameters as call options.

### Setting Oracle Price (Owner Only)

```clarity
(contract-call? .options-contract set-oracle-price u1200000)
```

This sets the current market price of STX that will be used for settlement.

### Exercising an Option

```clarity
(contract-call? .options-contract exercise-option u0)
```

Settles your option after expiry. Payout is automatically calculated and transferred.

### Transferring an Option

```clarity
(contract-call? .options-contract transfer-option u0 'SP2J6ZY48GV1EZ5V2V5RB9MP66SW86PYKKNRV9EJ7)
```

Transfer your option to another user before expiry.

### Reading Option Data

```clarity
(contract-call? .options-contract get-option u0)
```

Returns all information about an option including owner, type, strike, premium, expiry, and settlement status.

### Checking Oracle Price

```clarity
(contract-call? .options-contract get-oracle-price)
```

Returns the current oracle price and timestamp.

## 💡 Example Scenario

1. Alice creates a call option with strike 1.5 STX, paying 0.05 STX premium, expiring at block 100,000
2. Time passes and block 100,000 arrives
3. Contract owner updates oracle price to 2.0 STX
4. Alice exercises her option
5. Payout calculated: 2.0 - 1.5 = 0.5 STX profit
6. Alice receives 0.5 STX automatically

## 📝 Contract Functions

### Public Functions

- `create-call-option` - Create a new call option position
- `create-put-option` - Create a new put option position  
- `exercise-option` - Settle and claim payout from expired option
- `transfer-option` - Transfer option ownership before expiry
- `set-oracle-price` - Update market price (owner only)

### Read-Only Functions

- `get-option` - Retrieve option details by ID
- `get-oracle-price` - Get current oracle price and timestamp
- `get-option-nonce` - Get next option ID

## ⚙️ Technical Details

- Options are identified by unique incrementing IDs
- Premiums are held in contract until exercise
- Payouts are calculated automatically based on oracle price
- Options can only be exercised after expiry
- Exercised options cannot be exercised again
- Unexercised options expire worthless

## 🔒 Security Features

- Owner-only oracle price updates
- Option ownership verification
- Expiry enforcement
- Double-exercise prevention
- Premium payment verification

## 🏗️ Development

Built with Clarinet for the Stacks blockchain.

### Testing

Deploy to testnet and interact using Clarinet console or Stacks explorer.

### Deployment

```bash
clarinet integrate
```

## 📄 License

MIT