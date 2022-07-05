// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

contract OrderBookTest is DSTest {
    CheatCodes cheatCodes;
    OrderBookWrapper orderBook;
    Swap swapHelper;

    event OrderPlaced(bytes32[] indexed orderIds);
    event OrderCancelled(bytes32[] indexed orderIds);
    event OrderUpdated(bytes32[] indexed orderIds);

    //----------------State variables for testing--------------------
    ///@notice initialize swap helper
    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    //TODO: add univ3 address
    address uniV3Addr = address(0);
    address wnato = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    address swapToken1 = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;

    uint256 immutable MAX_UINT = type(uint256).max;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        swapHelper = new Swap(uniV2Addr, wnato);
        cheatCodes.deal(address(swapHelper), MAX_UINT);
        address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
        orderBook = new OrderBookWrapper(aggregatorV3Address);
    }

    function testGetOrderById() public {
        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

        //create a new order
        ConveyorLimitOrders.Order memory newOrder = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(newOrder);

        ConveyorLimitOrders.Order memory returnedOrder = orderBook.getOrderById(
            orderId
        );

        // assert that the two orders are the same
        assertEq(returnedOrder.tokenIn, newOrder.tokenIn);
        assertEq(returnedOrder.tokenOut, newOrder.tokenOut);
        assertEq(returnedOrder.orderId, newOrder.orderId);
        assertEq(returnedOrder.price, newOrder.price);
        assertEq(returnedOrder.quantity, newOrder.quantity);
    }

    function testFailGetOrderById_OrderDoesNotExist() public {
        //create a new order
        ConveyorLimitOrders.Order memory newOrder = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );
        //place a mock order
        placeMockOrder(newOrder);

        ConveyorLimitOrders.Order memory returnedOrder = orderBook.getOrderById(
            bytes32(0)
        );
    }

    function testPlaceOrder(uint256 swapAmount, uint256 executionPrice) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            console.log(amountOut);
            OrderBook.Order memory order = newOrder(
                swapToken,
                wnato,
                executionPrice,
                amountOut,
                amountOut
            );

            //create a new array of orders
            ConveyorLimitOrders.Order[]
                memory orderGroup = new ConveyorLimitOrders.Order[](1);
            //add the order to the arrOrder and add the arrOrder to the orderGroup
            orderGroup[0] = order;

            //place order
            bytes32[] memory orderIds = orderBook.placeOrder(orderGroup);
            bytes32 orderId = orderIds[0];

            //check that the orderId is not zero value
            assert((orderId != bytes32(0)));
        } catch {}
    }

    function testFailPlaceOrder_InsufficientWalletBalance() public {
        OrderBook.Order memory order = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );

        //create a new array of orders
        ConveyorLimitOrders.Order[]
            memory orderGroup = new ConveyorLimitOrders.Order[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        orderBook.placeOrder(orderGroup);
    }

    function testFailPlaceOrder_IncongruentTokenInOrderGroup(
        uint256 swapAmount,
        uint256 executionPrice,
        uint256 swapAmount1,
        uint256 executionPrice1
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //swap 20 ether for the swap token
        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            OrderBook.Order memory order1 = newOrder(
                swapToken,
                wnato,
                executionPrice,
                amountOut,
                amountOut
            );

            try
                swapHelper.swapEthForTokenWithUniV2(swapAmount1, swapToken1)
            returns (uint256 amountOut1) {
                OrderBook.Order memory order2 = newOrder(
                    swapToken1,
                    wnato,
                    executionPrice1,
                    amountOut1,
                    amountOut1
                );

                //create a new array of orders
                ConveyorLimitOrders.Order[]
                    memory orderGroup = new ConveyorLimitOrders.Order[](2);
                //add the order to the arrOrder and add the arrOrder to the orderGroup
                orderGroup[0] = order1;
                orderGroup[1] = order2;

                //place order
                orderBook.placeOrder(orderGroup);
            } catch {
                require(false, "swap 1 failed");
            }
        } catch {
            require(false, "swap 0 failed");
        }
    }

    function testUpdateOrder(
        uint256 swapAmount,
        uint256 executionPrice,
        uint256 swapAmount1,
        uint256 executionPrice1
    ) public {
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            //create a new order
            ConveyorLimitOrders.Order memory order = newOrder(
                swapToken,
                wnato,
                executionPrice,
                amountOut,
                amountOut
            );
            //place a mock order
            bytes32 orderId = placeMockOrder(order);
            try
                swapHelper.swapEthForTokenWithUniV2(swapAmount1, swapToken)
            returns (uint256 amountOut1) {
                //create a new order to replace the old order
                ConveyorLimitOrders.Order memory updatedOrder = newOrder(
                    swapToken,
                    wnato,
                    executionPrice1,
                    amountOut1,
                    amountOut1
                );
                updatedOrder.orderId = orderId;

                //submit the updated order
                orderBook.updateOrder(updatedOrder);
            } catch {}
        } catch {}
    }

    function testFailUpdateOrder_OrderDoesNotExist(
        uint256 swapAmount,
        uint256 executionPrice,
        bytes32 orderId
    ) public {
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            //create a new order
            ConveyorLimitOrders.Order memory order = newOrder(
                swapToken,
                wnato,
                amountOut,
                executionPrice,
                executionPrice
            );

            //place a mock order
            placeMockOrder(order);

            //create a new order to replace the old order
            ConveyorLimitOrders.Order memory updatedOrder = newOrder(
                swapToken,
                wnato,
                10,
                executionPrice,
                executionPrice
            );
            updatedOrder.orderId = orderId;

            //submit the updated order
            orderBook.updateOrder(updatedOrder);
        } catch {
            require(false, "swap failed");
        }
    }

    function testMinGasCredits() public {
        cheatCodes.deal(address(this), MAX_UINT);

        //swap 20 ether for the swap token
        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

        OrderBook.Order memory order = newOrder(
            swapToken,
            wnato,
            2450000000000000,
            5,
            5
        );

        placeMockOrder(order);

        bool hasMinGasCredits = orderBook.hasMinGasCredits(
            50000000000,
            300000,
            address(this),
            15000000000000000000000
        );

        assert(hasMinGasCredits);
    }

    function testFailMinGasCredits() public {
        cheatCodes.deal(address(this), MAX_UINT);

        //swap 20 ether for the swap token
        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

        OrderBook.Order memory order = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );
        placeMockOrder(order);

        //set the gasCredit balance to a value too low for the min gas credit check to pass
        bool hasMinGasCredits = orderBook.hasMinGasCredits(
            50000000000,
            300000,
            address(this),
            15000000000
        );

        assert(hasMinGasCredits);
    }

    function testCancelOrder(uint256 swapAmount, uint256 executionPrice)
        public
    {
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            //create a new order
            ConveyorLimitOrders.Order memory order = newOrder(
                swapToken,
                wnato,
                amountOut,
                executionPrice,
                executionPrice
            );
            //place a mock order
            bytes32 orderId = placeMockOrder(order);

            //submit the updated order
            orderBook.cancelOrder(orderId);
        } catch {}
    }

    function testFailCancelOrder_OrderDoesNotExist(bytes32 orderId) public {
        //submit the updated order
        orderBook.cancelOrder(orderId);
    }

    ///@notice cancel multiple orders
    function testCancelOrders(
        uint256 swapAmount,
        uint256 executionPrice,
        uint256 swapAmount1,
        uint256 executionPrice1
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            OrderBook.Order memory order1 = newOrder(
                swapToken,
                wnato,
                amountOut,
                executionPrice,
                executionPrice
            );

            try
                swapHelper.swapEthForTokenWithUniV2(swapAmount1, swapToken1)
            returns (uint256 amountOut1) {
                OrderBook.Order memory order2 = newOrder(
                    swapToken,
                    wnato,
                    amountOut1,
                    executionPrice1,
                    executionPrice1
                );

                //create a new array of orders
                ConveyorLimitOrders.Order[]
                    memory orderGroup = new ConveyorLimitOrders.Order[](2);
                //add the order to the arrOrder and add the arrOrder to the orderGroup
                orderGroup[0] = order1;
                orderGroup[1] = order2;

                //place order
                bytes32[] memory orderIds = orderBook.placeOrder(orderGroup);

                orderBook.cancelOrders(orderIds);
            } catch {}
        } catch {}
    }

    function testFailCancelOrders_OrderDoesNotExist(
        bytes32 orderId,
        bytes32 orderId1
    ) public {
        //place order
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId;
        orderIds[1] = orderId1;
        orderBook.cancelOrders(orderIds);
    }

    function testCalculateMinGasCredits() public {}

    function testGetTotalOrdersValue() public {}

    function testHasMinGasCredits() public {
        // orderBook.hasMinGasCredits(gasPrice, executionCost, userAddress, gasCreditBalance);
    }

    //------------------Helper functions-----------------------

    function newOrder(
        address tokenIn,
        address tokenOut,
        uint256 price,
        uint256 quantity,
        uint256 amountOutMin
    ) internal view returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0),
            buy: false,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: 2419200,
            price: price,
            quantity: quantity,
            amountOutMin: amountOutMin,
            owner: msg.sender
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

///@notice wrapper around the OrderBook contract to expose internal functions for testing
contract OrderBookWrapper is DSTest, OrderBook {
    constructor(address _gasOracle) OrderBook(_gasOracle) {}

    function hasMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 gasCreditBalance
    ) public view returns (bool) {
        return
            _hasMinGasCredits(
                gasPrice,
                executionCost,
                userAddress,
                gasCreditBalance
            );
    }
}
