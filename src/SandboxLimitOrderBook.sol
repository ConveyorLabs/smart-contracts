// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./GasOracle.sol";
import "./ConveyorErrors.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/ISwapRouter.sol";
import "./lib/ConveyorMath.sol";
import "./test/utils/Console.sol";

/// @title OrderBook
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Contract to maintain active orders in limit order system.

//TODO: need to separate gas oracle
contract SandboxLimitOrderBook is GasOracle {
    address immutable LIMIT_ORDER_EXECUTOR;

    ///@notice The gas credit buffer is the multiplier applied to the minimum gas credits necessary to place an order. This ensures that the gas credits stored for an order have a buffer in case of gas price volatility.
    ///@notice The gas credit buffer is divided by 100, making the GAS_CREDIT_BUFFER a multiplier of 1.5x,
    uint256 constant GAS_CREDIT_BUFFER = 150;

    ///@notice The execution cost of fufilling a SandboxLimitOrder with a standard ERC20 swap from tokenIn to tokenOut
    uint256 immutable SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST;

    //TODO: Move this to the limit order executor and keep it in one place
    ///@notice Mapping to hold gas credit balances for accounts.
    mapping(address => uint256) public gasCreditBalance;

    address immutable WETH;
    address immutable USDC;

    //----------------------Constructor------------------------------------//

    constructor(
        address _gasOracle,
        address _limitOrderExecutor,
        address _weth,
        address _usdc,
        uint256 _sandboxLimitOrderExecutionGasCost
    ) GasOracle(_gasOracle) {
        require(
            _limitOrderExecutor != address(0),
            "limitOrderExecutor address is address(0)"
        );
        WETH = _weth;
        USDC = _usdc;
        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
        SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST = _sandboxLimitOrderExecutionGasCost;
    }

    //----------------------Events------------------------------------//
    /**@notice Event that is emitted when a new order is placed. For each order that is placed, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderPlaced(bytes32[] orderIds);

    /**@notice Event that is emitted when an order is canceled. For each order that is canceled, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderCanceled(bytes32[] orderIds);

    /**@notice Event that is emitted when a new order is update. For each order that is updated, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderUpdated(bytes32[] orderIds);

    /**@notice Event that is emitted when an order is filled. For each order that is filled, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderFufilled(bytes32[] orderIds);

    ///@notice Event that notifies off-chain executors when an order has been refreshed.
    event OrderRefreshed(
        bytes32 indexed orderId,
        uint32 indexed lastRefreshTimestamp,
        uint32 indexed expirationTimestamp
    );

    ///@notice Event that notifies off-chain executors when gas credits are added or withdrawn from an account's balance.
    event GasCreditEvent(address indexed sender, uint256 indexed balance);

    //----------------------Structs------------------------------------//
    ///@notice Struct containing Order details for any limit order
    ///@param buy - Indicates if the order is a buy or sell
    ///@param lastRefreshTimestamp - Unix timestamp representing the last time the order was refreshed.
    ///@param expirationTimestamp - Unix timestamp representing when the order should expire.
    ///@param fillPercent - The percentage filled on the initial amountInRemaining represented as 16.16 fixed point.
    ///@param price - The execution price representing the spot price of tokenIn/tokenOut that the order should be filled at. This is simply amountOutRemaining/amountInRemaining.
    ///@param executionFee - The fee paid in WETH for Order execution.
    ///@param amountOutRemaining - The exact amountOut out that the order owner is willing to accept. This value is represented in tokenOut.
    ///@param amountInRemaining - The exact amountIn of tokenIn that the order will be supplying to the contract for the limit order.
    ///@param owner - The owner of the order. This is set to the msg.sender at order placement.
    ///@param tokenIn - The tokenIn for the order.
    ///@param tokenOut - The tokenOut for the order.
    ///@param orderId - Unique identifier for the order.
    struct SandboxLimitOrder {
        bool buy;
        uint32 lastRefreshTimestamp;
        uint32 expirationTimestamp;
        uint32 fillPercent;
        uint128 fee;
        uint128 amountInRemaining;
        uint128 amountOutRemaining;
        address owner;
        address tokenIn;
        address tokenOut;
        bytes32 orderId;
    }

    enum OrderType {
        None,
        PendingSandboxLimitOrder,
        PartialFilledSandboxLimitOrder,
        FilledSandboxLimitOrder,
        CanceledSandboxLimitOrder
    }

    //----------------------State Structures------------------------------------//

    ///@notice Mapping from an orderId to its ordorderIdToSandboxLimitOrderer.
    mapping(bytes32 => SandboxLimitOrder) internal orderIdToSandboxLimitOrder;

    ///@notice Mapping to find the total orders quantity for a specific token, for an individual account
    ///@dev The key is represented as: keccak256(abi.encode(owner, token));
    mapping(bytes32 => uint256) public totalOrdersQuantity;

    ///@notice Mapping to check if an order exists, as well as get all the orders for an individual account.
    ///@dev ownerAddress -> orderId -> OrderType
    mapping(address => mapping(bytes32 => OrderType)) public addressToOrderIds;

    ///@notice Mapping to store the number of total orders for an individual account
    mapping(address => uint256) public totalOrdersPerAddress;

    ///@notice Mapping to store all of the orderIds for a given address including canceled, pending and fuilled orders.
    mapping(address => bytes32[]) public addressToAllOrderIds;

    ///@notice The orderNonce is a unique value is used to create orderIds and increments every time a new order is placed.
    uint256 orderNonce;

    //----------------------Functions------------------------------------//

    ///@notice This function gets an order by the orderId. If the order does not exist, the return value will be bytes(0)
    function getOrderById(bytes32 orderId)
        public
        view
        returns (OrderType, bytes memory)
    {
        ///@notice Check if the order exists
        OrderType orderType = addressToOrderIds[msg.sender][orderId];

        if (orderType == OrderType.None) {
            return (OrderType.None, new bytes(0));
        }

        if (orderType == OrderType.PendingSandboxLimitOrder) {
            SandboxLimitOrder
                memory sandboxLimitOrder = orderIdToSandboxLimitOrder[orderId];
            return (
                OrderType.PendingSandboxLimitOrder,
                abi.encode(sandboxLimitOrder)
            );
        }
    }

    function getSandboxLimitOrderById(bytes32 orderId)
        public
        view
        returns (SandboxLimitOrder memory)
    {
        return orderIdToSandboxLimitOrder[orderId];
    }

    ///@notice Places a new order of multicall type (or group of orders) into the system.
    ///@param orderGroup - List of newly created orders to be placed.
    /// @return orderIds - Returns a list of orderIds corresponding to the newly placed orders.
    function placeSandboxLimitOrder(SandboxLimitOrder[] calldata orderGroup)
        public
        payable
        returns (bytes32[] memory)
    {
        checkSufficientGasCreditsForOrderPlacement(orderGroup.length);

        ///@notice Initialize a new list of bytes32 to store the newly created orderIds.
        bytes32[] memory orderIds = new bytes32[](orderGroup.length);

        ///@notice Initialize the orderToken for the newly placed orders.
        /**@dev When placing a new group of orders, the tokenIn and tokenOut must be the same on each order. New orders are placed
        this way to securely validate if the msg.sender has the tokens required when placing a new order as well as enough gas credits
        to cover order execution cost.*/
        address orderToken = orderGroup[0].tokenIn;

        ///@notice Get the value of all orders on the orderToken that are currently placed for the msg.sender.
        uint256 updatedTotalOrdersValue = _getTotalOrdersValue(orderToken);

        ///@notice Get the current balance of the orderToken that the msg.sender has in their account.
        uint256 tokenBalance = IERC20(orderToken).balanceOf(msg.sender);

        ///@notice For each order within the list of orders passed into the function.
        for (uint256 i = 0; i < orderGroup.length; ) {
            ///@notice Get the order details from the orderGroup.
            SandboxLimitOrder memory newOrder = orderGroup[i];

            ///@notice Increment the total value of orders by the quantity of the new order
            updatedTotalOrdersValue += newOrder.amountInRemaining;
            uint256 relativeWethValue;
            {
                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
                if (!(newOrder.tokenIn == WETH)) {
                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
                    (SwapRouter.SpotReserve[] memory spRes, ) = IOrderRouter(
                        LIMIT_ORDER_EXECUTOR
                    )._getAllPrices(newOrder.tokenIn, WETH, 500);
                    uint256 tokenAWethSpotPrice;
                    for (uint256 k = 0; k < spRes.length; ) {
                        if (spRes[k].spotPrice != 0) {
                            tokenAWethSpotPrice = spRes[k].spotPrice;
                            break;
                            ///TODO: Revisit this
                        }

                        unchecked {
                            ++k;
                        }
                    }
                    if (tokenAWethSpotPrice == 0) {
                        revert InvalidInputTokenForOrderPlacement();
                    }

                    if (!(tokenAWethSpotPrice == 0)) {
                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn)
                            .decimals();
                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
                        relativeWethValue = tokenInDecimals <= 18
                            ? ConveyorMath.mul128U(
                                tokenAWethSpotPrice,
                                newOrder.amountInRemaining
                            ) * 10**(18 - tokenInDecimals)
                            : ConveyorMath.mul128U(
                                tokenAWethSpotPrice,
                                newOrder.amountInRemaining
                            ) / 10**(tokenInDecimals - 18);
                    }
                } else {
                    relativeWethValue = newOrder.amountInRemaining;
                }
                ///@notice Set the minimum fee to the fee*wethValue*subsidy.
                uint128 minFeeReceived = uint128(
                    ConveyorMath.mul64U(
                        IOrderRouter(LIMIT_ORDER_EXECUTOR)._calculateFee(
                            uint128(relativeWethValue),
                            USDC,
                            WETH
                        ),
                        relativeWethValue
                    )
                );
                ///@notice Set the Orders min fee to be received during execution.
                newOrder.fee = minFeeReceived;
            }

            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
            if ((orderToken != newOrder.tokenIn)) {
                revert IncongruentInputTokenInOrderGroup(
                    newOrder.tokenIn,
                    orderToken
                );
            }

            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
            if (tokenBalance < updatedTotalOrdersValue) {
                revert InsufficientWalletBalance(
                    msg.sender,
                    tokenBalance,
                    updatedTotalOrdersValue
                );
            }

            ///@notice Create a new orderId from the orderNonce and current block timestamp
            bytes32 orderId = keccak256(
                abi.encode(orderNonce, block.timestamp)
            );

            ///@notice increment the orderNonce
            /**@dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the 
            orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
            */
            unchecked {
                ++orderNonce;
            }

            ///@notice Set the new order's owner to the msg.sender
            newOrder.owner = msg.sender;

            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
            newOrder.orderId = orderId;

            ///@notice update the newOrder's last refresh timestamp
            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
            newOrder.lastRefreshTimestamp = uint32(block.timestamp);

            ///@notice Add the newly created order to the orderIdToOrder mapping
            orderIdToSandboxLimitOrder[orderId] = newOrder;

            ///@notice Add the orderId to the addressToOrderIds mapping
            addressToOrderIds[msg.sender][orderId] = OrderType
                .PendingSandboxLimitOrder;

            ///@notice Increment the total orders per address for the msg.sender
            ++totalOrdersPerAddress[msg.sender];

            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
            orderIds[i] = orderId;

            ///@notice Add the orderId to the addressToAllOrderIds structure
            addressToAllOrderIds[msg.sender].push(orderId);

            unchecked {
                ++i;
            }
        }

        ///@notice Update the total orders value on the orderToken for the msg.sender.
        updateTotalOrdersQuantity(
            orderToken,
            msg.sender,
            updatedTotalOrdersValue
        );

        ///@notice Get the total amount approved for the ConveyorLimitOrder contract to spend on the orderToken.
        uint256 totalApprovedQuantity = IERC20(orderToken).allowance(
            msg.sender,
            address(LIMIT_ORDER_EXECUTOR)
        );

        ///@notice If the total approved quantity is less than the updatedTotalOrdersValue, revert.
        if (totalApprovedQuantity < updatedTotalOrdersValue) {
            revert InsufficientAllowanceForOrderPlacement(
                orderToken,
                totalApprovedQuantity,
                updatedTotalOrdersValue
            );
        }

        ///@notice Emit an OrderPlaced event to notify the off-chain executors that a new order has been placed.
        emit OrderPlaced(orderIds);

        return orderIds;
    }

    ///@notice Function to check if an order owner has sufficient gas credits for all active orders at order placement time.
    ///@param numberOfOrders - The owners current number of active orders.
    function checkSufficientGasCreditsForOrderPlacement(uint256 numberOfOrders)
        internal
    {
        ///@notice Cache the gasPrice and the userGasCreditBalance
        uint256 gasPrice = getGasPrice();

        uint256 userGasCreditBalance = gasCreditBalance[msg.sender];

        ///@notice Get the total amount of active orders for the userAddress
        uint256 totalOrderCount = totalOrdersPerAddress[msg.sender];

        ///@notice Calculate the minimum gas credits needed for execution of all active orders for the userAddress.
        uint256 minimumGasCredits = (totalOrderCount + numberOfOrders) *
            gasPrice *
            SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST *
            GAS_CREDIT_BUFFER;

        ///@notice If the gasCreditBalance + msg value does not cover the min gas credits, then revert
        if (userGasCreditBalance + msg.value < minimumGasCredits) {
            revert InsufficientGasCreditBalance(
                msg.sender,
                userGasCreditBalance + msg.value,
                minimumGasCredits
            );
        }

        if (msg.value != 0) {
            ///@notice Update the account gas credit balance
            gasCreditBalance[msg.sender] = userGasCreditBalance + msg.value;
            emit GasCreditEvent(msg.sender, userGasCreditBalance + msg.value);
        }
    }

    /**@notice Updates an existing order. If the order exists and all order criteria is met, the order at the specified orderId will
    be updated to the newOrder's parameters. */
    /**@param orderId - OrderId of order to update.
    ///@param price - Price to update the execution price of the order to. The price will stay the same if this field is set to 0.
    ///@param quantity - Quantity to update the existing order quantity to. The quantity will stay the same if this field is set to 0.
    The newOrder should have the orderId that corresponds to the existing order that it should replace. */
    function updateOrder(
        bytes32 orderId,
        uint128 price,
        uint128 quantity
    ) public {
        ///@notice Check if the order exists
        OrderType orderType = addressToOrderIds[msg.sender][orderId];

        if (orderType == OrderType.None) {
            ///@notice If the order does not exist, revert.
            revert OrderDoesNotExist(orderId);
        }

        if (orderType == OrderType.PendingLimitOrder) {
            _updateLimitOrder(orderId, price, quantity);
        } else {
            _updateSandboxLimitOrder(
                orderId,
                quantity,
                uint128(ConveyorMath.mul64U(price, quantity))
            );
        }
    }

    ///@notice Function to update a sandbox Limit Order.
    ///@param orderId - The orderId of the Sandbox Limit Order.
    ///@param amountInRemaining - The new amountInRemaining.
    ///@param amountOutRemaining - The new amountOutRemaining.
    function _updateSandboxLimitOrder(
        bytes32 orderId,
        uint128 amountInRemaining,
        uint128 amountOutRemaining
    ) internal {
        ///@notice Get the existing order that will be replaced with the new order
        SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[orderId];
        if (order.orderId == bytes32(0)) {
            revert OrderDoesNotExist(orderId);
        }
        ///@notice Get the total orders value for the msg.sender on the tokenIn
        uint256 totalOrdersValue = _getTotalOrdersValue(order.tokenIn);

        ///@notice Update the total orders value
        totalOrdersValue += amountInRemaining;
        totalOrdersValue -= order.amountInRemaining;

        ///@notice If the wallet does not have a sufficient balance for the updated total orders value, revert.
        if (IERC20(order.tokenIn).balanceOf(msg.sender) < totalOrdersValue) {
            revert InsufficientWalletBalance(
                msg.sender,
                IERC20(order.tokenIn).balanceOf(msg.sender),
                totalOrdersValue
            );
        }

        ///@notice Update the total orders quantity
        updateTotalOrdersQuantity(order.tokenIn, msg.sender, totalOrdersValue);

        ///@notice Get the total amount approved for the ConveyorLimitOrder contract to spend on the orderToken.
        uint256 totalApprovedQuantity = IERC20(order.tokenIn).allowance(
            msg.sender,
            address(LIMIT_ORDER_EXECUTOR)
        );

        ///@notice If the total approved quantity is less than the newOrder.quantity, revert.
        if (totalApprovedQuantity < amountInRemaining) {
            revert InsufficientAllowanceForOrderUpdate(
                order.tokenIn,
                totalApprovedQuantity,
                amountInRemaining
            );
        }

        ///@notice Update the order details stored in the system.
        orderIdToSandboxLimitOrder[order.orderId]
            .amountInRemaining = amountInRemaining;
        orderIdToSandboxLimitOrder[order.orderId]
            .amountOutRemaining = amountOutRemaining;

        ///@notice Emit an updated order event with the orderId that was updated
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        emit OrderUpdated(orderIds);
    }

    ///@notice Remove an order from the system if the order exists.
    /// @param orderId - The orderId that corresponds to the order that should be canceled.
    function cancelOrder(bytes32 orderId) public {
        ///@notice Get the order details
        SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[orderId];

        ///@notice Delete the order from orderIdToOrder mapping
        delete orderIdToSandboxLimitOrder[orderId];

        ///@notice Delete the orderId from addressToOrderIds mapping
        delete addressToOrderIds[msg.sender][orderId];

        ///@notice Decrement the total orders for the msg.sender
        --totalOrdersPerAddress[msg.sender];

        ///@notice Decrement the order quantity from the total orders quantity
        decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.amountInRemaining
        );

        ///@notice Update the status of the order to canceled
        addressToOrderIds[order.owner][order.orderId] = OrderType
            .CanceledSandboxLimitOrder;

        ///@notice Emit an event to notify the off-chain executors that the order has been canceled.
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCanceled(orderIds);
    }

    /// @notice cancel all orders relevant in ActiveOrders mapping to the msg.sender i.e the function caller
    function cancelOrders(bytes32[] memory orderIds) public {
        //check that there is one or more orders
        for (uint256 i = 0; i < orderIds.length; ) {
            cancelOrder(orderIds[i]);

            unchecked {
                ++i;
            }
        }
    }

    ///@notice Internal function to partially fill a sandbox limit order and update the remaining quantity.
    ///@param amountInFilled - The amount in that was filled for the order.
    ///@param amountOutFilled - The amount out that was filled for the order.
    ///@param orderId - The orderId of the order that was filled.
    function _partialFillSandboxLimitOrder(
        uint128 amountInFilled,
        uint128 amountOutFilled,
        bytes32 orderId
    ) internal {
        SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[orderId];

        ///@notice Decrement totalOrdersQuantity on order.tokenIn for order owner
        decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            amountInFilled
        );
        ///@notice Cache the Orders amountInRemaining.
        uint128 amountInRemaining = orderIdToSandboxLimitOrder[orderId]
            .amountInRemaining;
        ///@notice Update the orders fillPercent to amountInFilled/amountInRemaining as 16.16 fixed point
        orderIdToSandboxLimitOrder[orderId].fillPercent += ConveyorMath
            .fromX64ToX16(
                ConveyorMath.divUU(amountInFilled, amountInRemaining)
            );

        orderIdToSandboxLimitOrder[orderId].amountInRemaining =
            order.amountInRemaining -
            amountInFilled;

        orderIdToSandboxLimitOrder[orderId].amountOutRemaining =
            order.amountOutRemaining -
            amountOutFilled;

        ///@notice Update the status of the order to PartialFilled
        addressToOrderIds[order.owner][order.orderId] = OrderType
            .PartialFilledSandboxLimitOrder;
    }

    ///@notice Function to remove an order from the system.
    ///@param orderId - The orderId that should be removed from the system.
    function _removeOrderFromSystem(bytes32 orderId) internal {
        ///@dev the None order type can not reach here so we can use `else`
        SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[orderId];

        ///@notice Remove the order from the system
        delete orderIdToSandboxLimitOrder[order.orderId];

        ///@notice Decrement from total orders per address
        --totalOrdersPerAddress[order.owner];

        ///@notice Decrement totalOrdersQuantity on order.tokenIn for order owner
        decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.amountInRemaining
        );
    }

    ///@notice Function to resolve an order as completed.
    ///@param orderId - The orderId that should be resolved from the system.
    function _resolveCompletedOrder(bytes32 orderId, OrderType orderType)
        internal
    {
        ///@dev the None order type can not reach here so we can use `else`

        ///@notice Grab the order currently in the state of the contract based on the orderId of the order passed.
        SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[orderId];

        ///@notice If the order has already been removed from the contract revert.
        if (order.orderId == bytes32(0)) {
            revert DuplicateOrderIdsInOrderGroup();
        }
        ///@notice Remove the order from the system
        delete orderIdToSandboxLimitOrder[orderId];
        delete addressToOrderIds[order.owner][orderId];

        ///@notice Decrement from total orders per address
        --totalOrdersPerAddress[order.owner];

        ///@notice Decrement totalOrdersQuantity on order.tokenIn for order owner
        decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.amountInRemaining
        );

        ///@notice Update the status of the order to filled
        addressToOrderIds[order.owner][order.orderId] = OrderType
            .FilledSandboxLimitOrder;
    }

    /// @notice Helper function to get the total order value on a specific token for the msg.sender.
    /// @param token - Token address to get total order value on.
    /// @return totalOrderValue - The total value of orders that exist for the msg.sender on the specified token.
    function _getTotalOrdersValue(address token)
        internal
        view
        returns (uint256 totalOrderValue)
    {
        bytes32 totalOrdersValueKey = keccak256(abi.encode(msg.sender, token));
        return totalOrdersQuantity[totalOrdersValueKey];
    }

    ///@notice Decrement an owner's total order value on a specific token.
    ///@param token - Token address to decrement the total order value on.
    ///@param owner - Account address to decrement the total order value from.
    ///@param quantity - Amount to decrement the total order value by.
    function decrementTotalOrdersQuantity(
        address token,
        address owner,
        uint256 quantity
    ) internal {
        bytes32 totalOrdersValueKey = keccak256(abi.encode(owner, token));
        totalOrdersQuantity[totalOrdersValueKey] -= quantity;
    }

    ///@notice Update an owner's total order value on a specific token.
    ///@param token - Token address to update the total order value on.
    ///@param owner - Account address to update the total order value from.
    ///@param newQuantity - Amount set the the new total order value to.
    function updateTotalOrdersQuantity(
        address token,
        address owner,
        uint256 newQuantity
    ) internal {
        bytes32 totalOrdersValueKey = keccak256(abi.encode(owner, token));
        totalOrdersQuantity[totalOrdersValueKey] = newQuantity;
    }

    /// @notice Internal helper function to approximate the minimum gas credits needed for order execution.
    /// @param gasPrice - The Current gas price in gwei
    /// @param executionCost - The total execution cost for each order.
    /// @param userAddress - The account address that will be checked for minimum gas credits.
    /** @param multiplier - Multiplier value represented in e^3 to adjust the minimum gas requirement to 
        fulfill an order, accounting for potential fluctuations in gas price. For example, a multiplier of `1.5` 
        will be represented as `150` in the contract. **/
    /// @return minGasCredits - Total ETH required to cover the minimum gas credits for order execution.
    function _calculateMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 multiplier
    ) internal view returns (uint256 minGasCredits) {
        ///@notice Get the total amount of active orders for the userAddress
        uint256 totalOrderCount = totalOrdersPerAddress[userAddress];

        ///@notice Calculate the minimum gas credits needed for execution of all active orders for the userAddress.
        uint256 minimumGasCredits = totalOrderCount * gasPrice * executionCost;

        if (multiplier != 1) {
            minimumGasCredits = (minimumGasCredits * multiplier) / ONE_HUNDRED;
        }

        ///@notice Divide by 100 to adjust the minimumGasCredits to totalOrderCount*gasPrice*executionCost*1.5.
        return minimumGasCredits;
    }

    /// @notice Internal helper function to check if user has the minimum gas credit requirement for all current orders.
    /// @param gasPrice - The current gas price in gwei.
    /// @param executionCost - The cost of gas to exececute an order.
    /// @param userAddress - The account address that will be checked for minimum gas credits.
    /// @param userGasCreditBalance - The current gas credit balance of the userAddress.
    /// @return bool - Indicates whether the user has the minimum gas credit requirements.
    function _hasMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 userGasCreditBalance,
        uint256 multipler
    ) internal view returns (bool) {
        return
            userGasCreditBalance >=
            _calculateMinGasCredits(
                gasPrice,
                executionCost,
                userAddress,
                multipler
            );
    }

    function getAllOrderIdsLength(address owner) public view returns (uint256) {
        return addressToAllOrderIds[owner].length;
    }

    ///@notice Get all of the order Ids matching the targetOrderType for a given address
    ///@param owner - Target address to get all order Ids for.
    ///@param targetOrderType - Target orderType to retrieve from all orderIds.
    ///@param orderOffset - The first order to start from when checking orderstatus. For example, if order offset is 2, the function will start checking orderId status from the second order.
    ///@param length - The amount of orders to check order status for.
    ///@return - Array of orderIds matching the targetOrderType
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
}
