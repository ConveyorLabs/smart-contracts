// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

contract ConveyorLimitOrders {
    modifier onlyEOA() {
        require(msg.sender == tx.origin);
        _;
    }

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

    /// @notice Struct containing the token, orderId, OrderType enum type, price, and quantity for each order
    struct Order {
        address token;
        bytes32 orderId;
        OrderType orderType;
        uint256 price;
        uint256 quantity;
    }

    /// @notice Struct containing mapping(orderId => Order) where 'Order' is the order struct containing the properties of the Order
    struct OrderGroup {
        mapping(bytes32 => Order) Orders;
        uint256 totalOrdersValue;
    }

    /// @notice mapping from mapping(eoaAddress => mapping(token => OrderGroup)) to store the current Active orders in Conveyor state structure
    mapping(address => mapping(address => OrderGroup)) ActiveOrders;

    /// @notice Add user's order into the Active order's mapping conditionally if the oder passes all of the safety check criterion
    /// @param orders := array of orders to be added to ActiveOrders mapping in OrderGroup struct
    function placeOrder(Order[] calldata orders) public {
        //security checks

        //uses msg.sender as the eoaAccount placing the order

        //iterate through orders and place order
        for (uint256 i = 0; i <= orders.length; ++i) {
            //does the wallet have enough tokens to place the order + active order value on the token
            //make new order
            //add to collection
        }
        //emit event for placing an order
        //ex. emit placeOrder(msg.sender, orders)
    }

    /// @notice Update mapping(uint256 => Order) in Order struct from identifier orderId to new 'order' value passed as @param
    /// @param order the order to which the caller is updating from the OrderGroup struct
    function updateOrder(Order calldata order) public {
        //security checks
        //check that order exists
        /// @dev Update OrderGroup struct in ActiveOders mapping of identifier oderId to updated order i.e  mapping(bytes32 => Order) Orders;
        ActiveOrders[msg.sender][order.token].Orders[order.orderId] = order;

        //emit order updated
        //ex. emit updateOrder(msg.sender, order)
    }

    /// @notice Remove Order order from OrderGroup mapping by identifier orderId conditionally if order exists already in ActiveOrders
    /// @param order the order to which the caller is removing from the OrderGroup struct
    function cancelOrder(Order calldata order) public {
        //security checks
        //check that orders exists
        /// @dev The logic should look something like this I believe because of the logic below
        /// @dev ActiveOrders[msg.sender][order.token].Orders will be mapping(bytes32 => Order) Orders;
        delete ActiveOrders[msg.sender][order.token].Orders[order.orderId];
        //emit order canceled
        //ex. emit cancelOrder(msg.sender, order)
    }

    /// @notice cancel all orders relevant in ActiveOders mapping to the msg.sender i.e the function caller
    function cancelAllOrders() public {
        //security checks

        //check that there is one or more orders

        //get all orders for the eoa first, this is pseudo code atm
        delete ActiveOrders[msg.sender];

        //emit all order cancel
        //ex. emit cancelAllOrders(msg.sender, allOrders)
    }

    ///@notice gets all open orders for a specific wallet from ActiveOrders mapping
    function getOpenOrders() external view {
        return ActiveOrders[msg.sender];
    }

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
