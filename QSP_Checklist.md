# Quantstamp Audit Report Progress Checklist

# QSP-1 Stealing User and Contract Funds
## Description
Some funds-transferring functions in the contracts are declared as public or external but without any authorization checks, allowing anyone to arbitrarily call the functions and transfer funds.

### 1.)
#### Issue
The visibility of the safeTransferETH() function in several contracts is public. The visibility allows anyone to call this function to transfer the ETH on the contract to any address directly. The following is the list of affected contracts: LimitOrderRouter.sol, SwapRouter.sol, TaxedTokenLimitOrderExecution.sol,TokenToTokenLimitOrderExecution.sol, TokenToWethLimitOrderExecution.sol.

#### Resolution

### 2.)
#### Issue
In the SwapRouter contract, several transferXXX() functions allow anyone to call and direct transfer the funds away. The following is the list of functions: transferTokensToContract(), transferTokensOutToOwner(), and transferBeaconReward().
 
#### Resolution

### 3.)
#### Issue
The SwapRouter.uniswapV3SwapCallback() function does not verify that it is called from the Uniswap V3 contract, allowing anyone to steal funds by supplying fake inputs.

#### Resolution