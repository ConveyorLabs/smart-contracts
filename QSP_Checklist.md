
# QSP Resolution
The following sections detail the findings from the initial QSP report and the resolutions for each issue.

## QSP-1 Stealing User and Contract Funds ✅
Severity: 🔴**High Risk**🔴
## Description
Some funds-transferring functions in the contracts are declared as public or external but without any authorization checks, allowing anyone to arbitrarily call the functions and transfer funds.

### QSP-1_1
The visibility of the `safeTransferETH()` function in several contracts is public. The visibility allows anyone to call this function to transfer the ETH on the contract to any address directly. The following is the list of affected contracts: `LimitOrderRouter.sol`, `SwapRouter.sol`, `TaxedTokenLimitOrderExecution.sol`,`TokenToTokenLimitOrderExecution.sol`, `TokenToWethLimitOrderExecution.sol`.

### Resolution
The `safeTransferETH()` function visibility was changed to internal for all contracts affected. 
- OrderBook.sol#L263
- SwapRouter.sol#L164


### QSP-1_2
In the SwapRouter contract, several `transferXXX()` functions allow anyone to call and direct transfer the funds away. The following is the list of functions: `transferTokensToContract()`, `_transferTokensOutToOwner()`, and `_transferBeaconReward()`.
 
### Resolution
All `transferXXX()` functions were updated to only be callable by the execution contract.
- ConveyorExecutor.sol#L449
- SwapRouter.sol#L296
- SwapRouter.sol#308


### QSP-1_3
The `SwapRouter.uniswapV3SwapCallback()` function does not verify that it is called from the Uniswap V3 contract, allowing anyone to steal funds by supplying fake inputs.

### Resolution

The Uniswapv3 swap callback now has verification that the caller is a Uniswapv3 pool. First, the pool address is derived by calling the Uniswapv3 Factory. Then the function checks if the msg.sender is the pool address.

```solidity
     address poolAddress = IUniswapV3Factory(uniswapV3Factory).getPool(
            tokenIn,
            tokenOut,
            fee
        );

        if (msg.sender != poolAddress) {
            revert UnauthorizedUniswapV3CallbackCaller();
        }
```

- SwapRouter.sol#L486-541


# QSP-2 Missing Authorization for Execution Contracts ✅
## Description
Several functions are missing authorization validation and allow anyone to call the function instead of the specific callers. Specifically, the "execution" contracts are designed to be triggered by the `LimitOrderRouter` contract. However, those functions do not verify the caller. If anyone calls those functions on the "execution" contract, it will trigger the order execution without updating the order status as fulfilled.

### Resolution
Execution functions were merged into a single execution contract called `ConveyorExector.sol`. Validation was added to each execution function via a modifier called `onlyLimitOrderRouter`.


```solidity
modifier onlyLimitOrderRouter() {
    if (msg.sender != LIMIT_ORDER_ROUTER) {
        revert MsgSenderIsNotLimitOrderRouter();
    }
    _;
}
```

- ConveyorExecutor.sol#L124
- ConveyorExecutor.sol#L284


# QSP-3 Ignoring Return Value of ERC20 Transfer Functions ✅

## Description
Several functions use ERC20's and without checking their return values. Since per the , these functions merely throw, some implementations return on error. This is very dangerous, as transfers might not have been executed while the contract code assumes they did.

### Resolution
SafeERC20 was implemented for ERC20 transfer functions.

- ConveyorExecutor.sol#L452
- SwapRouer.sol#L342
- SwapRouer.sol#L345
- SwapRouer.sol#L537
- SwapRouer.sol#L539


# QSP-4 Cancelling Order Provides Compensation Twice ✅
### Description
After validating that a user does not have sufficient gas credits, the function validateAndCancelOrder() first calls _cancelOrder(), which removes the order from the
system, transfers compensation to the message sender and emits an event. After the call, the function itself sends compensation to the message sender again and emits an
event for the second time.

### Resolution
Duplicate logic to cancel order compensation was removed.

- LimitOrderRouter#L164-179

# QSP-5 Updating an Existing Order Can Be Malicious ✅
### Description

The function updateOrder() allows the order owner to change the old order's parameters. From the code, the owner is allowed to change anything except the member orderID.


### Resolution
The `updateOrder()` function was updated to take a quantity and price, which are now the only fields that are updated instead of replacing the old order. If the user wants to update any other fields, they will have to cancel the order and place a new one. The function now has the following signature:

```solidity
function updateOrder(
    bytes32 orderId, 
    uint128 price, 
    uint128 quantity) public {
   //--snip--   
  }
```

- OrderBook.sol#L434-450


# QSP-6 Same Order Id Can Be Executed Multiple Times ✅
### Description
In the current implementation, if the input orderIds in the function executeOrders() contains duplicate orderIDs, the function will execute the same order more than once.

### Resolution
Logic was added within the `_resolveCompletedOrder()` function to check if the order exists in the orderIdToOrder mapping. Since the orderId gets cleaned up from this mapping after successful execution, if there is a duplicate orderId in the array of orderIds being executed, the orderToOrderId mapping will return 0 for the duplicated orderId, causing a reversion.

```solidity

    function _resolveCompletedOrder(bytes32 orderId) internal {
        ///@notice Grab the order currently in the state of the contract based on the orderId of the order passed.
        Order memory order = orderIdToOrder[orderId];

        ///@notice If the order has already been removed from the contract revert.
        if (order.orderId == bytes32(0)) {
            revert DuplicateOrdersInExecution();
        }
```

- OrderBook.sol#L596-599


# QSP-7 Incorrectly Computing the Best Price ✅
### Description
The function _findBestTokenToWethExecutionPrice() initializes the bestPrice as 0 for buy orders and type(uint256).max for sell orders. For buy orders, the code
checks for each execution price whether that price is less than the current bestPrice and updates the bestPrice and bestPriceIndex accordingly. Since there is no "better" price than 0,
the function will always return the default value of bestPriceIndex, which is 0. Similarly for sell orders, the bestPrice is already the best it can be and will always return 0.

### Resolution
Changed `_findBestTokenToWethExecutionPrice()` to initialize the bestPrice as type(uint256).max for buys and 0 for sells.

- LimitOrderBatcher.sol#L31

# QSP-8 Reentrancy ✅
### Description
A reentrancy vulnerability is a scenario where an attacker can repeatedly call a function from itself, unexpectedly leading to potentially disastrous results. The following are places
that are at risk of reentrancy: `LimitOrderRouter.executeOrders()`, `withdrawConveyorFees()`.


### Resolution

A nonReentrant modifier has been added to `LimitOrderRouter.executeOrders()` and `withdrawConveyorFees()`. 

```solidity


    ///@notice Modifier to restrict reentrancy into a function.
    modifier nonReentrant() {
        if (reentrancyStatus == true) {
            revert Reentrancy();
        }
        reentrancyStatus = true;
        _;
        reentrancyStatus = false;
    }
```

```solidity
 ///@notice This function is called by off-chain executors, passing in an array of orderIds to execute a specific batch of orders.
    /// @param orderIds - Array of orderIds to indicate which orders should be executed.
    function executeOrders(bytes32[] calldata orderIds)
        external
        nonReentrant
        onlyEOA
    {
    //--snip--
```

```solidity

    ///@notice Function to withdraw owner fee's accumulated
    function withdrawConveyorFees() external nonReentrant onlyOwner {
        ///@notice Unwrap the the conveyorBalance.
        IWETH(WETH).withdraw(conveyorBalance);

        uint256 withdrawAmount = conveyorBalance;
        ///@notice Set the conveyorBalance to 0 prior to transferring the ETH.
        conveyorBalance = 0;
        _safeTransferETH(owner, withdrawAmount);
    }
   //--snip--     
```

- LimitOrderRouter.sol#284-288
- ConveyorExecutor.sol#493

# QSP-9 Not Cancelling Order as Expected ✅

## QSP-9_1

### Description
Both the `LimitOrderBatcher.batchTokenToTokenOrders()` and the `LimitOrderBatcher._batchTokenToWethOrders()` functions state that "If the transfer fails, cancel the order" (L124 and L278). However, the implementation does not handle the failed transfer for the call of `IOrderRouter(orderRouter).transferTokensToContract()`. Moreover, since the implementation of the `SwapRouter.transferTokensToContract()` function ignores the return value of `IERC20(order.tokenIn).transferFrom()`, it is possible that the transfer failed silently without reverting the transaction, causing the execution to proceed without a token transfer.

### Resolution
This function no longer exists, as we have removed batching and updated the system to only use linear execution.



## QSP-9_2
### Description
`LimitOrderRouter.refreshOrder()` states, "Check that the account has enough gas credits to refresh the order; otherwise, cancel the order and continue the loop".
However, on L234-240, the block for the condition `if (gasCreditBalance[order.owner] < REFRESH_FEE)` does not cancel the order.

### Resolution
The conditions to cancel an order in refresh order is that the order has expired, the execution credit balance is less than the refresh fee, the execution `creditBalance - refreshFee` is less than the `minExecutionCredit`, or if the owner's `tokenIn` balance is less than the specified order quantity. All of these conditions now contain logic to cancel an order during refresh.

- LimitOrderRouter.sol#L116
- LimitOrderRouter.sol#L121
- LimitOrderRouter.sol#L124
- LimitOrderRouter.sol#L129


# QSP-10 Granting Insufficient Gas Credit to the Executor ✅

### Description
The `calculateExecutionGasConsumed()` function returns the gas difference of the initialTxGas and the current gas retrieved by the gas() call. The returned value is the gas without multiplying it with the gas price. The `calculateExecutionGasCompensation()` function uses the returned gas value directly to calculate the gasDecrementValue. The gasDecrementValue does not take the gas price into account either. Consequently, the executor will not get enough gas compensation with the current implementation.

### Resolution
We have removed gas credit balances, as well as compensation based on gas price from the oracle. Now, when a user places an order, they will deposit an `executionCredit`, which is now accounted for in the order struct. Upon execution, the off-chain executor will be paid the `executionCredit`. This change was made due to the inconsistency of having a viable gas oracle on every chain.

# QSP-11 Integer Overflow / Underflow ✅
### Description
Description: Integer overflow/underflow occurs when an integer hits its bit-size limit. Every integer has a set range; the value loops back around when that range is passed. A clock is a good
analogy: at 11:59, the minute hand goes to 0, not 60, because 59 is the most significant possible minute.
We noticed that the ConveyorMath library implements changes from the ABDK library and introduced several issues because the overflow protection on the original library would work only on
the signed integers or with 128 bits. The overflow can lead to a miscalculation of the fees and rewards in the SwapRouter contract.

# QSP-11_1
### Description
OrderBook._calculateMinGasCredits()#L480-488: The code uses the unchecked block when calculating the minGasCredits. However, there is no boundary for the
input variables, and the calculation (especially the multiplication on L482-485) can overflow.

### Resolution
This function no longer exists because it is no longer needed.



# QSP-11_2
### Description
ConveyorMath.sub()#L80: The cast int128(MAX_64x64) will always be -1. MAX_64x64 is the constant for uint128 with 128 bits of 1. After casting to int128, the code
will treat it as -1. Judging from the logic, it does not make sense to check require(... && result <= -1).

### Resolution
In ConveyorMath.sub() we changed int128(MAX_64x64) to type(int128).max.

- ConveyorMath.sol#L88


# QSP-11_3
### Description
ConveyorMath.sub64UI()#L86: The line (y << 64) can be over-shifted and lose some bits for y. Also, the calculation result = x - (y << 64) can underflow as y
<<64 can be larger than x, especially since x is of the type uint128 and y is of the type uint256. The line require(result >= 0x0 && uint128(result) <=
uint128(MAX_64x64)) would not help preventing the overflow.

### Resolution
This function is no longer needed and was removed.


# QSP-11_4
### Description
ConveyorMath.add128x128()#L100: The line answer = x + y can overflow. The check require(answer <= MAX_128x128) would not help as the answer will already
have overflowed and always passes the validation.

### Resolution
The unchecked block in ConveyorMath.add128x128() was removed as well as the unnecessary validation require(answer <= MAX_128x128).

- ConveyorMath.sol#L97-101


# QSP-11_5
### Description
ConveyorMath.add128x64()#L112: The line answer = x + (uint256(y) << 64) can overflow. The check require(answer <= MAX_128x128) would not help as the
answer will already have overflowed and always passes the validation

### Resolution
The unchecked block in ConveyorMath.add128x64() was removed as well as the unnecessary validation require(answer <= MAX_128x128).

- ConveyorMath.sol#L107-111


# QSP-11_6
### Description
ConveyorMath.mul128x64()#L139: The line (uint256(y) * x) can overflow since x is of type uint256. The check require(answer <= MAX_128x128) would not help
as the answer will already have overflowed and always passes the validation.

### Resolution
The unchecked block in ConveyorMath.mul128X64() was removed as well as the unnecessary validation require(answer <= MAX_128x128).

- ConveyorMath.sol#L129-136


# QSP-11_7
### Description
ConveyorMath.mul128I()#:177-178: The line (uint256(x) * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) can overflow since x is of type uint256.

### Resolution
The unchecked block was removed and logic was changed to (x*y) >> 128.

- ConveyorMath.sol#L164-170

# QSP-11_8
### Description
ConveyorMath.div128x128()#L224-225: The line hi + lo can overflow.

### Resolution
Changed the validation logic from `hi+lo <= MAX_128x128` to `hi <= MAX_128x128-lo`.

- ConveyorMath.sol#L210


# QSP-11_9
### Description
ConveyorMath.divUU128x128()#L369-385: The require(answer <= MAX_128x128...) check is useless as MAX_128x128 is type(uint256).max so the answer of theuint256 type can never exceed this value. The following lines answer * (y >> 128) and answer * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) can potentially
overflow since answer is not capped. The code is tweaked from the divUU() function. However, it cannot simply do so unless accepting phantom overflow, as the original
function is designed to work with 128 bits calculations with 256 bits buffer. To handle 256 bits calculation requires a full re-implementation. Also, note that final return
value answer << 128 is incorrect. Since most of the implementation is identical with the divUU(), the answer is a 64.64 fixed-point number. The implementation should
shift the answer 64 bits instead of 128 bits to convert a 64.64 value to 128.128 format.

### Resolution
This function was removed as it was no longer needed. Instead of this, we now use `divUU()` in place of the previous function.


# QSP-11_10
### Description
SwapRouter._calculateAlphaX()#L640: The line QuadruplePrecision.fromInt(int256(_k)) casts the _k from uint256 to int256. If _k is larger than or equal to
1<<255, the cast from uint256 to int256 would accidentally treat _k as a negative number.


### Resolution
This function was removed as it was no longer needed. We now have a constant capping the max payout for stop loss orders.


# QSP-12 Updating Order Performs Wrong Total Order Quantity Accounting ✅
### Description
The updateOrders() function first retrieves the value for the oldOrder.tokenIn, then performs adjustments depending on whether the new order has a higher or lower order quantity. The
first issue with the function is that the else branch of the adjustment code is incorrect. If we assume the old value was 100 and the new value is 50, the total will be updated by += 100 - 50,
i.e. an increase by 50 instead of a decrease. While this code path is exercised in a test, the total order value is never checked to be equal to the expected value.
Additionally, the function updates the total order quantity with a call to updateTotalOrdersQuantity(newOrder.tokenIn, ...). Since it is never checked that the tokenIn member of
the old and new order are the same, this could update some completely unrelated token order quantity.

### Resolution
The updated order quantity now calculates the correct value.

```solidity

totalOrdersValue += newQuantity;
totalOrdersValue -= oldOrder.quantity;

```

- OrderBook.Sol#L479-480



# QSP-13 Not Always Taking Beacon Reward Into Account ✅
### Description
In the TaxedTokenLimitOrderExecution and TokenToTokenLimitOrderExecution contracts, the _executeTokenToTokenOrder() functions will always return a zero
amount beaconReward when order.tokenIn != WETH. Note that the function _executeSwapTokenToWethOrder() has the logic for computing beaconReward in it but the
beaconReward value is not returned as part of the function. The _executeTokenToTokenOrder() will need to get the beaconReward value from the
_executeSwapTokenToWethOrder() function.

### Resolution
`_executeSwapTokenToWethOrder()` now returns the `amountOutWeth - conveyorBeaconReward` after the beacon reward is adjusted in the event that it is capped. Further, the execution tests now have assertions validating executor payment after execution has completed.

- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417



# QSP-14 Denial of Service Due to Unbound Iteration ✅
### Description
Description: There is a limit on how much gas a block can execute on the network. It can consume more gas than the network limit when iterating over an unbounded list. In that case, the
transaction will never work and block the service. The following is the list of places that are at risk:

### Resolution
#### QSP_14_1
Modified `getAllOrderIds` to use an `offset`, and `length` parameter to index `addressToAllOrderIds` array from a specified position with a fixed return data `length`.
```solidity
function getOrderIds(
        address owner,
        OrderType targetOrderType,
        uint256 orderOffset,
        uint256 length
    ) public view returns (bytes32[] memory) {
        bytes32[] memory allOrderIds = addressToAllOrderIds[owner];

        uint256 orderIdIndex = 0;
        bytes32[] memory orderIds = new bytes32[](allOrderIds.length);

        uint256 orderOffsetSlot;
        assembly {
            //Adjust the offset slot to be the beginning of the allOrderIds array + 0x20 to get the first order + the order Offset * the size of each order
            orderOffsetSlot := add(
                add(allOrderIds, 0x20),
                mul(orderOffset, 0x20)
            )
        }

        for (uint256 i = 0; i < length; ++i) {
            bytes32 orderId;
            assembly {
                //Get the orderId at the orderOffsetSlot
                orderId := mload(orderOffsetSlot)
                //Update the orderOffsetSlot
                orderOffsetSlot := add(orderOffsetSlot, 0x20)
            }

            OrderType orderType = addressToOrderIds[owner][orderId];

            if (orderType == targetOrderType) {
                orderIds[orderIdIndex] = orderId;
                ++orderIdIndex;
            }
        }

        //Reassign length of each array
        assembly {
            mstore(orderIds, orderIdIndex)
        }

        return orderIds;
    }
```

- OrderBook.sol#L672-719

#### QSP_14_2
The number of `dexes` deployed in the constructor of the `SwapRouter` will never be anywhere from `3-8` depending on the chain. This will be sufficiently small to not exceed the block gas limit in `getAllPrices` when iterating through the dexes.

# QSP-15 Missing Input Validation ✅
### Description
1. OrderBook._resolveCompletedOrder() (L396-410): Check if the order exists or not before removing from storage. This function is used in LimitOrderRouter.executeOrders() (L432-532). However, this function does not check the order existence either.
2. LimitOrderRouter.transferOwnership() (L566-571): The validation on L567 owner == address(0) seems to be mistaken. Should validate that the newOwner is a non-zero address instead of validating the owner.
3. LimitOrderRouter.executeOrders() (L432-532): Check if the order exists for the order ID in the orderIds array. The validation can be added in the loop at L440-446 that sets orders[i] = getOrderById(orderIds[i]). Otherwise, an empty order has a chance to be executed unexpectedly. Additionally, the function should check that orderIds.length is non-zero.
4. SwapRouter.constructor() (L190-208): The first element of the _isUniV2 input must be true as the 0th index DEX needs to be Uniswap V2 compatible due to the implementation of the SwapRouter._calculateFee() function.
5. GasOracle.constructor() does not check if _gasOracleAddress is the zero address.
6. OrderBook.constructor() does not check if _orderRouter is the zero address.
7. LimitOrderRouter.constructor() does not check if any of _weth, _usdc, _tokenToTokenExecutionAddress, _taxedExecutionAddress, _tokenToWethExecutionAddress, _orderRouter are the zero address, and _executionCost is not 0.
8. LimitOrderRouter.depositGasCredits() does not check if msg.value is 0. If msg.value == 0, then the function does nothing.
9. SwapRouter.constructor() does not check if any element in _deploymentByteCodes or _dexFactories is 0.
10. SwapRouter.calculateFee() does not check if amountIn is not 0.
11. LimitOrderBatcher.constructor() does not check weth, quoterAddress, orderRouterAddress are not the zero address.
12. TokenToTokenLimitOrderExecution.constructor(),TaxedTokenLimitOrderExecution.constructor(),TokenToWethLimitOrderExecution.constructor()do not check that _usdc is not 0.


### Resolutions
#### QSP_15_1
 The following has been added to `_removeOrderFromSystem` in both `LimitOrderBook` and `SandboxLimitOrderBook`

```solidity
        ///@notice If the order has already been removed from the contract revert.
        if (order.orderId == bytes32(0)) {
            revert DuplicateOrderIdsInOrderGroup();
        }
```

- OrderBook.sol#L597-599


#### QSP_15_2
```solidity
    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }
        tempOwner = newOwner;
    }
```
- LimitOrderRouter.sol#L372-374


#### QSP_15_3

The following has been added to `executeOrders`
```solidity
 for (uint256 i = 0; i < orderIds.length; ) {
            orders[i] = getLimitOrderById(orderIds[i]);
            if (orders[i].orderId == bytes32(0)) {
                revert OrderDoesNotExist(orderIds[i]);
            }
            unchecked {
                ++i;
            }
        }
```

- LimitOrderRouter.sol#L299-301


#### QSP_15_4
```solidity
constructor(
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) {
        ///@notice Initialize DEXs and other variables
        for (uint256 i = 0; i < _deploymentByteCodes.length; ++i) {
            if (i == 0) {
                require(_isUniV2[i], "First Dex must be uniswap v2");
            }
            require(
                _deploymentByteCodes[i] != bytes32(0) &&
                    _dexFactories[i] != address(0),
                "Zero values in constructor"
            );
            dexes.push(
                Dex({
                    factoryAddress: _dexFactories[i],
                    initBytecode: _deploymentByteCodes[i],
                    isUniV2: _isUniV2[i]
                })
            );

            ///@notice If the dex is a univ3 variant, then set the uniswapV3Factory storage address.
            if (!_isUniV2[i]) {
                uniswapV3Factory = _dexFactories[i];
            }
        }
    }
```
- SwapRouter.sol#L134-158

#### QSP_15_5
The gas oracle was removed as well as all gas credit logic.

#### QSP_15_6
```solidity
    ///@param _limitOrderExecutor The address of the ConveyorExecutor contract.
    ///@param _weth The address of the WETH contract.
    ///@param _usdc The address of the USDC contract.
    ///@param _minExecutionCredit The minimum amount of Conveyor gas credits required to place an order.
    constructor(
        address _limitOrderExecutor,
        address _weth,
        address _usdc,
        uint256 _minExecutionCredit
    ) {
        require(
            _limitOrderExecutor != address(0),
            "limitOrderExecutor address is address(0)"
        );

        require(_minExecutionCredit != 0, "Minimum Execution Credit is 0");

        minExecutionCredit = _minExecutionCredit;
        WETH = _weth;
        USDC = _usdc;
        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
    }
```
- OrderBook.sol#L45-48

#### QSP_15_7
This validation is happening in the `ConveyorExecutor` Constructor prior to deploying the `LimitOrderRouter`
```solidity
///@param _weth - Address of the wrapped native token for the chain.
    ///@param _usdc - Address of the USD pegged token for the chain.
    ///@param _limitOrderExecutor - Address of the limit order executor contract
    ///@param _minExecutionCredit - Minimum amount of credit that must be provided to the limit order executor contract.
    constructor(
        address _weth,
        address _usdc,
        address _limitOrderExecutor,
        uint256 _minExecutionCredit
    ) OrderBook(_limitOrderExecutor, _weth, _usdc, _minExecutionCredit) {
        ///@notice Require that deployment addresses are not zero
        ///@dev All other addresses are being asserted in the limit order executor, which deploys the limit order router
        require(
            _limitOrderExecutor != address(0),
            "Invalid ConveyorExecutor address"
        );

        ///@notice Set the owner of the contract
        owner = tx.origin;
    }
```
- ConveyorExecutor.sol#L98-103

#### QSP_15_8
Gas credit logic was removed.

#### QSP_15_9
```solidity
/**@dev It is important to note that a univ2 compatible DEX must be initialized in the 0th index.
        The calculateFee function relies on a uniV2 DEX to be in the 0th index.*/
    ///@param _deploymentByteCodes - Array of DEX creation init bytecodes.
    ///@param _dexFactories - Array of DEX factory addresses.
    ///@param _isUniV2 - Array of booleans indicating if the DEX is UniV2 compatible.
    constructor(
        bytes32[] memory _deploymentByteCodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) {
        ///@notice Initialize DEXs and other variables
        for (uint256 i = 0; i < _deploymentByteCodes.length; ++i) {
            if (i == 0) {
                require(_isUniV2[i], "First Dex must be uniswap v2");
            }
            require(
                _deploymentByteCodes[i] != bytes32(0) &&
                    _dexFactories[i] != address(0),
                "Zero values in constructor"
            );
            dexes.push(
                Dex({
                    factoryAddress: _dexFactories[i],
                    initBytecode: _deploymentByteCodes[i],
                    isUniV2: _isUniV2[i]
                })
            );

            address uniswapV3Factory;
            ///@notice If the dex is a univ3 variant, then set the uniswapV3Factory storage address.
            if (!_isUniV2[i]) {
                uniswapV3Factory = _dexFactories[i];
            }

            UNISWAP_V3_FACTORY = uniswapV3Factory;
        }
    }

```
- SwapRouter.sol#L134-158

#### QSP_15_10
 Added assertion to `calculateFee`
```solidity
uint128 calculated_fee_64x64;
        if (amountIn == 0) {
            revert AmountInIsZero();
        }
```

- SwapRouter.sol#L191-193 

#### QSP_15_11
The referenced variables have been removed from the Quoter constructor. Below is the updated Quoter constructor.
```solidity
constructor(address _weth) {
        require(_weth != address(0), "Invalid weth address");
        WETH = _weth;
    }
```

- LimitOrderBatcher.sol#L17

#### QSP_15_12
The ConveyorExecutor contract now checks the mentioned variables for `address(0)`.

- ConveyorExecutor.sol#L99

# QSP-16 Gas Oracle Reliability ✅
### Description
1. Chainlink updates the feeds periodically (heartbeat idle time). The application should check that the timestamp of the latest answer is updated within the latest
heartbeat or within the time limits acceptable for the application (see: Chainlink docs). The GasOracle.getGasPrice() function does not check the timestamp of the
answer from the IAggregatorV3(gasOracleAddress).latestRoundData() call.
2. The "Fast Gas Data Feed" prices from Chainlink can be manipulated according to their docs. The application should be designed to detect gas price volatility or
malicious activity.


### Resolution
Gas oracle logic has been removed from the protocol.

# QSP-17 Math Function Returns Wrong Type ✅
Severity: 🟡Low Risk🟡
## Description
Under the assumption that the function `divUU128x128()` should return a `128.128` fixed point number, this function does not return the correct value.
### Resolution Details
This function has been removed from the codebase as we are no longer using it in the core contracts.


# QSP-18 Individual Order Fee Is Not Used in Batch Execution ✅

File(s) affected: TokenToWethLimitOrderExecution.sol
## Description: In TokenToWethLimitOrderExecution.sol#L365, getAllPrices() is using the first order's order.feeIn to compute uniswap prices for all of the orders in the batch.
However, different orders are not guaranteed to have the same feeIn. Thus, the computed result may not apply to all orders in the batch.

### Resolution Details
Updated _validateOrderSequencing() to check for congruent `feeIn` and `feeOut`. Added tests `testFailValidateOrderSequence_IncongruentFeeIn` and  `testFailValidateOrderSequence_IncongruentFeeOut`.

- LimitOrderRouter.sol#L265-272

# QSP-19 Locking the Difference Between `beaconReward` and `maxBeaconReward` in the Contract ✅
Severity: 🔵Informational🔵
## Description: 
The code has the concept of a `maxBeaconReward` to cap the max beacon reward sent to the executor. So whenever the raw `beaconReward` is greater than the `maxBeaconReward`, the executor will get the `maxBeaconReward`. However, the implementation will lock the difference between the two in the contract.
### Resolution Details
This issue has been resolved by subtracting the `amountOutInWeth` by the beaconReward after the cap has been computer. Along with this we decided to remove the maxBeaconReward for all order types except stoplosses.

- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417


## QSP-19_1
`TaxedTokenLimitOrderExecution._executeTokenToWethTaxedSingle()`: The function calls the `_executeTokenToWethOrder()` function on L133 and the `_executeTokenToWethOrder() `function will return `uint256(amountOutWeth - (beaconReward + conveyorReward))` (L192) as the `amountOut`. The `amountOut` is the final amount transferred to the order's owner. Later on L148-150, the raw `beaconReward` is capped to the `maxBeaconReward`. The difference will be left and locked in the contract.

### Resolution
The contract architecture change from batch execution to linear execution remvoved the need for a TaxedTokenLimitOrderExecution contract. A single taxed order from Token -> WETH will now be executed by the contract `LimitOrderExecutor#L52` within the function `executeTokenToWethOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_6**.

- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417

## QSP-19_2 
`TaxedTokenLimitOrderExecution._executeTokenToTokenTaxedSingle()`: The function calls `_executeTokenToTokenOrder().` The raw `beaconReward` will also be part of the deduction in `_executeTokenToTokenOrder()` (L357): `amountInWethToB = amountIn - (beaconReward + conveyorReward)`. The `maxBeaconReward` cap is applied later, and the difference will be left locked in the contract.
### Resolution
The contract architecture change from batch execution to linear execution remvoved the need for a TaxedTokenLimitOrderExecution contract. A single taxed order from Token -> Token will now be executed by the contract within the function `executeTokenToTokenOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_4**.
- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417

## QSP-19_3
TokenToTokenLimitOrderExecution._executeTokenToTokenSingle(): The function calls the _executeTokenToTokenOrder(). The raw beaconReward will be deducted when calculating the amountInWethToB. Later in _executeTokenToTokenSingle(), the maxBeaconReward is applied to the beaconReward. The difference
between the beaconReward and maxBeaconReward will be left in the contract.

### Resolution
This function has been removed as it is no longer needed with a linear execution contract architecture. A single order from Token-> Token will now be executed by the contract within the function `executeTokenToTokenOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_4**.
- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417

## QSP-19_4
`TokenToTokenLimitOrderExecution._executeTokenToTokenBatchOrders()`: The function calls `_executeTokenToTokenBatch()`. In the
`_executeTokenToTokenBatch()` function, the raw `beaconReward` is deducted when calculating the `amountInWethToB`. Later in the `_executeTokenToTokenBatchOrders()` function, the `maxBeaconReward` is applied to the `totalBeaconReward`. The difference between the `totalBeaconReward` and `maxBeaconReward` will be left in the contract.
### Resolution
The function `TokenToTokenLimitOrderExecution._executeTokenToTokenBatchOrders()` has been replaced with `executeTokenToTokenOrders()` as a result of changing to a linear execution architecture. The function similarly calculates the `maxBeaconReward` and calls `_executeTokenToTokenOrder` passing in the capped beacon reward.

#### Case Token-Token.) 
The function calls `_executeSwapTokenToWethOrder` and returns the `amountInWethToB` decremented by the `maxBeaconReward` if instantiated.
#### Case WETH-Token.) 
Since WETH is the input token no swap is needed. The function `_executeTokenToTokenOrder` calls `transferTokensToContract` and decrements the value `amountInWethToB` by the `maxBeaconReward` if instantiated. 

- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417

## QSP-19_5 
`TokenToWethLimitOrderExecution._executeTokenToWethSingle()`: The function calls `_executeTokenToWethOrder()`. The `_executeTokenToWethOrder()` will deduct the raw `beaconReward` when returning the `amountOut` value. Later, the `_executeTokenToWethSingle()` function caps the `beaconReward` to `maxBeaconReward`. The difference between the `beaconReward` and `maxBeaconReward` will be left in the contract. 

### Resolution
This function has been removed as it is no longer needed with a linear execution contract architecture. A single order from Token-> WETH will now be executed by the contract `LimitOrderExecutor` within the function `executeTokenToWethOrders`. The resolution to the locked beacon reward issue within the function is addressed in **QSP-19_6**.

- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417


## QSP-19_6 
`TokenToWethLimitOrderExecution._executeTokenToWethBatchOrders()`: The function calls the `_executeTokenToWethBatch()` function. The `_executeTokenToWethBatch()` will deduct the raw `beaconReward` when returning the `amountOut` value. Later, the `_executeTokenToWethBatchOrders()` function caps the `totalBeaconReward` to `maxBeaconReward`. The difference between the `totalBeaconReward` and `maxBeaconReward` will be left in the contract.

### Resolution

The function `TokenToWethLimitOrderExecution._executeTokenToWethBatchOrders()` is no longer used with the changes to a simpler linear execution architecture. All orders from Token -> Weth will now be executed at the top level by `executeTokenToWethOrders`. This function calculates the `maxBeaconReward` `LimitOrderExecutor` and calls `_executeTokenToWethOrder` passing in the `maxBeaconReward` as a parameter. `_executeTokenToWethOrder` calls `_executeSwapTokenToWethOrder` with the `maxBeaconReward` as a parameter and the returned `amountOutWeth` value is decremented by the `beaconReward` after the `beaconReward` has been capped. The fix can be referenced at 

```solidity
        ///@notice Calculate the conveyorReward and executor reward.
        (conveyorReward, beaconReward) = ConveyorFeeMath.calculateReward(
            protocolFee,
            amountOutWeth
        );
        ///@notice If the order is a stoploss, and the beaconReward surpasses 0.05 WETH. Cap the protocol and the off chain executor at 0.05 WETH.
        if (order.stoploss) {
            if (STOP_LOSS_MAX_BEACON_REWARD < beaconReward) {
                beaconReward = STOP_LOSS_MAX_BEACON_REWARD;
                conveyorReward = STOP_LOSS_MAX_BEACON_REWARD;
            }
        }

        ///@notice Get the AmountIn for weth to tokenB.
        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
```

- ConveyorExecutor.sol#L267-275
- ConveyorExecutor.sol#403-417


# QSP-20 Inaccurate Array Length ✅ (Needs tests to validate expected behavior)
Severity: Informational Status: Unresolved

File(s) affected: LimitOrderBatcher.sol, OrderBook.sol
## Description: Some functions return arrays that are padded with empty elements. The caller of those functions will need to be aware of this fact to not accidentally treat the padding as real data. The following is a list of functions that have this issue:
1. OrderBook.getAllOrderIds(): The impact is unclear, as the function is only used in the test contracts.

2. LimitOrderBatcher.batchTokenToTokenOrders(): The function is called by TokenToTokenLimitOrderExecution.executeTokenToTokenOrders(). Fortunately, the
implementation of executeTokenToTokenOrders() seems to be aware of the fact that batches can be empty.


### Resolution
#### QSP_20_1
In `OrderBook.getAllOrderIds()` assembly is used to resize the array after it is populated.

- OrderBook.sol#L658-664
- OrderBook.sol#L672-719

#### QSP_20_2
Batching functionality was removed so the issue in `LimitOrderBatcher.batchTokenToTokenOrders()` no longer exists.


# QSP-21 `TaxedTokenLimitOrderExecution` Contains Code for Handling Non-Taxed Orders ✅

Severity: 🔵Informational🔵

## Description: 
The function `_executeTokenToTokenOrder()` checks whether the order to execute is taxed. In case it is not, the tokens for the order are transferred to the `SwapRouter`contract. When actually executing the swap in `_executeSwapTokenToWethOrder()`, the swap is performed using the order.owner as sender, i.e. the tokens will be sent again from that address. Since the function is typically only called from code paths where orders are taxed, the best case scenario is that `TaxedTokenLimitOrderExecution.sol#L323-326` is dead code. In case somebody calls this function manually with a non-taxed order, it might lead to tokens being sent erroneously to the SwapRouter.

### Resolution
Taxed token limit order execution has been removed. Instead of a specific function for taxed token execution, taxed tokens are executed through `executeTokenToTokenOrders` or `executeTokenToWethOrders`.

- ConveyorExecutor.sol#L124
- ConveyorExecutor.sol#L280

## QSP-22 Unlocked Pragma ✅
Severity: 🔵Informational🔵
## Description: 
Every Solidity file specifies in the header a version number of the format pragma solidity (^)0.8.*. The caret (^) before the version number implies an unlocked pragma,
meaning that the compiler will use the specified version and above, hence the term "unlocked".
### Resolution
Locked all core contracts at solidity v0.8.16.


# QSP-23 Allowance Not Checked when Updating Orders ✅
Severity: 🔵Informational🔵
## Description: 
When placing an order, the contract will check if users set a high enough allowance to the ORDER_ROUTER contract (L216). However, this is not checked when updating an order in
the function updateOrder().
### Resolution
Added a check that ensures the allowance of the sender on the `LimitOrderExecutor` contract >= the `newOrder.quantity`.
```solidity
        ///@notice If the total approved quantity is less than the newOrder.quantity, revert.
        if (totalApprovedQuantity < newOrder.quantity) {
            revert InsufficientAllowanceForOrderUpdate();
        }
```


Test Case
```solidity
    ///@notice Test fail update order insufficient allowance
    function testFailUpdateOrder_InsufficientAllowanceForOrderUpdate(
        uint128 price,
        uint64 quantity,
        uint128 amountOutMin,
        uint128 newPrice,
        uint128 newAmountOutMin
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), quantity);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);

        //create a new order
        OrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            price,
            quantity,
            amountOutMin
        );

        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //create a new order to replace the old order
        OrderBook.LimitOrder memory updatedOrder = newOrder(
            swapToken,
            wnato,
            newPrice,
            quantity + 1, //Change the quantity to more than the approved amount
            newAmountOutMin
        );

        updatedOrder.orderId = orderId;

        //submit the updated order should revert since approved quantity is less than order quantity
        orderBook.updateOrder(updatedOrder);
    }
```

- OrderBook.sol#L501-507


# QSP-24 Incorrect Restriction in fromUInt256 ✅
Severity: 🔵Informational🔵
## Description: 
In the function `fromUInt256()`, if the input `x` is an unsigned integer and `x <= 0xFFFFFFFFFFFFFFFF`, then after `x << 64`, it will be less than or equal to `MAX64.64`. However
the restriction for `x` is set to `<= 0x7FFFFFFFFFFFFFFF` in the current implementation.

### Resolution
Changed the require statement to the recommended validation logic. Reference `ConveyorMath.sol#L20-25`.
```solidity
function fromUInt256(uint256 x) internal pure returns (uint128) {
    unchecked {
        require(x <= 0xFFFFFFFFFFFFFFFF);
        return uint128(x << 64);
    }
}
```

- ConveyorMath.sol#L24

# QSP-25 Extremely Expensive Batch Execution for Uniswap V3 ✅
Severity: 🟢Undetermined🟢
File(s) affected: `LimitOrderBatcher.sol`, `SwapRouter.sol`
## Description: 
According to the discussion with the team, the motivation for executing orders in batches is to save gas by reducing the number of swaps. However, when it comes to Uniswap V3, the code heavily relies on the `QUOTER.quoteExactInputSingle()` call to get the output amount of the swap. Unfortunately, the `QUOTER.quoteExactInputSingle()` is as costly as a real swap because it is performing the swap and then force reverting to undo it (see: code and doc). `QUOTER.quoteExactInputSingle()` is called in `SwapRouter.getNextSqrtPriceV3()`, `LimitOrderBatcher.calculateNextSqrtPriceX96()`, and `LimitOrderBatcher.calculateAmountOutMinAToWeth()`.
### Resolution
Changes made to mitigate Gas consumption in execution:
As per the reccomendation of the quant stamp team we changed the execution architecture of the contract to a stricly linear flow. The changes to linear execution architecture immediately reduced the gas consumption overall, most significantly when a V3 pool was utilized during execution because of a reduced amount of calls to the quoter. Further, we eliminated using the v3 quoter completely from the contract, and built our own internal logic to simulate the amountOut yielded on a V3 swap. Reference `Contract Architecture Changes/Uniswap V3` for a detailed report of the code, and it's implementation throughout the contract. 

## Uniswap V3 Changes
#### Function `LimitOrderBatcher.calculateAmountOutMinAToWeth()`
We eliminated the use of the v3 Quoter in the contract. Our quoting logic was modeled after: (https://github.com/Uniswap/v3-core/blob/main/contracts/UniswapV3Pool.sol#L596).

The implementation is located in `src/lib/ConveyorTickMath.sol` within the function `simulateAmountOutOnSqrtPriceX96`. 
This function is called in `src/LimitOrderBatcher.sol` within `calculateAmountOutMinAToWeth` </br>

Tests:<br />
Reference `src/test/LimitOrderBatcher.t.sol` for `calculateAmountOutMinAToWeth` tests.<br />
Reference `src/test/ConveyorTickMath.t.sol` for `simulateAmountOutOnSqrtPriceX96` tests. <br />

#### Function `_calculateV3SpotPrice`
The V3 spot price calculation has been modified to be more gas efficient by simply calling `slot0()` on the pool, and converting `sqrtPriceX96` to `128.128` fixed point representation of `sqrtPriceX96**2`. 

#### Function `LimitOrderBatcher.calculateNextSqrtPriceX96`
This function was modified to be more gas efficient by eliminating all calls to the v3 quoter, and calculating the amountOut return value by simply calling `ConveyorTickMath.simulateAmountOutOnSqrtPriceX96`. 

#### Function `SwapRouter.getNextSqrtPriceV3`
This has been simplified to be more gas efficient by eliminating all calls to the quoter. <br />
Reference `SwapRouter`


# QSP-26 Issues in Maximum Beacon Reward Calculation ✅
### Resolution
We decided to remove the `alphaX` and `maxBeaconReward` functions from the contract because of the gas consumed from the computation. We also decided capping the reward was not necessary for any limit order other than a stop loss. We added a constant: 
```solidity
uint128 constant STOP_LOSS_MAX_BEACON_REWARD = 50000000000000000;
```
This constant is used in place of the `maxBeaconReward` in the case of stoploss orders. 

- ConveyorExecutor.sol#L29

# QSP-27 Verifier's Dilemma ✅
he beacon network allows any executor to submit the execution of the orders. As an incentive for monitoring the protocol and executing orders once they become valid, the protocol pays the executors a reward. However, an attacker can steal the work of another executor by simply monitoring the mempool and front-run their transaction. Despite the attacker never monitoring and matching the orders, the attacker can earn the beacon reward by stealing another executor's work.
Furthermore, since only the fastest executor receives a reward, this might discourage participants from becoming an executor themselves.

## Resolution
The default behavior for the off-chain logic will be to route the execution transaction through private relays, encrypted mempools and other means of transaction obfuscation when available. For chains that do not have an equivalent option, the default Beacon will have built in priority gas auction (PGA) logic to compete with other bots that try to front run their transaction. While this does not alleviate the Verifier's delimma on these chains, it gives the beacon a defense mechanism against front runners.  

# QSP-28 Taxed Token Swaps Using Uniswap V3 Might Fail 🟡

## Description
The SwapRouter does not seem to handle taxed tokens, i.e. ones with a "fee on transfer", correctly when routed through Uniswap V3. In the uniswapV3SwapCallback() function, one of the function parameters dictates the amount of tokens that have to be transferred to the pool for the swap to succeed. The SwapRouter attempts to send exactly that many tokens. However, if the token transfers are "taxed", the pool will receive less than intended and the swap will fail.

## Resolution
This QSP has been acknowledged. The current taxed token tests in the codebase have been successfully executed on V3 Pools. The off-chain executor is able to call the node prior to execution, and should be able to determine if a taxed token execution will fail or not. In the case when a taxed token were to fail a v3 execution the off-chain executor can wait until a v2 pool becomes the most advantageous limit price to execute the Order.


# **Code Documentation** ✅
Consider providing instructions on how to build and test the contracts in the README. ✅ </br>
Consider providing a link in the code comment for the SwapRouter._getV2PairAddress() function (L1025-1045) on how the address is determined: Uniswap V2 Pair Address doc. ✅ </br>

The comment in LimitOrderRouter.sol#L416 (within the `_validateOrderSequencing()` function) does not match the implementation. Change it from "Check if thetoken tax status is the same..." to "Check if the buy/sell status is the same..." instead. ✅ </br>

The code documentation/comment in `LimitOrderBatcher.sol#L22` and `LimitOrderBatcher.sol#L35` for the `batchTokenToTokenOrders()` function seems inconsistent with the implementation. The comment states "Function to batch multiple token to weth orders together" and "Create a new token to weth batch order", but the function is token to "token" and not token to "weth". ✅ </br>

`LimitOrderBatcher.sol#L469` states, "If the order is a buy order, set the initial best price at 0". However, the implementation set the initial best price to the max of `uint256`. Similarly, L475 states, "If the order is a sell order, set the initial best price at max `uint256`". In contrast, the implementation sets the initial price to zero. The implementation seems correct, and the comment is misleading.  ✅ </br>

The code documentation for the following contracts seems misplaced: `TaxedTokenLimitOrderExecution`, `TokenToTokenLimitOrderExecution`, and `TokenToWethLimitOrderExecution`. They all have `@title SwapRouter` instead of each contract's documentation.  ✅ </br>

Fix the code documentation for the `ConveyorMath.add64x64()` function. L65 states that "helper to add two unsigened `128.128` fixed point numbers" while the functions add two `64.64` fixed point numbers instead. Also, there is a typo on the word "unsigened", which should be "unsigned".
Consider adding NatSpec documentation for the following functions in `ConveyorMath.sol`: `sub()`, `sub64UI()`, `abs()`, `sqrt128()`, `sqrt()`, and `sqrtBig()`. It is unclear which types they operate on (e.g., whether they should be fixed-point numbers).  ✅ </br>

Fix the code documentation for the `ConveyorMath.mul128x64()` function. **L130** states that "helper function to multiply two unsigned `64.64` fixed point numbers" while multiplying a `128.128` fixed point number with another `64.64` fixed-point number.  ✅ </br>

Add `@param` comment for the field `taxIn` of the struct Order **(L44-73)** in `OrderBook.sol`. ✅ </br>

Consider adding a warning for the `SwapRouter.calculateFee()` function that the amountIn can only be the amount **WETH (or 18 decimal tokens)**.  ✅</br>

The onlyOwner modifier implemented in the `LimitOrderExecution.sol` contracts has documentation that states that the modifier should be applied to the function `transferOwnership()`. As there is no transferOwnership() function in those contracts, either add one or remove it from the modifier documentation.  ✅ </br>

`ConveyorMath.mul128I()#L167`, **"multiply unsigned 64.64" should be "128.128"**.  ✅ </br>

`ConveyorMath.div128x128()#L213`, **"@return unsigned uint128 64.64" should be "128.128"**.  ✅ </br>

`ConveyorMath.divUI()#L229`, **"helper function to divide two 64.64 fixed point numbers" should be "... two integers"**.  ✅ </br>

`ConveyorMath.divUI128x128()#L310`, **"helper function to divide two unsigned 64.64 fixed point" should be "... two integers".**  ✅ </br>

`ConveyorMath.divUI128x128()#L313`, **"@return unsigned uint128 64.64 unsigned integer" should be "... uint256 128.128 fixed point number"**.  ✅ </br>
`ConveyorMath.divUU128x128()#L330`, **"@return unsigned 64.64" should be "... 128.128"**.  ✅ </br>

`TokenToWethLimitOrderExecution.sol#L349`, **the documentation is wrong, since the function only handles tokenA -> Weth**.  ✅ </br>

`TaxedTokenLimitOrderExecution.sol#L197`, **the documentation is wrong, since the function only handles tokenA -> Weth**.  ✅ </br>

### The following functions do not have any documentation: ✅ 
        `ConveyorTickMath.fromX96()`
        `ConveyorMath.sub()`
        `ConveyorMath.sub64UI()`
        `ConveyorMath.sqrt128()`
        `ConveyorMath.sqrt()`
        `ConveyorMath.sqrtBig()`
        `QuadruplePrecision.to128x128()`
        `QuadruplePrecision.fromInt()`
        `QuadruplePrecision.toUInt()`
        `QuadruplePrecision.from64x64()`
        `QuadruplePrecision.to64x64()`
        `QuadruplePrecision.fromUInt()`
        `QuadruplePrecision.from128x128()`
The `@return` documentation for the following functions is unclear:


       `ConveyorMath.mul64x64()` (expecting unsigned 64.64).
       `ConveyorMath.mul128x64() (expecting unsigned 128.128).
       `ConveyorMath.mul64U()` (expecting unsigned integer).
       `ConveyorMath.mul128U()` (expecting unsigned integer).
       

## Adherence to Best Practices**
Remove the unused function `OrderBook._resolveCompletedOrderAndEmitOrderFufilled()` (L371-392).  ✅ </br>

Remove the unused function `OrderBook.incrementTotalOrdersQuantity()` (L441-448).  ✅ </br>

`OrderBook.sol#L487`, replace the magic number 100 in the `_calculateMinGasCredits()` function with a named constant.  ✅ </br>

`OrderBook.sol#L505`, replace the magic number 150 in the `_hasMinGasCredits()` function with a named constant.  ✅ </br>

Consider setting the tempOwner to zero in the `LimitOrderRouter.confirmTransferOwnership()` function once the owner is set. By cleaning up the storage, the EVM will refund some gas.  ✅ </br>

Consider replacing the assembly block with simply `initalTxGas = gasleft()` in `LimitOrderRouter.sol#434-436`(within the `executeOrders()` function). The gas saved with the assembly is negligible (around 10). </br>

Consider removing the `LimitOrderBatcher._buyOrSell()` function. The code using this function can replace it simply with `firstOrder.buy on L44` and L207.  </br>

Consider renaming the `ConveyorMath.mul64I() (L149)` and the `ConveyorMath.mul128I()` (L171) functions to `mul64U()` and `mul128U()` instead. The functions handle unsigned integers instead of signed integers.  ✅ </br>

GasOracle.getGasPrice() tends to get called multiple times per execution. Consider whether it's possible to cache it to avoid multiple external calls.  ✅ </br>

`OrderBook.addressToOrderIds` seems unnecessary. It is used to check whether orders exist via: `bool orderExists = addressToOrderIds[msg.sender] [newOrder.orderId];`. This can also be done through `bool orderExists = orderIdToOrder[newOrder.orderId].owner == msg.sender`. </br>

`OrderBook.orderIdToOrder` should be declared as internal since the generated getter function leads to "stack too deep" errors when compiled without optimizations, which is required for collecting code coverage.  ✅ </br>

Consider using `orderNonce` as the orderId directly instead of hashing it with `block.timestamp`, since the orderNonce will already be unique. </br>
`OrderBook.sol#L177` and `LimitOrderRouter.sol#L285` perform a modulo operation on the block.timestamp and casts the result to uint32. A cast to uint32 willtruncate the value the same way the modulo operation does, which is therefore redundant and can be removed.  ✅ </br>

In `OrderBook.placeOrder()`, the local variables `orderIdIndex` and i will always have the same value. `orderIdIndex` can be removed and uses replaced by i.  ✅ </br>

Consider removing the `OrderBook.cancelOrder()` function, since the OrderBook.cancelOrders() contains nearly identical code. Additionally, to place an order, only the OrderBook.placeOrders() function exists, which makes the API inconsistent. </br>
`LimitOrderRouter.refreshOrder()#254` calls `getGasPrice()` in each loop iteration. Since the gas price does not change within a transaction, move this call out of the loop to save gas.  ✅ </br>

`LimitOrderRouter.refreshOrder()#277` sends the fees to the message sender on each loop. Consider accumulating the amount and use a single `safeTransferETH()` call at the end of the function.  ✅ </br>

`SwapRouter.sol` should implement the `IOrderRouter` interface explicitly to ensure the function signatures match. NA </br>

`SwapRouter._calculateV2SpotPrice()#L961` computes the Uniswap V2 token pair address manually and enforces that it is equal to the `IUniswapV2Factory.getPair()` immediately after. Since the addresses must match, consider using just the output of the call to `getPair()` and remove the manual address computation. The `getPair()` function returns the zero address in case the pair has not been created. </br>

SwapRouter._swapV3() makes a call to `getNextSqrtPriceV3()` to receive the `_sqrtPriceLimitX96` parameter that is passed to the pool's `swap() `function. Since the `getNextSqrtPriceV3()` function potentially also performs the expensive swap through the use of a `Quoter.quoteExactInputSingle()` call and the output amount of the swap will be checked by `uniswapV3SwapCallback()` anyway, consider using the approach of Uniswap V3's router and supply `(_zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)` as the `_sqrtPriceLimitX96` parameter.  </br>

This would also allow removing the dependency on the Quoter contract for the SwapRouter contract.✅ </br>

Save the `uniV3AmountOut` amount in memory and set the contract storage back to 0 before returning the amount in `SwapRouter._swapV3()#L829` to save gas (see **EIP-1283**). ✅ </br>

The iQuoter member should be removed from the `*LimitOrderExecution.sol` contracts, since they are not used by the contracts and already inherited through `LimitOrderBatcher`. ✅ </br>

ConveyorMath.mul64x64#L125 uses an unclear require message that looks like a leftover from debugging. ✅ </br>

`SwapRouter.calculateReward()#L320`, **change (0.005-fee)/2+0.001*10**2 to ((0.005-fee)/2+0.001)*10**2** to avoid confusion about operator precedence.
`ConveyorMath.divUI()` and `ConveyorMath.divUU()` perform the same computation. Remove `divUI()`. ✅ </br>

`ConveyorMath.divUI128x128()` and `ConveyorMath.divUU128x128()` perform the same computation. Remove `divUI128x128()`. ✅ </br>

The function `mostSignificantBit()` exists in both ConveyorBitMath.sol and QuadruplePrecision.sol. Remove one of them. ✅ </br>

Typos in variables:

### Several variables contain the typo fufilled instead of fulfilled. Some of these are externally visible. ✅
    parameter _reciever in `SwapRouter._swapV2()` should be renamed to _receiver, the return variable amountRecieved should be amountReceived
    parameter _reciever in `SwapRouter._swapV3()` should be renamed to _receiver, the return variable amountRecieved should be amountReceived
    parameter _reciever in `SwapRouter._swap()` should be renamed to _receiver, the return variable amountRecieved should be amountReceived.
    
OrderBook.sol#L240 could use storage instead of memory to save gas. </br>

Internal function `_executeSwapTokenToWethOrder()` in `TokenToWethLimitOrderExecution.sol` is never used and can be removed. ✅ </br>


