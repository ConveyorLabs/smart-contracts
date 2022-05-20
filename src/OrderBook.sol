// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/token/IERC20.sol";

contract OrderBook {
    //----------------------Constructor------------------------------------//

    constructor() {}

    //----------------------Events------------------------------------//

    event OrderEvent(
        EventType indexed eventType,
        address indexed sender,
        bytes32[] indexed orderIds
    );

    //----------------------Enums------------------------------------//

    /// @notice enumeration of event type to be emmited from eoa function calls for, for queryable beacon event listening
    enum EventType {
        PLACE,
        UPDATE,
        CANCEL,
        CANCEL_ALL,
        FILLED,
        FAILED
    }

    /// @notice enumeration of type of Order to be executed within the 'Order' Struct
    enum OrderType {
        BUY,
        SELL,
        STOP,
        TAKE_PROFIT
    }

    //----------------------Errors------------------------------------//

    error OrderDoesNotExist(bytes32 orderId);
    error InsufficientWalletBalance();

    //TODO: rename this, bad name oof
    error IncongruentTokenInOrderGroup();

    //----------------------Structs------------------------------------//

    /// @notice Struct containing the token, orderId, OrderType enum type, price, and quantity for each order
    struct Order {
        address token;
        bytes32 orderId;
        OrderType orderType;
        uint256 price;
        uint256 quantity;
    }

    //----------------------State Structures------------------------------------//

    //order id  to order
    mapping(bytes32 => Order) orderIdToOrder;

    //struct to check if order exists, as well as get all orders for a wallet
    mapping(address => mapping(bytes32 => bool)) addressToOrderIds;

    //----------------------Functions------------------------------------//

    function getOrderById(
        address eoaAddress,
        address token,
        bytes32 orderId
    ) public view returns (Order memory order) {
        order = orderIdToOrder[orderId];
        return order;
    }

    /// @notice Add user's order into the Active order's mapping conditionally if the oder passes all of the safety check criterion
    /// @param orderGroup := array of orders to be added to ActiveOrders mapping in OrderGroup struct
    /// @return orderIds
    function placeOrder(Order[] calldata orderGroup)
        public
        returns (bytes32[] memory)
    {
        uint256 orderIdIndex;
        bytes32[] memory orderIds = new bytes32[](orderGroup.length);
        //token that the orders are being placed on
        address orderToken = orderGroup[0].token;

        //TODO: sum all orders to check against total order value
        uint256 totalOrdersValue;

        uint256 tokenBalance = IERC20(orderToken).balanceOf(msg.sender);

        for (uint256 i = 0; i < orderGroup.length; ++i) {
            Order memory newOrder = orderGroup[i];

            if (!(orderToken == newOrder.token)) {
                revert IncongruentTokenInOrderGroup();
            }

            totalOrdersValue += newOrder.quantity;

            //check if the wallet has a sufficient balance
            if (tokenBalance < totalOrdersValue) {
                revert InsufficientWalletBalance();
            }

            //TODO: create new order id construction that is simpler
            bytes32 orderId = keccak256(
                abi.encodePacked(
                    msg.sender,
                    block.timestamp,
                    orderToken,
                    newOrder.price,
                    i
                )
            );

            //TODO: add order to all necessary state

            //TODO: add the order to active orders

            orderIds[orderIdIndex] = orderId;
            ++orderIdIndex;
        }

        //emit orders placed
        emit OrderEvent(EventType.PLACE, msg.sender, orderIds);

        return orderIds;
    }

    /// @notice Update mapping(uint256 => Order) in Order struct from identifier orderId to new 'order' value passed as @param
    function updateOrder(Order calldata newOrder) public {
        //check if the old order exists

        bool orderExists = addressToOrderIds[msg.sender][newOrder.orderId];

        if (!orderExists) {
            revert OrderDoesNotExist(newOrder.orderId);
        }

        Order memory oldOrder = orderIdToOrder[newOrder.orderId];

        //TODO: get total order sum and make sure that the user has the balance for the new order

        // if (newOrder.quantity > oldOrder.quantity) {
        //     totalOrdersValue += newOrder.quantity - oldOrder.quantity;
        // } else {
        //     totalOrdersValue += oldOrder.quantity - newOrder.quantity;
        // }

        // //check if the wallet has a sufficient balance
        // if (IERC20(newOrder.token).balanceOf(msg.sender) < totalOrdersValue) {
        //     revert InsufficientWalletBalance();
        // }

        //update the order
        orderIdToOrder[oldOrder.orderId] = newOrder;

        //emit order updated
        //TODO: still need to decide on contents of events

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = newOrder.orderId;
        emit OrderEvent(EventType.UPDATE, msg.sender, orderIds);
    }

    /// @notice Remove Order order from OrderGroup mapping by identifier orderId conditionally if order exists already in ActiveOrders
    /// @param orderId the order to which the caller is removing from the OrderGroup struct
    function cancelOrder(bytes32 orderId) public {
        /// Check if order exists in active orders. Revert if order does not exist
        bool orderExists = addressToOrderIds[msg.sender][orderId];

        if (!orderExists) {
            revert OrderDoesNotExist(orderId);
        }

        Order memory order = orderIdToOrder[orderId];

        // Delete Order Orders[order.orderId] from ActiveOrders mapping
        delete orderIdToOrder[orderId];
        delete addressToOrderIds[msg.sender][orderId];

        bytes32[] memory orderIds = new bytes32[](1);
        orderIds[0] = order.orderId;
        emit OrderEvent(EventType.CANCEL, msg.sender, orderIds);
    }

    /// @notice cancel all orders relevant in ActiveOders mapping to the msg.sender i.e the function caller
    function cancelOrders(bytes32[] memory orderIds) public {
        bytes32[] memory canceledOrderIds = new bytes32[](orderIds.length);

        //check that there is one or more orders
        for (uint256 i = 0; i < orderIds.length; ++i) {
            bytes32 orderId = orderIds[i];
            bool orderExists = addressToOrderIds[msg.sender][orderId];

            if (!orderExists) {
                revert OrderDoesNotExist(orderId);
            }

            delete addressToOrderIds[msg.sender][orderId];
            delete orderIdToOrder[orderId];
            canceledOrderIds[i] = orderId;
        }

        emit OrderEvent(EventType.PLACE, msg.sender, canceledOrderIds);
    }
}
