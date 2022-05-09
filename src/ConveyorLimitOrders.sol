// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "../lib/interfaces/IERC20.sol";
import "../lib/interfaces/IUniswapV2Router02.sol";
import "../lib/interfaces/IUniswapV2Factory.sol";
import "../lib/interfaces/IUniswapV2Pair.sol";
import "./test/utils/Console.sol";
import "../lib/libraries/OracleLibrary.sol";
import "../lib/interfaces/IUniswapV3Factory.sol";
import "../lib/interfaces/IUniswapV3Pool.sol";

contract ConveyorLimitOrders {
    //----------------------Constructor------------------------------------//
    constructor() {
        //TODO: need to fill out what we are putting in the constructor
    }

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
    address[] dexFactories = [
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f,
        0x1F98431c8aD98523631AE4a59f267346ea31F984
    ];

    IUniswapV2Factory public v2Factory;

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

    //----------------------State Structures------------------------------------//

    //order id  to order
    mapping(bytes32 => Order) orderIdToOrder;

    //struct to check if order exists, as well as get all orders for a wallet
    mapping(address => mapping(bytes32 => bool)) addressToOrderIds;

    //msg.sender => tokenAddress => total order value
    mapping(address => mapping(address => uint256)) totalOrdersValue;

    //----------------------Functions------------------------------------//

    function getOrderById(bytes32 orderId)
        public
        view
        returns (Order memory order)
    {
        order = orderIdToOrder[orderId];
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
        uint256 _totalOrdersValue = totalOrdersValue[msg.sender][orderToken];

        uint256 tokenBalance = IERC20(orderToken).balanceOf(msg.sender);

        for (uint256 i = 0; i < orderGroup.length; ++i) {
            Order memory newOrder = orderGroup[i];

            if (!(orderToken == newOrder.token)) {
                revert IncongruentTokenInOrderGroup();
            }

            //add the order quant to total order value
            _totalOrdersValue += newOrder.quantity;

            //check if the wallet has a sufficient balance
            if (tokenBalance < _totalOrdersValue) {
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
            orderIdToOrder[orderId] = newOrder;

            //add the order to address to order ids
            addressToOrderIds[msg.sender][orderId] = true;

            orderIds[orderIdIndex] = orderId;
            ++orderIdIndex;
        }

        //set the updated total value
        totalOrdersValue[msg.sender][orderToken] = _totalOrdersValue;

        //emit orders placed
        emit OrderEvent(EventType.PLACE, msg.sender, orderGroup);

        return orderIds;
    }

    /// @notice Update mapping(uint256 => Order) in Order struct from identifier orderId to new 'order' value passed as @param
    function updateOrder(Order calldata newOrder) public {
        Order memory oldOrder = orderIdToOrder[newOrder.orderId];

        //check if the old order exists
        if (!oldOrder.exists) {
            revert OrderDoesNotExist(newOrder.orderId);
        }

        uint256 _totalOrdersValue = totalOrdersValue[msg.sender][
            newOrder.token
        ];

        if (newOrder.quantity > oldOrder.quantity) {
            _totalOrdersValue += newOrder.quantity - oldOrder.quantity;
        } else {
            _totalOrdersValue += oldOrder.quantity - newOrder.quantity;
        }
        //adjust total orders value quanity

        //check if the wallet has a sufficient balance
        if (IERC20(newOrder.token).balanceOf(msg.sender) < _totalOrdersValue) {
            revert InsufficientWalletBalance();
        }

        //update totalOrdersValue for that token
        totalOrdersValue[msg.sender][newOrder.token] = _totalOrdersValue;

        //update the order
        orderIdToOrder[newOrder.orderId] = newOrder;

        //emit order updated
        //TODO: still need to decide on contents of events

        Order[] memory orders = new Order[](1);
        orders[0] = newOrder;
        emit OrderEvent(EventType.UPDATE, msg.sender, orders);
    }

    /// @notice Remove Order order from OrderGroup mapping by identifier orderId conditionally if order exists already in ActiveOrders
    // / @param order the order to which the caller is removing from the OrderGroup struct
    function cancelOrders(bytes32[] memory orderIds) public {
        uint256 canceledOrderIdIndex;
        Order[] memory canceledOrders = new Order[](orderIds.length);

        for (uint256 i = 0; i < orderIds.length; ++i) {
            Order memory _order = orderIdToOrder[orderIds[i]];
            bytes32 _orderId = _order.orderId;

            /// Check if order exists in active orders. Revert if order does not exist
            if (!_order.exists) {
                revert OrderDoesNotExist(_orderId);
            }

            /// Get the orderQuantity from the existing order
            uint256 orderQuantity = _order.quantity;

            //update totalOrdersValue to decrease by amount orderQuantity of the order being removed
            totalOrdersValue[msg.sender][_order.token] -= orderQuantity;

            delete orderIdToOrder[_orderId];

            delete addressToOrderIds[msg.sender][_order.orderId];

            //add Order to canceled orders
            canceledOrders[canceledOrderIdIndex] = _order;

            ++canceledOrderIdIndex;
        }
        //emit event
        emit OrderEvent(EventType.CANCEL, msg.sender, canceledOrders);
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

    /// @notice Helper function to change the base decimal value of token0 & token1 to the same target decimal value
    /// target decimal value for both token decimals to match will be max(token0Decimals, token1Decimals)
    /// @param reserve0 uint256 token1 value
    /// @param token0Decimals Decimals of token0
    /// @param reserve1 uint256 token2 value
    /// @param token1Decimals Decimals of token1
    function convertToCommonBase(
        uint256 reserve0,
        uint8 token0Decimals,
        uint256 reserve1,
        uint8 token1Decimals
    ) external returns (uint256, uint256) {
        /// @dev Conditionally change the decimal to target := max(decimal0, decimal1)
        /// return tuple of modified reserve values in matching decimals
        if (token0Decimals > token1Decimals) {
            return (
                reserve0,
                reserve1 * (10**(token0Decimals - token1Decimals))
            );
        } else {
            return (
                reserve0 * (10**(token1Decimals - token0Decimals)),
                reserve1
            );
        }
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return uint256 spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateUniV2SpotPrice(address token0, address token1)
        external
        view
        returns (uint112)
    {
        //Get Uni v2 pair address for token0, token1
        address factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
        address pair = address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            hex"ff",
                            factory,
                            keccak256(abi.encodePacked(token0, token1)),
                            hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f"
                        )
                    )
                )
            )
        );

        console.log(pair);
        (uint112 x, , ) = IUniswapV2Pair(pair).getReserves();
        console.log(x);

        (uint112 reserve0, uint112 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();
        console.log(reserve0);
        console.log(reserve1);

        return reserve0 / reserve1;
    }

    /// @notice Helper function to get Uniswap V2 spot price of pair token1/token2
    /// @param token0 bytes32 address of token1
    /// @param token1 bytes32 address of token2
    /// @return amountOut spot price of token1 with respect to token2 i.e reserve1/reserve2
    function calculateUniV3SpotPrice(
        address token0,
        address token1,
        uint128 amountIn,
        uint24 FEE,
        uint32 tickSecond
    ) external returns (uint256 amountOut) {
        //Uniswap V3 Factory
        address factory = dexFactories[1];

        //tickSeconds array defines our tick interval of observation over the lp
        uint32[] memory tickSeconds = new uint32[](2);
        //int32 version of tickSecond padding in tick range
        int32 tickSecondInt = int32(tickSecond);
        //Populate tickSeconds array current block to tickSecond behind current block for tick range
        tickSeconds[0] = tickSecond;
        tickSeconds[1] = 0;

        //Pool address for token pair
        address pool = IUniswapV3Factory(factory).getPool(token0, token1, FEE);

        //Start observation over lp in prespecified tick range
        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
            tickSeconds
        );

        //Spot price of tickSeconds ago - spot price of current block
        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];

        // int56 / uint32 = int24
        int24 tick = int24(tickCumulativesDelta / (tickSecondInt));

        //so if tickCumulativeDelta < 0 and division has remainder, then rounddown

        if (
            tickCumulativesDelta < 0 &&
            (tickCumulativesDelta % tickSecondInt != 0)
        ) {
            tick--;
        }

        //amountOut = tick range spot over specified tick interval
        amountOut = OracleLibrary.getQuoteAtTick(
            tick,
            amountIn,
            token0,
            token1
        );
    }

    /// @notice Helper function to get the price average of a token between multiple pools
    /// @param address[] pool address's to calculate the average price between
    // function calculateMeanPoolPriceAverageToken0(address[] pairs, address token0, address token1) internal {
    //     //Calculate mean spot price across arrTokenPairs in terms of token0, so token0/token1
    // }
}
