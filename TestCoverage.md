

# Conveyor Limit Orders

## onlyEOA

## creditBalance
- read
- write
- delete

## Events
- emit deposit gas credit event 
- emit withdraw gas credit event


## depositCredits
- success
- fail: balance < msg.value branch

## withdrawGasCredits
- success
- fail: credit balance < _value
- fail: gas min gas credits

## executeOrders
- success: one token to weth order
- success: multiple token to weth orders
- success: one token to token order
- success: multiple token to tokens orders
- fail: nonEOA

## _executeTokenToWethOrders
- success: one token to weth order
- success: multiple token to weth orders

## _executeTokenToWethBatchOrders
- success: one token to weth order
- success: multiple token to weth orders

## _executeTokenToWethBatch

## _initializeTokenToWethExecutionPrices

## _initializeNewTokenToWethBatchOrder

## _batchTokenToWethOrders
- succcess
- test currentBestPriceIndex != bestPriceIndex branch
- test _orderMeetsExecutionPrice branch
- test !_orderMeetsExecutionPrice branch
- test _orderCanExecute branch
- test !_orderCanExecute branch

## _findBestTokenToWethExecutionPrice



## _executeTokenToTokenOrders
- success: one token to weth order
- success: multiple token to weth orders

## _executeTokenToTokenBatchOrders
- success: one token to weth order
- success: multiple token to weth orders

## _executeTokenToTokenBatch

## _initializeTokenToTokenExecutionPrices

## _calculateTokenToWethToTokenSpotPrice

## _initializeNewTokenToTokenBatchOrder

## _batchTokenToTokenOrders
- succcess
- test currentBestPriceIndex != bestPriceIndex branch
- test _orderMeetsExecutionPrice branch
- test !_orderMeetsExecutionPrice branch
- test _orderCanExecute branch
- test !_orderCanExecute branch

## _findBestTokenToWethExecutionPrice


## _validateOrderSequencing
- success
- fail: invalid batch ordering
- fail: incongruent token group (token in)
- fail: incongruent token group (token out)


## simulateTokenToWethPriceChange

## simulateTokenToTokenPriceChange

## simulateAToBPriceChange
- success
- fail: overflow?

## _orderMeetsExecutionPrice
- success: buyOrder
- success: !buyOrder

## _orderCanExecute

<br>

# GasOracle

## getGasPrice


<br>

# OrderBook


## Events
- emit order placed event
- emit order cancelled event
- emit order updated event

## getOrderById
- order exists
- order does not exist

## placeOrder
- success
- fail: incongruent tokenIn Order Group
- fail: insufficient wallet balance

## updateOrder
- success
- fail: order does not exist

## cancelOrder
- success
- fail: order does not exist

## cancelOrders
- success
- fail: order does not exist

## getTotalOrdersValue

## calculateMinGasCredits

## _hasMinGasCredits
- true
- false

<br>

# OrderRouter

## _calculateFee
- success
- fail: overflow error

## _calculateReward


## _calculateMaxBeaconReward

## _calculateAlphaX

## addDex
- success
- fail invalid input

## _swap
- success univ2
- success univ3

## _swapV2
- success
- fail: insufficient output amount

## _swapV3
- success
- fail: insufficient output amount

## _calculateV2SpotPrice
 - Success: fork specific block
 - Fail: fork specific block
## _calculateV3SpotPrice
- success: Fork specific block
- fail: Fork specific block
## _lpIsUniV2

## _getUniV3Fee
- success case
- fail case
## getTick

## _getAllPrices

## _getTargetAmountIn

## _convertToCommonBase

## _getTargetDecimals

## _sortTokens

## _getQuoteAtTick