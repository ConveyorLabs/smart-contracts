// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./GasOracle.sol";
import "./ConveyorErrors.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/ISwapRouter.sol";
import "./lib/ConveyorMath.sol";

/// @title OrderBook
/// @author 0xKitsune, LeytonTaylor, Conveyor Labs
/// @notice Contract to maintain active orders in limit order system.
contract OrderBook is GasOracle {
    address immutable LIMIT_ORDER_EXECUTOR;

    uint256 constant GAS_CREDIT_SHIFT = 150;
    uint256 constant GAS_CREDIT_SHIFT_NORMALIZED = 100;
    ///@notice Fee subsidy if paying fee at Order Placement time.
    ///@dev Fee must either be paid to the placeOrder function or be viable to be paid from the gas credit balance. The order will get a 20% discount on the fee if paid at placement but this is not a requirement.
    uint128 constant FEE_SUBSIDY = 14757395258967642000;
    address immutable WETH;
    address immutable USDC;

    //----------------------Constructor------------------------------------//

    constructor(
        address _gasOracle,
        address _limitOrderExecutor,
        address _weth,
        address _usdc
    ) GasOracle(_gasOracle) {
        require(
            _limitOrderExecutor != address(0),
            "limitOrderExecutor address is address(0)"
        );
        WETH = _weth;
        USDC = _usdc;
        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
    }

    //----------------------Events------------------------------------//
    /**@notice Event that is emitted when a new order is placed. For each order that is placed, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderPlaced(bytes32[] orderIds);

    /**@notice Event that is emitted when an order is cancelled. For each order that is cancelled, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderCancelled(bytes32[] orderIds);

    /**@notice Event that is emitted when a new order is update. For each order that is updated, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderUpdated(bytes32[] orderIds);

    /**@notice Event that is emitted when an order is filled. For each order that is filled, the corresponding orderId is added
    to the orderIds param. 
     */
    event OrderFufilled(bytes32[] orderIds);

    //----------------------Structs------------------------------------//

    ///@notice Struct containing Order details for any limit order
    ///@param buy - Indicates if the order is a buy or sell
    ///@param taxed - Indicates if the tokenIn or tokenOut is taxed. This will be set to true if one or both tokens are taxed.
    ///@param lastRefreshTimestamp - Unix timestamp representing the last time the order was refreshed.
    ///@param expirationTimestamp - Unix timestamp representing when the order should expire.
    ///@param feeIn - The Univ3 liquidity pool fee for the tokenIn/Weth pairing.
    ///@param feeOut - The Univ3 liquidity pool fee for the tokenOut/Weth pairing.
    ///@param taxIn - The token transfer tax on tokenIn.
    ///@param price - The execution price representing the spot price of tokenIn/tokenOut that the order should be filled at. This is represented as a 64x64 fixed point number.
    ///@param amountOutMin - The minimum amount out that the order owner is willing to accept. This value is represented in tokenOut.
    ///@param quantity - The amount of tokenIn that the order use as the amountIn value for the swap (represented in amount * 10**tokenInDecimals).
    ///@param owner - The owner of the order. This is set to the msg.sender at order placement.
    ///@param tokenIn - The tokenIn for the order.
    ///@param tokenOut - The tokenOut for the order.
    ///@param orderId - Unique identifier for the order.
    struct LimitOrder {
        bool buy;
        bool taxed;
        bool stoploss;
        uint32 lastRefreshTimestamp;
        uint32 expirationTimestamp;
        uint24 feeIn;
        uint24 feeOut;
        uint16 taxIn;
        uint128 price;
        uint128 amountOutMin;
        uint128 quantity;
        address owner;
        address tokenIn;
        address tokenOut;
        bytes32 orderId;
    }

    ///@notice Struct containing Order details for any limit order
    ///@param buy - Indicates if the order is a buy or sell
    ///@param lastRefreshTimestamp - Unix timestamp representing the last time the order was refreshed.
    ///@param expirationTimestamp - Unix timestamp representing when the order should expire.
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
        bool prePayFee;
        uint32 lastRefreshTimestamp;
        uint32 expirationTimestamp;
        uint128 fee;
        address quoteWethLiquidSwapPool;
        uint128 amountInRemaining;
        uint128 amountOutRemaining;
        address owner;
        address tokenIn;
        address tokenOut;
        bytes32 orderId;
    }

    enum OrderType {
        None,
        LimitOrder,
        SandboxLimitOrder
    }

    //----------------------State Structures------------------------------------//

    ///@notice Mapping from an orderId to its order.
    mapping(bytes32 => LimitOrder) internal orderIdToLimitOrder;

    ///@notice Mapping from an orderId to its order.
    mapping(bytes32 => SandboxLimitOrder) internal orderIdToSandboxLimitOrder;

    ///@notice Mapping to find the total orders quantity for a specific token, for an individual account
    ///@notice The key is represented as: keccak256(abi.encode(owner, token));
    mapping(bytes32 => uint256) public totalOrdersQuantity;

    ///@notice Mapping to check if an order exists, as well as get all the orders for an individual account.
    ///@dev ownerAddress -> orderId -> OrderType
    mapping(address => mapping(bytes32 => OrderType)) public addressToOrderIds;

    ///@notice Mapping to store the number of total orders for an individual account
    mapping(address => uint256) public totalOrdersPerAddress;

    ///@notice Mapping to store all of the orderIds for a given address including cancelled, pending and fuilled orders.
    mapping(address => bytes32[]) public addressToAllOrderIds;

    ///@notice Mapping to store all of the fufilled orderIds for a given address.
    mapping(address => mapping(bytes32 => bool))
        public addressToFufilledOrderIds;

    ///@notice Mapping to hold fee balances for accounts.
    mapping(address => uint256) public feeBalance;

    ///@notice Mapping to hold locked fee balances for accounts.
    mapping(address => uint256) public lockedFeeBalance;

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
            ///@notice If the order does not exist, revert.

            return (OrderType.None, new bytes(0));
        }

        if (orderType == OrderType.LimitOrder) {
            LimitOrder memory limitOrder = orderIdToLimitOrder[orderId];
            return (OrderType.LimitOrder, abi.encode(limitOrder));
        } else {
            SandboxLimitOrder
                memory sandboxLimitOrder = orderIdToSandboxLimitOrder[orderId];
            return (OrderType.SandboxLimitOrder, abi.encode(sandboxLimitOrder));
        }
    }

    //TODO: check if these can be internal
    function getLimitOrderById(bytes32 orderId)
        public
        view
        returns (LimitOrder memory)
    {
        LimitOrder memory order = orderIdToLimitOrder[orderId];
        return order;
    }

    //TODO: check if these can be internal
    function getSandboxLimitOrderById(bytes32 orderId)
        public
        view
        returns (SandboxLimitOrder memory)
    {
        return orderIdToSandboxLimitOrder[orderId];
    }

    ///@notice Places a new order (or group of orders) into the system.
    ///@param orderGroup - List of newly created orders to be placed.
    /// @return orderIds - Returns a list of orderIds corresponding to the newly placed orders.
    function placeLimitOrder(LimitOrder[] calldata orderGroup)
        public
        returns (bytes32[] memory)
    {
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
            LimitOrder memory newOrder = orderGroup[i];

            ///@notice Increment the total value of orders by the quantity of the new order
            updatedTotalOrdersValue += newOrder.quantity;

            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
            if (!(orderToken == newOrder.tokenIn)) {
                revert IncongruentTokenInOrderGroup();
            }

            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
            if (tokenBalance < updatedTotalOrdersValue) {
                revert InsufficientWalletBalance();
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
            orderIdToLimitOrder[orderId] = newOrder;

            ///@notice Add the orderId to the addressToOrderIds mapping
            addressToOrderIds[msg.sender][orderId] = OrderType.LimitOrder;

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
            revert InsufficientAllowanceForOrderPlacement();
        }

        ///@notice Emit an OrderPlaced event to notify the off-chain executors that a new order has been placed.
        emit OrderPlaced(orderIds);

        return orderIds;
    }

    ///@notice Places a new order of multicall type (or group of orders) into the system.
    ///@param orderGroup - List of newly created orders to be placed.
    /// @return orderIds - Returns a list of orderIds corresponding to the newly placed orders.
    function placeSandboxLimitOrder(SandboxLimitOrder[] calldata orderGroup)
        public
        payable
        returns (bytes32[] memory)
    {
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

            {
                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
                if (newOrder.prePayFee) {
                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
                    (SwapRouter.SpotReserve memory spRes, ) = IOrderRouter(
                        LIMIT_ORDER_EXECUTOR
                    )._calculateV2SpotPrice(
                            orderToken,
                            WETH,
                            IOrderRouter(LIMIT_ORDER_EXECUTOR)
                            .dexes()[0].factoryAddress,
                            IOrderRouter(LIMIT_ORDER_EXECUTOR)
                            .dexes()[0].initBytecode
                        );
                    uint256 tokenAWethSpotPrice = spRes.spotPrice;

                    if (!(tokenAWethSpotPrice == 0)) {
                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn)
                            .decimals();
                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
                        uint256 relativeWethValue = tokenInDecimals <= 18
                            ? ConveyorMath.mul128U(
                                tokenAWethSpotPrice,
                                newOrder.amountInRemaining
                            ) * 10**(18 - tokenInDecimals)
                            : ConveyorMath.mul128U(
                                tokenAWethSpotPrice,
                                newOrder.amountInRemaining
                            ) / 10**(tokenInDecimals - 18);
                        ///@notice Set the minimum fee to the fee*wethValue*subsidy.
                        uint128 minFeeReceived = uint128(
                            ConveyorMath.mul64U(
                                ConveyorMath.mul64x64(
                                    IOrderRouter(LIMIT_ORDER_EXECUTOR)
                                        ._calculateFee(
                                            uint128(relativeWethValue),
                                            USDC,
                                            WETH
                                        ),
                                    FEE_SUBSIDY
                                ),
                                relativeWethValue
                            )
                        );
                        ///@notice If the msg.value + unlocked balance can't cover the fee revert.
                        if (
                            !(feeBalance[msg.sender] + msg.value >=
                                minFeeReceived)
                        ) {
                            revert InsufficientFeeCreditBalanceForOrderExecution();
                        }
                        ///@notice If the msg.value is less than minFeeReceived then use the addresses feeBalance to cover the difference.
                        if (msg.value < minFeeReceived) {
                            ///@notice Increment the locked fee balance
                            lockedFeeBalance[msg.sender] += minFeeReceived;
                            ///@notice Decrement the feeBalance of the msg.sender by the amount used to cover the fee.
                            feeBalance[msg.sender] -=
                                minFeeReceived -
                                msg.value;
                        } else {
                            ///@notice If the msg.value can cover the minFeeReceived then simply increment the locked fee balance by minFeeReceived.
                            lockedFeeBalance[msg.sender] += minFeeReceived;
                            ///@notice Increment the senders feeBalance by msg.value -minFeeReceived to account for over paying.
                            feeBalance[msg.sender] +=
                                msg.value -
                                minFeeReceived;
                        }
                        ///@notice Set the minFeeReceived to 0 as the fee has already been paid at placement.
                        newOrder.fee = 0;
                    }
                } else {
                    ///@notice Calculate the minimum fee for the order to be taken out at execution time.
                    (
                        newOrder.fee,
                        newOrder.quoteWethLiquidSwapPool
                    ) = IOrderRouter(LIMIT_ORDER_EXECUTOR)
                        .calculateSandboxFeeAmount(
                            newOrder.tokenIn,
                            WETH,
                            newOrder.amountInRemaining,
                            USDC
                        );
                }
            }

            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
            if (!(orderToken == newOrder.tokenIn)) {
                revert IncongruentTokenInOrderGroup();
            }

            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
            if (tokenBalance < updatedTotalOrdersValue) {
                revert InsufficientWalletBalance();
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
                .SandboxLimitOrder;

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
            revert InsufficientAllowanceForOrderPlacement();
        }

        ///@notice Emit an OrderPlaced event to notify the off-chain executors that a new order has been placed.
        emit OrderPlaced(orderIds);

        return orderIds;
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

        if(orderType == OrderType.LimitOrder){
            _updateLimitOrder(orderId, price, quantity);
        }else{
            _updateSandboxLimitOrder(orderId, quantity, uint128(ConveyorMath.mul64U(price, quantity)));
        }
        
    }

    function _updateLimitOrder(
        bytes32 orderId,
        uint128 price,
        uint128 quantity
    ) internal {
        ///@notice Get the existing order that will be replaced with the new order
        LimitOrder memory order = orderIdToLimitOrder[orderId];

        ///@notice Get the total orders value for the msg.sender on the tokenIn
        uint256 totalOrdersValue = _getTotalOrdersValue(order.tokenIn);

        ///@notice Update the total orders value
        totalOrdersValue += quantity;
        totalOrdersValue -= order.quantity;

        ///@notice If the wallet does not have a sufficient balance for the updated total orders value, revert.
        if (IERC20(order.tokenIn).balanceOf(msg.sender) < totalOrdersValue) {
            revert InsufficientWalletBalance();
        }

        ///@notice Update the total orders quantity
        updateTotalOrdersQuantity(order.tokenIn, msg.sender, totalOrdersValue);

        ///@notice Get the total amount approved for the ConveyorLimitOrder contract to spend on the orderToken.
        uint256 totalApprovedQuantity = IERC20(order.tokenIn).allowance(
            msg.sender,
            address(LIMIT_ORDER_EXECUTOR)
        );

        ///@notice If the total approved quantity is less than the newOrder.quantity, revert.
        if (totalApprovedQuantity < quantity) {
            revert InsufficientAllowanceForOrderUpdate();
        }

        ///@notice Update the order details stored in the system.
        orderIdToLimitOrder[order.orderId].price = price;
        orderIdToLimitOrder[order.orderId].quantity = quantity;

        ///@notice Emit an updated order event with the orderId that was updated
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        emit OrderUpdated(orderIds);
    }

    function _updateSandboxLimitOrder(
        bytes32 orderId,
        uint128 amountInRemaining,
        uint128 amountOutRemaining
    ) internal {
        ///@notice Get the existing order that will be replaced with the new order
        SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[orderId];
        if(order.orderId==bytes32(0)){
            revert OrderDoesNotExist(orderId);
        }
        ///@notice Get the total orders value for the msg.sender on the tokenIn
        uint256 totalOrdersValue = _getTotalOrdersValue(order.tokenIn);

        ///@notice Update the total orders value
        totalOrdersValue += amountInRemaining;
        totalOrdersValue -= order.amountInRemaining;

        ///@notice If the wallet does not have a sufficient balance for the updated total orders value, revert.
        if (IERC20(order.tokenIn).balanceOf(msg.sender) < totalOrdersValue) {
            revert InsufficientWalletBalance();
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
            revert InsufficientAllowanceForOrderUpdate();
        }

        ///@notice Update the order details stored in the system.
        orderIdToSandboxLimitOrder[order.orderId].amountInRemaining = amountInRemaining;
        orderIdToSandboxLimitOrder[order.orderId].amountOutRemaining = amountOutRemaining;

        ///@notice Emit an updated order event with the orderId that was updated
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        emit OrderUpdated(orderIds);
    }

    function cancelOrder(bytes32 orderId) public {
        ///@notice Check if the order exists
        OrderType orderType = addressToOrderIds[msg.sender][orderId];

        if (orderType == OrderType.None) {
            ///@notice If the order does not exist, revert.
            revert OrderDoesNotExist(orderId);
        }

        if (orderType == OrderType.LimitOrder) {
            _cancelLimitOrder(orderId);
        } else {
            _cancelSandboxLimitOrder(orderId);
        }
    }

    ///@notice Remove an order from the system if the order exists.
    /// @param orderId - The orderId that corresponds to the order that should be cancelled.
    function _cancelLimitOrder(bytes32 orderId) internal {
        ///@notice Get the order details
        LimitOrder memory order = orderIdToLimitOrder[orderId];

        ///@notice Delete the order from orderIdToOrder mapping
        delete orderIdToLimitOrder[orderId];

        ///@notice Delete the orderId from addressToOrderIds mapping
        delete addressToOrderIds[msg.sender][orderId];

        ///@notice Decrement the total orders for the msg.sender
        --totalOrdersPerAddress[msg.sender];

        ///@notice Decrement the order quantity from the total orders quantity
        decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.quantity
        );

        ///@notice Emit an event to notify the off-chain executors that the order has been cancelled.
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCancelled(orderIds);
    }

    ///@notice Remove an order from the system if the order exists.
    /// @param orderId - The orderId that corresponds to the order that should be cancelled.
    function _cancelSandboxLimitOrder(bytes32 orderId) internal {
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

        ///@notice Emit an event to notify the off-chain executors that the order has been cancelled.
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderCancelled(orderIds);
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

    ///TODO: need to update this
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

        orderIdToSandboxLimitOrder[orderId].amountInRemaining =
            order.amountInRemaining -
            amountInFilled;

        orderIdToSandboxLimitOrder[orderId].amountOutRemaining =
            order.amountOutRemaining -
            amountOutFilled;
    }

    //TODO: there are a lot of places where we have the order details and then pass in the orderId which is redundant, we can save gas
    //by passing the order or having two separate remove order form system functions.

    ///@notice Function to remove an order from the system.
    ///@param orderId - The orderId that should be removed from the system.
    function _removeOrderFromSystem(bytes32 orderId, OrderType orderType)
        internal
    {
        if (orderType == OrderType.LimitOrder) {
            LimitOrder memory order = orderIdToLimitOrder[orderId];

            ///@notice Remove the order from the system
            delete orderIdToLimitOrder[orderId];

            ///@notice Decrement from total orders per address
            --totalOrdersPerAddress[order.owner];

            ///@notice Decrement totalOrdersQuantity on order.tokenIn for order owner
            decrementTotalOrdersQuantity(
                order.tokenIn,
                order.owner,
                order.quantity
            );
        } else {
            ///@dev the None order type can not reach here so we can use `else`
            SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[
                orderId
            ];

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
    }

    ///@notice Function to resolve an order as completed.
    ///@param orderId - The orderId that should be resolved from the system.
    function _resolveCompletedOrder(bytes32 orderId, OrderType orderType)
        internal
    {
        if (orderType == OrderType.LimitOrder) {
            ///@notice Grab the order currently in the state of the contract based on the orderId of the order passed.
            LimitOrder memory order = orderIdToLimitOrder[orderId];

            ///@notice If the order has already been removed from the contract revert.
            if (order.orderId == bytes32(0)) {
                revert DuplicateOrdersInExecution();
            }
            ///@notice Remove the order from the system
            delete orderIdToLimitOrder[orderId];
            delete addressToOrderIds[order.owner][orderId];

            ///@notice Decrement from total orders per address
            --totalOrdersPerAddress[order.owner];

            ///@notice Decrement totalOrdersQuantity on order.tokenIn for order owner
            decrementTotalOrdersQuantity(
                order.tokenIn,
                order.owner,
                order.quantity
            );
        } else {
            ///@dev the None order type can not reach here so we can use `else`

            ///@notice Grab the order currently in the state of the contract based on the orderId of the order passed.
            SandboxLimitOrder memory order = orderIdToSandboxLimitOrder[
                orderId
            ];

            ///@notice If the order has already been removed from the contract revert.
            if (order.orderId == bytes32(0)) {
                revert DuplicateOrdersInExecution();
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
        }
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
        uint256 minimumGasCredits = totalOrderCount *
            gasPrice *
            executionCost *
            multiplier;
        ///@notice Divide by 100 to adjust the minimumGasCredits to totalOrderCount*gasPrice*executionCost*1.5.
        return minimumGasCredits / GAS_CREDIT_SHIFT_NORMALIZED;
    }

    /// @notice Internal helper function to check if user has the minimum gas credit requirement for all current orders.
    /// @param gasPrice - The current gas price in gwei.
    /// @param executionCost - The cost of gas to exececute an order.
    /// @param userAddress - The account address that will be checked for minimum gas credits.
    /// @param gasCreditBalance - The current gas credit balance of the userAddress.
    /// @return bool - Indicates whether the user has the minimum gas credit requirements.
    function _hasMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 gasCreditBalance
    ) internal view returns (bool) {
        return
            gasCreditBalance >=
            _calculateMinGasCredits(
                gasPrice,
                executionCost,
                userAddress,
                GAS_CREDIT_SHIFT
            );
    }

    ///@notice Get all of the order Ids for a given address
    ///@param owner - Target address to get all order Ids for.
    /**@return - Nested array of order Ids organized by status. 
    The first array represents pending orders.
    The second array represents fufilled orders.
    The third array represents cancelled orders.
    **/
    function getAllOrderIds(address owner)
        public
        view
        returns (bytes32[][] memory)
    {
        //TODO: have to figure this out
        // bytes32[] memory allOrderIds = addressToAllOrderIds[owner];
        // bytes32[][] memory orderIdsStatus = new bytes32[][](3);
        // bytes32[] memory fufilledOrderIds = new bytes32[](allOrderIds.length);
        // uint256 fufilledOrderIdsIndex = 0;
        // bytes32[] memory pendingOrderIds = new bytes32[](allOrderIds.length);
        // uint256 pendingOrderIdsIndex = 0;
        // bytes32[] memory cancelledOrderIds = new bytes32[](allOrderIds.length);
        // uint256 cancelledOrderIdsIndex = 0;
        // for (uint256 i = 0; i < allOrderIds.length; ++i) {
        //     bytes32 orderId = allOrderIds[i];
        //     //If it is fufilled
        //     if (addressToFufilledOrderIds[owner][orderId]) {
        //         fufilledOrderIds[fufilledOrderIdsIndex] = orderId;
        //         ++fufilledOrderIdsIndex;
        //     } else if (addressToOrderIds[owner][orderId]) {
        //         //Else if the order is pending
        //         pendingOrderIds[pendingOrderIdsIndex] = orderId;
        //         ++pendingOrderIdsIndex;
        //     } else {
        //         //Else if the order has been cancelled
        //         cancelledOrderIds[cancelledOrderIdsIndex] = orderId;
        //         ++cancelledOrderIdsIndex;
        //     }
        // }
        // ///Reassign length of each array
        // uint256 pendingOrderIdsLength = pendingOrderIds.length;
        // uint256 fufilledOrderIdsLength = fufilledOrderIds.length;
        // uint256 cancelledOrderIdsLength = cancelledOrderIds.length;
        // assembly {
        //     mstore(pendingOrderIds, pendingOrderIdsLength)
        //     mstore(fufilledOrderIds, fufilledOrderIdsLength)
        //     mstore(cancelledOrderIds, cancelledOrderIdsLength)
        // }
        // orderIdsStatus[0] = pendingOrderIds;
        // orderIdsStatus[1] = fufilledOrderIds;
        // orderIdsStatus[2] = cancelledOrderIds;
        // return orderIdsStatus;
    }
}
