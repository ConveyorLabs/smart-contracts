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
    ConveyorLimitOrders conveyorLimitOrders;

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
    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address

    bytes32 _uniswapV2HexDem =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _uniswapV2HexDem];
    address[] _dexFactories = [_uniV2FactoryAddress, _uniV3FactoryAddress];
    bool[] _isUniV2 = [true, false];

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        conveyorLimitOrders = new ConveyorLimitOrders(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            5,
            2592000,
            300000,
            _hexDems,
            _dexFactories,
            _isUniV2
        );
        swapHelper = new Swap(_sushiSwapRouterAddress, wnato);
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
            OrderBook.Order memory order = newOrder(
                swapToken,
                wnato,
                uint128(executionPrice),
                uint112(amountOut),
                uint112(amountOut)
            );

            //create a new array of orders
            ConveyorLimitOrders.Order[]
                memory orderGroup = new ConveyorLimitOrders.Order[](1);
            //add the order to the arrOrder and add the arrOrder to the orderGroup
            orderGroup[0] = order;

            //approve the contract to spend the tokens
            IERC20(swapToken).approve(address(orderBook), MAX_UINT);

            //place order
            bytes32[] memory orderIds = orderBook.placeOrder(orderGroup);
            bytes32 orderId = orderIds[0];

            //check that the orderId is not zero value
            assert((orderId != bytes32(0)));

            assertEq(
                orderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                amountOut
            );

            assertEq(orderBook.totalOrdersPerAddress(address(this)), 1);
        } catch {}
    }

    function testFailPlaceOrder_InsufficientAllowanceForOrderPlacement(
        uint256 swapAmount,
        uint256 executionPrice
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            OrderBook.Order memory order = newOrder(
                swapToken,
                wnato,
                uint128(executionPrice),
                uint128(amountOut),
                uint128(amountOut)
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

            assertEq(
                orderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                amountOut
            );

            assertEq(orderBook.totalOrdersPerAddress(address(this)), 1);
        } catch {
            require(false, "swap failed");
        }
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
                uint128(executionPrice),
                uint128(amountOut),
                uint128(amountOut)
            );

            try
                swapHelper.swapEthForTokenWithUniV2(swapAmount1, swapToken1)
            returns (uint256 amountOut1) {
                OrderBook.Order memory order2 = newOrder(
                    swapToken1,
                    wnato,
                    uint128(executionPrice1),
                    uint112(amountOut1),
                    uint112(amountOut1)
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
                uint128(executionPrice),
                uint128(amountOut),
                uint128(amountOut)
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
                    uint128(executionPrice1),
                    uint128(amountOut1),
                    uint128(amountOut1)
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
                uint128(amountOut),
                uint128(executionPrice),
                uint128(executionPrice)
            );

            //place a mock order
            placeMockOrder(order);

            //create a new order to replace the old order
            ConveyorLimitOrders.Order memory updatedOrder = newOrder(
                swapToken,
                wnato,
                10,
                uint128(executionPrice),
                uint128(executionPrice)
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
                uint128(amountOut),
                uint128(executionPrice),
                uint128(executionPrice)
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
        uint128 swapAmount,
        uint128 executionPrice,
        uint128 swapAmount1,
        uint128 executionPrice1
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            OrderBook.Order memory order1 = newOrder(
                swapToken,
                wnato,
                uint128(amountOut),
                uint128(executionPrice),
                uint128(executionPrice)
            );

            try
                swapHelper.swapEthForTokenWithUniV2(swapAmount1, swapToken1)
            returns (uint256 amountOut1) {
                OrderBook.Order memory order2 = newOrder(
                    swapToken,
                    wnato,
                    uint128(amountOut1),
                    uint128(executionPrice1),
                    uint128(executionPrice1)
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

    //TODO: fuzz this
    function testCalculateMinGasCredits(uint256 _amount) public {
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
        placeMockOrder(newOrder);

        bool overflow;
        assembly {
            overflow := lt(_amount, add(_amount, 1))
        }

        uint256 totalOrdersCount = 1;
        uint256 executionCost = 300000;
        uint256 multiplier = 2;

        if (!overflow) {
            if (_amount > 0) {
                unchecked {
                    if (
                        totalOrdersCount *
                            multiplier *
                            executionCost *
                            _amount <
                        MAX_UINT
                    ) {
                        // require(false, "Got here :[");
                        uint256 minGasCredits = orderBook
                            .calculateMinGasCredits(
                                _amount,
                                executionCost,
                                address(this),
                                multiplier
                            );
                        uint256 expected = totalOrdersCount *
                            _amount *
                            executionCost *
                            multiplier;
                        assertEq(expected, minGasCredits);
                    }
                }
            }
        }
    }

    function testGetTotalOrdersValue() public {
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
        placeMockOrder(newOrder);

        uint256 totalOrdersValue = orderBook.getTotalOrdersValue(swapToken);
        assertEq(5, totalOrdersValue);
    }

    function testHasMinGasCredits() public {
        cheatCodes.deal(address(this), MAX_UINT);
        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: 100000000000000
        }(abi.encodeWithSignature("depositGasCredits()"));
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
        placeMockOrder(newOrder);

        bool hasMinGasCredits = orderBook.hasMinGasCredits(
            1000000,
            300000,
            address(this),
            100000000000000
        );
        assertTrue(hasMinGasCredits);
    }

    function testFailHasMinGasCredits() public {
        cheatCodes.deal(address(this), MAX_UINT);
        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: 1000000000000
        }(abi.encodeWithSignature("depositGasCredits()"));

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
        placeMockOrder(newOrder);

        bool hasMinGasCredits = orderBook.hasMinGasCredits(
            1000000,
            300000,
            address(this),
            1000000000000
        );
        assertTrue(hasMinGasCredits);
    }

    //------------------Helper functions-----------------------

    function newOrder(
        address tokenIn,
        address tokenOut,
        uint128 price,
        uint128 quantity,
        uint128 amountOutMin
    ) internal view returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            buy: false,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: uint32(MAX_UINT),
            feeIn: 0,
            feeOut: 0,
            taxIn: 0,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: address(this),
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
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

    function calculateMinGasCredits(
        uint256 gasPrice,
        uint256 executionCost,
        address userAddress,
        uint256 multiplier
    ) public view returns (uint256) {
        return
            _calculateMinGasCredits(
                gasPrice,
                executionCost,
                userAddress,
                multiplier
            );
    }

    function getTotalOrdersValue(address token) public view returns (uint256) {
        return _getTotalOrdersValue(token);
    }

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
