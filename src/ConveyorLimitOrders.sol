// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/token/IERC20.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./test/utils/Console.sol";
import "../lib/libraries/uniswap/OracleLibrary.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
import "../lib/libraries/PriceLibrary.sol";

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

    //----------------------Factory/Router Address's------------------------------------//
    /// @dev 0-Uniswap V2 Factory, 1-Uniswap V3 Factory
    address[] dexFactories = [0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,0x1F98431c8aD98523631AE4a59f267346ea31F984];
   

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

    /// @notice Struct to store important Dex specifications
    struct Dex {
        address factoryAddress;
        bytes32 initBytecode;
        bool isUniV2;
    }
    //----------------------State Structures------------------------------------//

    /// @notice mapping from mapping(eoaAddress => mapping(token => OrderGroup)) to store the current Active orders in Conveyor state structure
    mapping(address => TokenToOrderGroup) ActiveOrders;

    /// @notice Array of dex structures to be used throughout the contract for pair spot price calculations
    Dex[] public dexes;

     //----------------------Constructor------------------------------------//

     constructor() {}

    //----------------------Functions------------------------------------//
   
    function getOrderById(
        address eoaAddress,
        address token,
        bytes32 orderId
    ) public view returns (Order memory order) {
        order = ActiveOrders[eoaAddress].orderGroup[token].orders[orderId];
    }

    /// @notice Add Dex struct to dexes array from arr _factory, and arr _hexDem
    /// @param _factory address[] dex factory address's to add
    /// @param _hexDem Factory address create2 deployment bytecode array
    /// @param isUniV2 Array of bool's indicating uniV2 status
    function addDex(address[] memory _factory, bytes32[] memory _hexDem, bool[] memory isUniV2) public {
        require((_factory.length == _hexDem.length && _hexDem.length== isUniV2.length), "Invalid input, Arr length mismatch");
        for(uint256 i = 0; i < _factory.length; i++){
            Dex memory d = Dex(_factory[i], _hexDem[i], isUniV2[i]);
            dexes.push(d);
        }
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

        //get the current totalOrderValue for all existing orders on the token
        uint256 totalOrderValue = ActiveOrders[msg.sender]
            .orderGroup[orderToken]
            .totalOrderValue;

        uint256 tokenBalance = IERC20(orderToken).balanceOf(msg.sender);

        for (uint256 i = 0; i < orderGroup.length; ++i) {
            Order memory newOrder = orderGroup[i];

            if (!(orderToken == newOrder.token)) {
                revert IncongruentTokenInOrderGroup();
            }

            //add the order quant to total order value
            totalOrderValue += newOrder.quantity;

            //check if the wallet has a sufficient balance
            if (tokenBalance < totalOrderValue) {
                revert InsufficientWalletBalance();
            }

            //create the new orderId
            bytes32 orderId = keccak256(
                abi.encodePacked(
                    msg.sender,
                    block.timestamp,
                    orderToken,
                    newOrder.price,
                    i
                )
            );

            //set exists to true
            newOrder.exists = true;

            //add the order to active orders
            ActiveOrders[msg.sender].orderGroup[orderToken].orders[
                orderId
            ] = newOrder;

            orderIds[orderIdIndex] = orderId;
            ++orderIdIndex;
        }

        //set the updated total value
        ActiveOrders[msg.sender]
            .orderGroup[orderToken]
            .totalOrderValue = totalOrderValue;

        //emit orders placed
        emit OrderEvent(EventType.PLACE, msg.sender, orderGroup);

        return orderIds;
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

        if (newOrder.quantity > oldOrder.quantity) {
            totalOrdersValue += newOrder.quantity - oldOrder.quantity;
        } else {
            totalOrdersValue += oldOrder.quantity - newOrder.quantity;
        }
        //adjust total orders value quanity

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

        Order[] memory orders = new Order[](1);
        orders[0] = newOrder;
        emit OrderEvent(EventType.UPDATE, msg.sender, orders);
    }

    /// @notice Remove Order order from OrderGroup mapping by identifier orderId conditionally if order exists already in ActiveOrders
    // / @param order the order to which the caller is removing from the OrderGroup struct
    function cancelOrder(address token, bytes32 orderId) public {
        /// Check if order exists in active orders. Revert if order does not exist
        if (
            !ActiveOrders[msg.sender].orderGroup[token].orders[orderId].exists
        ) {
            revert OrderDoesNotExist(orderId);
        }

        Order memory order = ActiveOrders[msg.sender].orderGroup[token].orders[
            orderId
        ];
        /// Get the orderQuantity from the existing order
        uint256 orderQuantity = order.quantity;

        //update totalOrdersValue to decrease by amount orderQuantity of the order being removed
        ActiveOrders[msg.sender]
            .orderGroup[token]
            .totalOrderValue -= orderQuantity;

        // Delete Order Orders[order.orderId] from ActiveOrders mapping
        delete ActiveOrders[msg.sender].orderGroup[token].orders[orderId];

        //emit OrderEvent CANCEL
        Order[] memory orders = new Order[](1);
        orders[0] = order;
        emit OrderEvent(EventType.CANCEL, msg.sender, orders);
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


    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return uint256 spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateMeanPairSpotPrice(address token0, address token1) external view returns (uint256) {
        return PriceLibrary.calculateMeanLPSpot(token0, token1, dexes,1, 3000);
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return uint256 spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateMinPairSpotPrice(address token0, address token1) external view returns (uint256) {
        return PriceLibrary.calculateMinLPSpotPrice(token0, token1, dexes,1, 3000);
    }
    

}
