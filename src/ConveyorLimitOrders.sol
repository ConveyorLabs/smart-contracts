// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

contract ConveyorLimitOrders {

    /// @notice enumeration of event type to be emmited from eoa function calls for, for queryable beacon event listening
    enum EventType{
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
    struct Order{
        address token;
        bytes32 orderId;
        OrderType orderType;
        uint256 price;
        uint256 quantity;
    }

    /// @notice Struct containing mapping(orderId => Order) where 'Order' is the order struct containing the properties of the Order
    struct OrderGroup{
        mapping(uint256 => Order) Orders;
        uint256 totalOrdersValue;
    }

    /// @notice mapping from mapping(eoaAddress => mapping(token => OrderGroup)) to store the current Active orders in Conveyor state structure
    mapping(address => mapping(address => OrderGroup)) ActiveOrders;

    /// @notice Add user's order into the Active order's mapping conditionally if the oder passes all of the safety check criterion
    function placeOrder(Order[] orders){
        //security checks

        //uses msg.sender as the eoaAccount placing the order

        //iterate through orders and place order
        for (i=0; i<=orders.length; ++i;) {
            //does the wallet have enough tokens to place the order + active order value on the token
            
            //make new order 
            
            //add to collection
            

        }
        //emit event for placing an order
        //ex. emit placeOrder(msg.sender, orders)
    }

    /// @notice Update mapping(uint256 => Order) in Order struct from identifier orderId to new 'order' value passed as @param 
    /// @param order the order to which the caller is updating from the OrderGroup struct
    function updateOrder(Order order){
        //security checks
        //check that order exists
        /// @dev Update OrderGroup struct in ActiveOders mapping of identifier oderId to updated order i.e  mapping(uint256 => Order) Orders;
        ActiveOrders[msg.sender][order.token].Orders[order.orderId] = order;

        //emit order updated
        //ex. emit updateOrder(msg.sender, order)

    }

    /// @notice Remove Order order from OrderGroup mapping by identifier orderId conditionally if order exists already in ActiveOrders
    /// @param order the order to which the caller is removing from the OrderGroup struct
    function cancelOrder(Order order){
        //security checks
        //check that orders exists
        /// @dev The logic should look something like this I believe because of the logic below
        /// @dev ActiveOrders[msg.sender][order.token].Orders will be mapping(uint256 => Order) Orders; 
        del ActiveOrders[msg.sender][order.token].Orders[order.orderId]
        //emit order canceled
        //ex. emit cancelOrder(msg.sender, order)

    }

    /// @notice cancel all orders relevant in ActiveOders mapping to the msg.sender i.e the function caller
    function cancelAllOrders(){
        //security checks

        //check that there is one or more orders

        //get all orders for the eoa first, this is pseudo code atm
        allOrders = orders[msg.sender];

        for (i=0; i<len(allOrders); ++i){
            cancelOrder(allOrders[i])
        }
        //emit all order cancel
        //ex. emit cancelAllOrders(msg.sender, allOrders)
    }

    ///@notice gets all open orders for a specific wallet
    function getOpenOrders() external view {
        return orders[msg.sender];
    }
}
