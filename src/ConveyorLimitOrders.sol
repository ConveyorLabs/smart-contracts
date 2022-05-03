// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/IERC20.sol";

contract ConveyorLimitOrders {
    //----------------------Modifiers------------------------------------//

    modifier onlyEOA() {
        require(msg.sender == tx.origin);
        _;
    }

    //----------------------Events------------------------------------//

    event OrderEvent(
        EventType indexed eventType,
        address indexed sender,
        Order[] indexed orders
    );
    
    event OrderCanceled(
        EventType indexed eventType, 
        address indexed sender,
        Order indexed order
    );

    //----------------------Errors------------------------------------//

    error OrderDoesNotExist(bytes32 orderId);
    error InsufficientWalletBalance();

    //TODO: rename this, bad name oof
    error IncongruentTokenInOrderGroup();

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

    //----------------------Structs------------------------------------//

    /// @notice Struct containing the token, orderId, OrderType enum type, price, and quantity for each order
    struct Order {
        address token;
        bytes32 orderId;
        OrderType orderType;
        uint256 price;
        uint256 quantity;
        bool exists;
    }

    /// @notice Struct containing mapping(orderId => Order) where 'Order' is the order struct containing the properties of the Order
    struct OrderGroup {
        mapping(bytes32 => Order) orders;
        uint256 totalOrderValue;
    }

    struct TokenToOrderGroup {
        mapping(address => OrderGroup) orderGroup;
    }

    //----------------------State Structures------------------------------------//

    /// @notice mapping from mapping(eoaAddress => mapping(token => OrderGroup)) to store the current Active orders in Conveyor state structure
    mapping(address => TokenToOrderGroup) ActiveOrders;

    //----------------------Functions------------------------------------//

    /// @notice Add user's order into the Active order's mapping conditionally if the oder passes all of the safety check criterion
    /// @param arrOrders := array of orders to be added to ActiveOrders mapping in OrderGroup struct
    function placeOrder(Order[][] calldata arrOrders) public {
        for (uint256 i = 0; i < arrOrders.length; ++i) {
            Order[] memory orders = arrOrders[i];
            //get the current token for the order array
            address currentToken = orders[i].token;

            //get the current totalOrderValue for all existing orders on the token
            uint256 totalOrderValue = ActiveOrders[msg.sender]
                .orderGroup[currentToken]
                .totalOrderValue;

            uint256 tokenBalance = IERC20(currentToken).balanceOf(msg.sender);

            for (uint256 j = 0; j < orders.length; ++j) {
                Order memory newOrder = orders[j];

                if (!(currentToken == newOrder.token)) {
                    revert IncongruentTokenInOrderGroup();
                }

                //add the order quant to total order value
                totalOrderValue += newOrder.quantity;

                //check if the wallet has a sufficient balance
                if (tokenBalance < totalOrderValue) {
                    revert InsufficientWalletBalance();
                }

                //add the order to active orders
                ActiveOrders[msg.sender].orderGroup[currentToken].orders[
                        newOrder.orderId
                    ] = newOrder;
            }

            //emit orders placed
            emit OrderEvent(EventType.PLACE, msg.sender, orders);
        }
    }

    /// @notice Update mapping(uint256 => Order) in Order struct from identifier orderId to new 'order' value passed as @param
    function updateOrder(Order calldata newOrder) public {
        Order memory oldOrder = ActiveOrders[msg.sender]
            .orderGroup[newOrder.token]
            .orders[newOrder.orderId];

        //check if the old order exists
        if (!oldOrder.exists) {
            revert OrderDoesNotExist(newOrder.orderId);
        }

        uint256 totalOrdersValue = ActiveOrders[msg.sender]
            .orderGroup[newOrder.token]
            .totalOrderValue;

        //adjust total orders value quanity
        totalOrdersValue -= newOrder.quantity + oldOrder.quantity;

        //check if the wallet has a sufficient balance
        if (IERC20(newOrder.token).balanceOf(msg.sender) < totalOrdersValue) {
            revert InsufficientWalletBalance();
        }

        //update totalOrdersValue for that token
        ActiveOrders[msg.sender]
            .orderGroup[newOrder.token]
            .totalOrderValue = totalOrdersValue;

        //update the order
        ActiveOrders[msg.sender].orderGroup[newOrder.token].orders[
            newOrder.orderId
        ] = newOrder;

        //emit order updated
        //TODO: still need to decide on contents of events

        Order[] memory orders;
        orders[0] = newOrder;
        emit OrderEvent(EventType.UPDATE, msg.sender, orders);
    }

    /// @notice Remove Order order from OrderGroup mapping by identifier orderId conditionally if order exists already in ActiveOrders
    /// @param order the order to which the caller is removing from the OrderGroup struct
    function cancelOrder(Order calldata order) public {
        
        /// Check if order exists in active orders. Revert if order does not exist
        if(!ActiveOrders[msg.sender].orderGroup[order.token].orders[order.orderId].exists){
            revert OrderDoesNotExist(order.orderId);
        }

        /// get the the order quantity of the calldata
        uint256 orderQuantity = ActiveOrders[msg.sender]
            .orderGroup[order.token]
            .orders[order.orderId]
            .quantity;

        //update totalOrdersValue to decrease by amount orderQuantity of the order being removed
        ActiveOrders[msg.sender]
            .orderGroup[order.token]
            .totalOrderValue -= orderQuantity;

        // Delete Order Orders[order.orderId] from ActiveOrders mapping
        delete ActiveOrders[msg.sender]
            .orderGroup[order.token]
            .orders[order.orderId];

        //emit order canceled
        //ex. emit cancelOrder(msg.sender, order)
        emit OrderCanceled(EventType.CANCEL, msg.sender, order);
    }

    /// @notice cancel all orders relevant in ActiveOders mapping to the msg.sender i.e the function caller
    function cancelAllOrders() public {
        //security checks

        //check that there is one or more orders

        //get all orders for the eoa first, this is pseudo code atm
        delete ActiveOrders[msg.sender];

        //emit all order cancel
        //pass in an empty list to signify that all orders have been canceled
        Order[] memory orders;
        emit OrderEvent(EventType.PLACE, msg.sender, orders);
    }

    function swapAndPlaceOrders() public {}

    ///@notice gets all open orders for a specific wallet from ActiveOrders mapping

    ///TODO: implement logic to do this
    // function getOpenOrders() external view returns (TokenToOrderGroup memory) {
    //     return ActiveOrders[msg.sender];
    // }

    /// @notice execute all orders passed from beacon matching order execution criteria. i.e. 'orderPrice' matches observable lp price for all orders
    /// @param orders := array of orders to be executed within the mapping
    function executeOrders(Order[] memory orders) external onlyEOA {
        //iterate through orders and try to fill order
        for (uint256 i = 0; i < orders.length; ++i) {
            Order memory order = orders[i];
            //check the execution price of the order

            //check the price of the lp

            //note: can either loop through and execute or aggregate and execute

            //loop through orders and see which ones hit the execution price

            //if execution price hit
            //add the order to executableOrders, update total

            //aggregate the value of all of the orders
        }
    }
}
