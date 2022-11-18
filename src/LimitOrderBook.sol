// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "./interfaces/IOrderBook.sol";
import "./interfaces/ISwapRouter.sol";
import "./lib/ConveyorMath.sol";
import "./test/utils/Console.sol";
import "./interfaces/ILimitOrderExecutor.sol";
import "./GasOracle.sol";

/// @title LimitOrderBook
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Contract to maintain active orders in limit order system.
contract LimitOrderBook is GasOracle {
    address immutable LIMIT_ORDER_EXECUTOR;

    ///@notice The gas credit buffer is the multiplier applied to the minimum gas credits necessary to place an order. This ensures that the gas credits stored for an order have a buffer in case of gas price volatility.
    ///@notice The gas credit buffer is divided by 100, making the GAS_CREDIT_BUFFER a multiplier of 1.5x,
    uint256 constant GAS_CREDIT_BUFFER = 150;

    ///@notice The execution cost of fufilling a LimitOrder with a standard ERC20 swap from tokenIn to tokenOut
    uint256 immutable LIMIT_ORDER_EXECUTION_GAS_COST;

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
        uint256 _limitOrderExecutionGasCost
    ) GasOracle(_gasOracle) {
        require(
            _limitOrderExecutor != address(0),
            "limitOrderExecutor address is address(0)"
        );
        WETH = _weth;
        USDC = _usdc;
        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
        LIMIT_ORDER_EXECUTION_GAS_COST = _limitOrderExecutionGasCost;
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

    enum OrderType {
        None,
        PendingLimitOrder,
        FilledLimitOrder,
        CanceledLimitOrder
    }

    //----------------------State Structures------------------------------------//

    ///@notice Mapping from an orderId to its order.
    mapping(bytes32 => LimitOrder) internal orderIdToLimitOrder;

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
    ///@dev The orderNonce is set to 1 intially, and is always incremented by 2, so that the nonce is always odd, ensuring that there are not collisions with the orderIds from the SandboxLimitOrderBook
    uint256 orderNonce = 1;

    //----------------------Functions------------------------------------//

    ///@notice Gets an active order by the orderId. If the order does not exist, the return value will be bytes(0)
    function getLimitOrderById(bytes32 orderId)
        public
        view
        returns (LimitOrder memory)
    {
        LimitOrder memory order = orderIdToLimitOrder[orderId];
        return order;
    }

    ///@notice Places a new order (or group of orders) into the system.
    ///@param orderGroup - List of newly created orders to be placed.
    /// @return orderIds - Returns a list of orderIds corresponding to the newly placed orders.
    function placeLimitOrder(LimitOrder[] calldata orderGroup)
        public
        payable
        returns (bytes32[] memory)
    {
        _checkSufficientGasCreditsForOrderPlacement(orderGroup.length);

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
                revert IncongruentInputTokenInOrderGroup(
                    newOrder.tokenIn,
                    orderToken
                );
            }

            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
            if (newOrder.tokenOut == newOrder.tokenIn) {
                revert TokenInIsTokenOut();
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
                orderNonce += 2;
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
            addressToOrderIds[msg.sender][orderId] = OrderType
                .PendingLimitOrder;

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
    function _checkSufficientGasCreditsForOrderPlacement(uint256 numberOfOrders)
        internal
    {
        ///@notice Cache the gasPrice and the userGasCreditBalance
        uint256 gasPrice = getGasPrice();
        uint256 userGasCreditBalance = ILimitOrderExecutor(LIMIT_ORDER_EXECUTOR)
            .gasCreditBalance(msg.sender);

        ///@notice Get the total amount of active orders for the userAddress
        uint256 totalOrderCount = totalOrdersPerAddress[msg.sender];

        ///@notice Calculate the minimum gas credits needed for execution of all active orders for the userAddress.
        uint256 minimumGasCredits = (totalOrderCount + numberOfOrders) *
            gasPrice *
            LIMIT_ORDER_EXECUTION_GAS_COST *
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

            ILimitOrderExecutor(LIMIT_ORDER_EXECUTOR).updateGasCreditBalance(
                msg.sender,
                userGasCreditBalance + msg.value
            );
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
        }
    }

    ///@notice Function to update the price or quantity of an active Limit Order.
    ///@param orderId - The orderId of the Limit Order.
    ///@param price - The new price of the Limit Order.
    ///@param quantity - The new quantity of the Limit Order.
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
        if (totalApprovedQuantity < quantity) {
            revert InsufficientAllowanceForOrderUpdate(
                order.tokenIn,
                totalApprovedQuantity,
                quantity
            );
        }

        ///@notice Update the order details stored in the system.
        orderIdToLimitOrder[order.orderId].price = price;
        orderIdToLimitOrder[order.orderId].quantity = quantity;

        ///@notice Emit an updated order event with the orderId that was updated
        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = orderId;
        emit OrderUpdated(orderIds);
    }

    ///@notice Remove an order from the system if the order exists.
    /// @param orderId - The orderId that corresponds to the order that should be canceled.
    function cancelOrder(bytes32 orderId) public {
        ///@notice Get the order details
        LimitOrder memory order = orderIdToLimitOrder[orderId];

        if (order.orderId == bytes32(0)) {
            revert OrderDoesNotExist(orderId);
        }

        if (order.owner != msg.sender) {
            revert MsgSenderIsNotOrderOwner();
        }

        ///@notice Delete the order from orderIdToOrder mapping
        delete orderIdToLimitOrder[orderId];

        ///@notice Delete the orderId from addressToOrderIds mapping
        delete addressToOrderIds[msg.sender][orderId];

        ///@notice Decrement the total orders for the msg.sender
        --totalOrdersPerAddress[msg.sender];

        ///@notice Decrement the order quantity from the total orders quantity
        _decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.quantity
        );

        ///@notice Update the status of the order to canceled
        addressToOrderIds[order.owner][order.orderId] = OrderType
            .CanceledLimitOrder;

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

    ///@notice Function to remove an order from the system.
    ///@param orderId - The orderId that should be removed from the system.
    function _removeOrderFromSystem(bytes32 orderId) internal {
        LimitOrder memory order = orderIdToLimitOrder[orderId];

        ///@notice Remove the order from the system
        delete orderIdToLimitOrder[orderId];

        ///@notice Decrement from total orders per address
        --totalOrdersPerAddress[order.owner];

        ///@notice Decrement totalOrdersQuantity on order.tokenIn for order owner
        _decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.quantity
        );
    }

    ///@notice Function to resolve an order as completed.
    ///@param orderId - The orderId that should be resolved from the system.
    function _resolveCompletedOrder(bytes32 orderId, OrderType orderType)
        internal
    {
        ///@notice Grab the order currently in the state of the contract based on the orderId of the order passed.
        LimitOrder memory order = orderIdToLimitOrder[orderId];

        ///@notice If the order has already been removed from the contract revert.
        if (order.orderId == bytes32(0)) {
            revert DuplicateOrderIdsInOrderGroup();
        }

        ///@notice Remove the order from the system
        delete orderIdToLimitOrder[orderId];
        delete addressToOrderIds[order.owner][orderId];

        ///@notice Decrement from total orders per address
        --totalOrdersPerAddress[order.owner];

        ///@notice Decrement totalOrdersQuantity on order.tokenIn for order owner
        _decrementTotalOrdersQuantity(
            order.tokenIn,
            order.owner,
            order.quantity
        );

        ///@notice Update the status of the order to filled
        addressToOrderIds[order.owner][order.orderId] = OrderType
            .FilledLimitOrder;
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
    function _decrementTotalOrdersQuantity(
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
