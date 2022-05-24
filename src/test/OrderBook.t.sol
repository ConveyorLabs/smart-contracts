// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "../../lib/libraries/PriceLibrary.sol";
import "./utils/Swap.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract OrderBookTest is DSTest {
    CheatCodes cheatCodes;
    OrderBookWrapper orderBook;
    Swap swapHelper;

    //----------------State variables for testing--------------------
    ///@notice initialize swap helper
    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    //TODO: add univ3 address
    address uniV3Addr = address(0);
    address wnato = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 immutable MAX_UINT = type(uint256).max;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        swapHelper = new Swap(uniV2Addr, uniV3Addr, wnato);

        address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
        orderBook = new OrderBookWrapper(aggregatorV3Address);
    }

    function testPlaceOrder() public {
        cheatCodes.deal(address(this), MAX_UINT);

        address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
        //swap 20 ether for the swap token
        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

        OrderBook.Order memory order = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5
        );

        placeMockOrder(order);
    }

    function testUpdateOrder() public {}

    function testCancelOrder() public {}

    //------------------Helper functions-----------------------

    function newOrder(
        address tokenIn,
        address tokenOut,
        uint256 price,
        uint256 quantity
    ) internal view returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0),
            orderType: OrderBook.OrderType.SELL,
            price: price,
            quantity: quantity
        });
    }

    function placeMockOrder(ConveyorLimitOrders.Order memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        ConveyorLimitOrders.Order[]
            memory orderGroup = new ConveyorLimitOrders.Order[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = orderBook.placeOrder(orderGroup);

        orderId = orderIds[0];
    }
}

contract OrderBookWrapper is DSTest, OrderBook {
    constructor(address _gasOracle) OrderBook(_gasOracle) {}
}
