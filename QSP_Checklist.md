 
# QSP-1 Stealing User and Contract Funds
## Description
Some funds-transferring functions in the contracts are declared as public or external but without any authorization checks, allowing anyone to arbitrarily call the functions and transfer funds.

## QSP-1_1
The visibility of the `safeTransferETH()` function in several contracts is public. The visibility allows anyone to call this function to transfer the ETH on the contract to any address directly. The following is the list of affected contracts: `LimitOrderRouter.sol`, `SwapRouter.sol`, `TaxedTokenLimitOrderExecution.sol`,`TokenToTokenLimitOrderExecution.sol`, `TokenToWethLimitOrderExecution.sol`.

### Resolution Details

## QSP-1_2
In the SwapRouter contract, several `transferXXX()` functions allow anyone to call and direct transfer the funds away. The following is the list of functions: `transferTokensToContract()`, `transferTokensOutToOwner()`, and `transferBeaconReward()`.
 
### Resolution Details

## QSP-1_3
The `SwapRouter.uniswapV3SwapCallback()` function does not verify that it is called from the Uniswap V3 contract, allowing anyone to steal funds by supplying fake inputs.

### Resolution Details

# QSP-2 Missing Authorization for Execution Contracts
## Description
Several functions are missing authorization validation and allow anyone to call the function instead of the specific callers. Specifically, the "execution" contracts are designed to be triggered by the `LimitOrderRouter` contract. However, those functions do not verify the caller. If anyone calls those functions on the "execution" contract, it will trigger the order execution without updating the order status as fulfilled.

## QSP-2_1
`TaxedTokenLimitOrderExecution.executeTokenToWethTaxedOrders()`

### Resolution Details

## QSP-2_2
`TaxedTokenLimitOrderExecution.executeTokenToTokenTaxedOrders()`
 
### Resolution Details

## QSP-2_3
`TokenToTokenLimitOrderExecution.executeTokenToTokenOrders()`

### Resolution Details

## QSP-2_4
`TokenToTokenLimitOrderExecution.executeTokenToTokenOrderSingle()`

### Resolution Details

## QSP-2_5
`TokenToWethLimitOrderExecution.executeTokenToWethOrders()`

### Resolution Details

## QSP-2_6
`TokenToWethLimitOrderExecution.executeTokenToWethOrderSingle()`

### Resolution Details


## QSP-18

File(s) affected: TokenToWethLimitOrderExecution.sol

Description: In TokenToWethLimitOrderExecution.sol#L365, getAllPrices() is using the first order's order.feeIn to compute uniswap prices for all of the orders in the batch.

However, different orders are not guaranteed to have the same feeIn. Thus, the computed result may not apply to all orders in the batch.

Recommendation: Change the logic to use each individual order's feeIn or check that they all have the same feeIn value, e.g. in LimitOrderRouter._validateOrderSequencing().

### Resolution Details

Updated _validateOrderSequencing() to check for congruent `feeIn` and `feeOut`. Added tests `testFailValidateOrderSequence_IncongruentFeeIn` and  `testFailValidateOrderSequence_IncongruentFeeOut`.