# Lending Pool Smart Contract
This smart contract is a decentralized lending pool implemented in Clarity, designed for users to deposit STX tokens, borrow against their deposits, and repay their loans. The contract enforces collateralization rules to ensure the safety of funds and supports administrative controls for management.

## Features
Depositing and Withdrawing: Users can deposit STX into the contract to earn interest and withdraw as long as collateral rules are satisfied.
Borrowing and Repayment: Users can borrow STX against their deposits, subject to a minimum collateralization ratio, and repay their loans.
Collateralization Enforcement: Ensures that users maintain at least a 150% collateralization ratio (configurable by the contract owner).
Interest Accrual: Loans accrue interest based on an annual interest rate, which is configurable by the contract owner.

Administrative Controls:
Pause or unpause the contract.
Update collateralization ratio.
Update the interest rate.
Contract Constants
CONTRACT_OWNER: The address that deploys the contract.
ERR_UNAUTHORIZED: Error code for unauthorized access (u100).
ERR_INSUFFICIENT_BALANCE: Error code for insufficient user balance (u101).
ERR_INSUFFICIENT_COLLATERAL: Error code for insufficient collateralization ratio (u102).
ERR_INVALID_AMOUNT: Error code for invalid deposit or withdrawal amount (u103).
ERR_PAUSED: Error code when the contract is paused (u104).
Data Variables
Global Variables
min-collateral-ratio: The minimum collateralization ratio required (default: 150%).
interest-rate: The annual interest rate for borrowing (default: 5%).
total-deposits: Total STX deposited in the contract.
total-borrows: Total STX borrowed from the contract.
paused: Boolean indicating whether the contract is paused.
User-Specific Variables (Maps)
user-deposits: Tracks each user's deposit amount and the block height of their last update.
user-borrows: Tracks each user's borrow amount and the block height of their last update.
Functions
Public Functions
Deposit

Function: (deposit (amount uint))
Allows a user to deposit STX into the lending pool.
Requirements:
Contract must not be paused.
amount must be greater than 0.
Events: Triggers a deposit-event.
Withdraw

Function: (withdraw (amount uint))
Allows a user to withdraw STX, ensuring collateralization requirements are met.
Requirements:
Contract must not be paused.
amount must be greater than 0.
User must have sufficient deposited balance.
Withdrawal must not breach the collateralization ratio.
Events: Triggers a withdraw-event.
Borrow

Function: (borrow (amount uint))
Allows a user to borrow STX against their deposited collateral.
Requirements:
Contract must not be paused.
amount must be greater than 0.
Borrowing must satisfy collateralization rules.
Events: Triggers a borrow-event.
Repay

Function: (repay (amount uint))
Allows a user to repay their outstanding loan.
Requirements:
Contract must not be paused.
amount must be greater than 0.
User must have sufficient borrow balance.
Events: Triggers a repay-event.
Admin Functions

set-collateral-ratio: Updates the minimum collateralization ratio.
set-interest-rate: Updates the annual interest rate.
toggle-pause: Toggles the paused state of the contract.
Read-Only Functions
Get User Balances

get-deposit: Fetches the deposit amount for a user.
get-borrow: Fetches the borrow amount for a user.
Get Global Balances

get-total-deposits: Fetches the total STX deposited in the contract.
get-total-borrows: Fetches the total STX borrowed from the contract.
Collateral Ratio Check

check-collateral-ratio: Validates if a user's collateralization ratio is sufficient.
Interest Calculation

calculate-interest: (Private) Calculates interest on the loan based on the principal and number of blocks elapsed.
Events
Deposit Event: Triggered on successful deposits.
Withdraw Event: Triggered on successful withdrawals.
Borrow Event: Triggered on successful borrows.
Repay Event: Triggered on successful loan repayments.
Error Codes
u100: Unauthorized access.
u101: Insufficient balance.
u102: Insufficient collateralization ratio.
u103: Invalid deposit or withdrawal amount.
u104: Contract is paused.
u105: Invalid collateralization ratio (outside 100%-500%).
u106: Invalid interest rate (greater than 100%).
How to Deploy and Use
Deploy the Contract:

Ensure the deploying account has sufficient STX for the deployment and initial funding.
Initialize Settings (Admin):

Use set-collateral-ratio and set-interest-rate to configure the contract.
User Operations:

Users can deposit, withdraw, borrow, and repay STX using the respective functions.
Admin Operations:

Use toggle-pause to enable/disable contract operations in case of emergencies.
Testing Scenarios
Successful Deposit and Withdraw:

Deposit STX and withdraw a portion while maintaining sufficient collateral.
Borrowing Against Collateral:

Deposit STX and borrow up to the collateralization limit.
Repayment of Loan:

Borrow STX and repay partially or fully.
Unauthorized Access:

Attempt to change settings or pause the contract with a non-owner account.
Pause State:

Attempt deposits, withdrawals, or borrows while the contract is paused.




