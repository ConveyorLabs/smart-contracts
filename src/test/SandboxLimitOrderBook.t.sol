// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../LimitOrderQuoter.sol";
import "../LimitOrderExecutor.sol";
import "../SwapRouter.sol";
import "../SandboxLimitOrderBook.sol";

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

contract SandboxLimitOrderBookTest is DSTest {
    CheatCodes cheatCodes;
    LimitOrderExecutor limitOrderExecutor;
    LimitOrderQuoter limitOrderQuoter;
    Swap swapHelper;
    IOrderBook limitOrderBook;
    ISandboxLimitOrderBook sandboxLimitOrderBook;

    event OrderPlaced(bytes32[] orderIds);
    event OrderCanceled(bytes32[] orderIds);
    event OrderUpdated(bytes32[] orderIds);

    //----------------State variables for testing--------------------
    ///@notice initialize swap helper
    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
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

    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    //Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _uniswapV2HexDem];
    address[] _dexFactories = [_uniV2FactoryAddress, _uniV3FactoryAddress];
    bool[] _isUniV2 = [true, false];
    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000000;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        swapHelper = new Swap(_sushiSwapRouterAddress, wnato);
        cheatCodes.deal(address(swapHelper), MAX_UINT);

        limitOrderQuoter = new LimitOrderQuoter(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );

        limitOrderExecutor = new LimitOrderExecutor(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderQuoter),
            _hexDems,
            _dexFactories,
            _isUniV2,
            aggregatorV3Address,
            300000,
            250000
        );

        sandboxLimitOrderBook = ISandboxLimitOrderBook(
            limitOrderExecutor.SANDBOX_LIMIT_ORDER_BOOK()
        );

        cheatCodes.deal(address(this), type(uint128).max);
        depositGasCreditsForMockOrders(type(uint64).max);
    }

    function testFrom64XToX16() public {
        uint128 number = 18446744073709552; //0.0001 64.64
        uint32 result = ConveyorMath.fromX64ToX16(number);
        console.log(result);
    }

    ///@notice Test get order by id
    function testgetLimitOrderById() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        LimitOrderBook.LimitOrder memory returnedOrder = limitOrderBook
            .getLimitOrderById(orderId);
        (orderId);

        // assert that the two orders are the same
        assertEq(returnedOrder.tokenIn, order.tokenIn);
        assertEq(returnedOrder.tokenOut, order.tokenOut);
        assertEq(returnedOrder.orderId, orderId);
        assertEq(returnedOrder.price, order.price);
        assertEq(returnedOrder.quantity, order.quantity);
    }

    //Test to get SandboxLimitOrder
    function testGetOrderByIdSandBox() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

        //create a new order
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(swapToken, wnato, 5, 5);
        //place a mock order
        bytes32 orderId = placeMockSandboxLimitOrder(order);

        SandboxLimitOrderBook.SandboxLimitOrder
            memory returnedOrder = sandboxLimitOrderBook
                .getSandboxLimitOrderById(orderId);

        // assert that the two orders are the same
        assertEq(returnedOrder.tokenIn, order.tokenIn);
        assertEq(returnedOrder.tokenOut, order.tokenOut);
        assertEq(returnedOrder.orderId, orderId);
    }

    ///@notice Test fail get order by id order does not exist
    function testFailgetLimitOrderById_OrderDoesNotExist() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );
        //place a mock order
        placeMockOrder(order);

        limitOrderBook.getLimitOrderById(bytes32(0));
    }

    ///@notice Test palce order fuzz test
    function testPlaceOrder(uint256 swapAmount, uint256 executionPrice) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                wnato,
                uint128(executionPrice),
                uint112(amountOut),
                uint112(amountOut)
            );

            //create a new array of orders
            LimitOrderBook.LimitOrder[]
                memory orderGroup = new LimitOrderBook.LimitOrder[](1);
            //add the order to the arrOrder and add the arrOrder to the orderGroup
            orderGroup[0] = order;

            //place order
            bytes32[] memory orderIds = limitOrderBook.placeLimitOrder(
                orderGroup
            );
            bytes32 orderId = orderIds[0];

            //check that the orderId is not zero value
            assert((orderId != bytes32(0)));
            LimitOrderBook.OrderType orderType = limitOrderBook
                .addressToOrderIds(address(this), orderId);
            assert(orderType == LimitOrderBook.OrderType.PendingLimitOrder);
            assertEq(
                limitOrderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                amountOut
            );

            assertEq(limitOrderBook.totalOrdersPerAddress(address(this)), 1);
        } catch {}
    }

    // function testGetOrderIds() public {
    //     cheatCodes.deal(address(this), MAX_UINT);
    //     IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);
    //     //if the fuzzed amount is enough to complete the swap
    //     swapHelper.swapEthForTokenWithUniV2(10000, swapToken);

    //     ///@notice Place orders
    //     bytes32 orderId1 = placeMockOrder(
    //         newOrder(swapToken, wnato, uint128(1), uint112(1), uint112(1))
    //     );

    //     bytes32 orderId2 = placeMockOrder(
    //         newOrder(swapToken, wnato, uint128(1), uint112(1), uint112(1))
    //     );

    //     bytes32 orderId4 = placeMockSandboxLimitOrder(
    //         newSandboxLimitOrder(swapToken, wnato, uint112(1), uint112(1))
    //     );

    //     bytes32 orderId5 = placeMockSandboxLimitOrder(
    //         newSandboxLimitOrder(swapToken, wnato, uint112(1), uint112(1))
    //     );

    //     limitOrderBook.cancelOrder(orderId2);
    //     limitOrderBook.cancelOrder(orderId5);

    //     uint256 orderIdsLength = limitOrderBook.getAllOrderIdsLength(
    //         address(this)
    //     );

    //     bytes32[] memory pendingLimitOrders = limitOrderBook.getOrderIds(
    //         address(this),
    //         LimitOrderBook.OrderType.PendingLimitOrder,
    //         0,
    //         orderIdsLength
    //     );

    //     bytes32[] memory pendingSandboxLimitOrders = limitOrderBook.getOrderIds(
    //         address(this),
    //         LimitOrderBook.OrderType.PendingSandboxLimitOrder,
    //         0,
    //         orderIdsLength
    //     );

    //     bytes32[] memory canceledLimitOrders = limitOrderBook.getOrderIds(
    //         address(this),
    //         LimitOrderBook.OrderType.CanceledLimitOrder,
    //         0,
    //         orderIdsLength
    //     );

    //     bytes32[] memory canceledSandboxLimitOrders = limitOrderBook
    //         .getOrderIds(
    //             address(this),
    //             LimitOrderBook.OrderType.CanceledSandboxLimitOrder,
    //             0,
    //             orderIdsLength
    //         );

    //     assertEq(pendingLimitOrders.length, 1);
    //     assertEq(pendingSandboxLimitOrders.length, 1);
    //     assertEq(canceledLimitOrders.length, 1);
    //     assertEq(canceledSandboxLimitOrders.length, 1);

    //     assertEq(pendingLimitOrders[0], orderId1);
    //     assertEq(pendingSandboxLimitOrders[0], orderId4);
    //     assertEq(canceledLimitOrders[0], orderId2);
    //     assertEq(canceledSandboxLimitOrders[0], orderId5);
    // }

    ///@notice Test palce order fuzz test
    function testPlaceSandboxOrder(
        uint112 amountInRemaining,
        uint112 amountOutRemaining
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);
        if (!(amountInRemaining < 1000000000000000)) {
            //if the fuzzed amount is enough to complete the swap
            try
                swapHelper.swapEthForTokenWithUniV2(
                    amountInRemaining,
                    swapToken
                )
            returns (uint256 amountOut) {
                SandboxLimitOrderBook.SandboxLimitOrder
                    memory order = newSandboxLimitOrder(
                        swapToken,
                        wnato,
                        uint112(amountOut),
                        uint112(amountOutRemaining)
                    );

                //create a new array of orders
                SandboxLimitOrderBook.SandboxLimitOrder[]
                    memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                        1
                    );
                //add the order to the arrOrder and add the arrOrder to the orderGroup
                orderGroup[0] = order;

                //place order
                bytes32[] memory orderIds = sandboxLimitOrderBook
                    .placeSandboxLimitOrder(orderGroup);
                bytes32 orderId = orderIds[0];

                //check that the orderId is not zero value
                assert((orderId != bytes32(0)));
                SandboxLimitOrderBook.OrderType orderType = sandboxLimitOrderBook
                        .addressToOrderIds(address(this), orderId);
                assert(
                    orderType ==
                        SandboxLimitOrderBook.OrderType.PendingSandboxLimitOrder
                );
                assertEq(
                    sandboxLimitOrderBook.totalOrdersQuantity(
                        keccak256(abi.encode(address(this), swapToken))
                    ),
                    amountOut
                );

                assertEq(
                    sandboxLimitOrderBook.totalOrdersPerAddress(address(this)),
                    1
                );
            } catch {}
        }
    }

    ///TODO: Write a fuzz test for this
    function testFailPlaceSandboxLimitOrder_InsufficientWalletBalance(
        uint112 amountOutRemaining
    ) public {
        uint256 amountInRemaining = 1000000000000000000;

        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);
        //if the fuzzed amount is enough to complete the swap

        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(
                swapToken,
                wnato,
                uint112(amountInRemaining),
                uint112(amountOutRemaining)
            );

        //create a new array of orders
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                1
            );
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        sandboxLimitOrderBook.placeSandboxLimitOrder(orderGroup);
    }

    ///TODO: Write a fuzz test for this
    function testFailPlaceSandboxLimitOrder_InsufficientAllowanceForOrderPlacement(
        uint256 amountOutRemaining
    ) public {
        uint256 amountInRemaining = 1000000000000000000;

        cheatCodes.deal(address(this), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try
            swapHelper.swapEthForTokenWithUniV2(amountInRemaining, swapToken)
        returns (uint256 amountOut) {
            SandboxLimitOrderBook.SandboxLimitOrder memory order = newSandboxLimitOrder(
                swapToken,
                swapToken, //Same in out token should throw reversion
                uint112(amountOut),
                uint112(amountOutRemaining)
            );

            //create a new array of orders
            SandboxLimitOrderBook.SandboxLimitOrder[]
                memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                    1
                );
            //add the order to the arrOrder and add the arrOrder to the orderGroup
            orderGroup[0] = order;

            //place order
            sandboxLimitOrderBook.placeSandboxLimitOrder(orderGroup);
        } catch {}
    }

    ///TODO: Write a fuzz test for this
    function testCancelSandboxLimitOrder(uint256 amountOutRemaining) public {
        uint256 amountInRemaining = 1000000000000000000;

        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(
            address(limitOrderExecutor),
            type(uint128).max
        );

        //if the fuzzed amount is enough to complete the swap
        try
            swapHelper.swapEthForTokenWithUniV2(amountInRemaining, swapToken)
        returns (uint256 amountOut) {
            SandboxLimitOrderBook.SandboxLimitOrder
                memory order = newSandboxLimitOrder(
                    swapToken,
                    wnato,
                    uint112(amountOut),
                    uint112(amountOutRemaining)
                );

            //create a new array of orders
            SandboxLimitOrderBook.SandboxLimitOrder[]
                memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                    1
                );
            //add the order to the arrOrder and add the arrOrder to the orderGroup
            orderGroup[0] = order;

            //place order
            bytes32[] memory orderIds = sandboxLimitOrderBook
                .placeSandboxLimitOrder(orderGroup);
            bytes32 orderId = orderIds[0];

            //check that the orderId is not zero value
            assert((orderId != bytes32(0)));

            assertEq(
                sandboxLimitOrderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                amountOut
            );

            assertEq(
                sandboxLimitOrderBook.totalOrdersPerAddress(address(this)),
                1
            );
            sandboxLimitOrderBook.cancelOrder(orderId);
            SandboxLimitOrderBook.OrderType orderType = sandboxLimitOrderBook
                .addressToOrderIds(address(this), orderId);
            assert(
                orderType ==
                    SandboxLimitOrderBook.OrderType.CanceledSandboxLimitOrder
            );
            assertEq(
                sandboxLimitOrderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                0
            );

            assertEq(
                sandboxLimitOrderBook.totalOrdersPerAddress(address(this)),
                0
            );
        } catch {}
    }

    ///@notice Test fail place order InsufficientAlllowanceForOrderPlacement
    function testFailPlaceOrder_InsufficientAllowanceForOrderPlacement(
        uint256 swapAmount,
        uint256 executionPrice
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                wnato,
                uint128(executionPrice),
                uint128(amountOut),
                uint128(amountOut)
            );

            //create a new array of orders
            LimitOrderBook.LimitOrder[]
                memory orderGroup = new LimitOrderBook.LimitOrder[](1);
            //add the order to the arrOrder and add the arrOrder to the orderGroup
            orderGroup[0] = order;

            //place order
            bytes32[] memory orderIds = limitOrderBook.placeLimitOrder(
                orderGroup
            );
            bytes32 orderId = orderIds[0];

            //check that the orderId is not zero value
            assert((orderId != bytes32(0)));

            assertEq(
                limitOrderBook.totalOrdersQuantity(
                    keccak256(abi.encode(address(this), swapToken))
                ),
                amountOut
            );

            assertEq(limitOrderBook.totalOrdersPerAddress(address(this)), 1);
        } catch {
            require(false, "swap failed");
        }
    }

    ///@notice Test fail place order InsufficientWalletBalance
    function testFailPlaceOrder_InsufficientWalletBalance() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );

        //create a new array of orders
        LimitOrderBook.LimitOrder[]
            memory orderGroup = new LimitOrderBook.LimitOrder[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        limitOrderBook.placeLimitOrder(orderGroup);
    }

    ///@notice Test Fail Place order IncongruentTokenInOrderGroup
    function testFailPlaceOrder_IncongruentTokenInOrderGroup(
        uint256 swapAmount,
        uint256 executionPrice,
        uint256 swapAmount1,
        uint256 executionPrice1
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //swap 20 ether for the swap token
        //if the fuzzed amount is enough to complete the swap
        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            LimitOrderBook.LimitOrder memory order1 = newOrder(
                swapToken,
                wnato,
                uint128(executionPrice),
                uint128(amountOut),
                uint128(amountOut)
            );

            try
                swapHelper.swapEthForTokenWithUniV2(swapAmount1, swapToken1)
            returns (uint256 amountOut1) {
                LimitOrderBook.LimitOrder memory order2 = newOrder(
                    swapToken1,
                    wnato,
                    uint128(executionPrice1),
                    uint112(amountOut1),
                    uint112(amountOut1)
                );

                //create a new array of orders
                LimitOrderBook.LimitOrder[]
                    memory orderGroup = new LimitOrderBook.LimitOrder[](2);
                //add the order to the arrOrder and add the arrOrder to the orderGroup
                orderGroup[0] = order1;
                orderGroup[1] = order2;

                //place order
                limitOrderBook.placeLimitOrder(orderGroup);
            } catch {
                require(false, "swap 1 failed");
            }
        } catch {
            require(false, "swap 0 failed");
        }
    }

    ///@notice Test update order
    function testUpdateOrder(
        uint128 price,
        uint64 quantity,
        uint128 amountOutMin,
        uint128 newPrice,
        uint64 newQuantity
    ) public {
        if (
            !(price == 0 ||
                quantity == 0 ||
                amountOutMin == 0 ||
                newPrice == 0 ||
                newQuantity == 0)
        ) {
            cheatCodes.deal(address(this), MAX_UINT);
            IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

            cheatCodes.deal(address(swapHelper), MAX_UINT);
            swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);

            //create a new order
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                wnato,
                price,
                quantity,
                amountOutMin
            );

            //place a mock order
            bytes32 orderId = placeMockOrder(order);

            //submit the updated order
            limitOrderBook.updateOrder(orderId, newPrice, newQuantity);

            LimitOrderBook.LimitOrder memory updatedOrder = limitOrderBook
                .getLimitOrderById(orderId);

            //Cache the total orders value after the update
            uint256 totalOrdersValueAfter = limitOrderBook.totalOrdersQuantity(
                keccak256(abi.encode(address(this), swapToken))
            );

            //Make sure the order was updated properly
            assertEq(newQuantity, totalOrdersValueAfter);
            assertEq(newQuantity, updatedOrder.quantity);
            assertEq(newPrice, updatedOrder.price);
        }
    }

    ///@notice Test update sandbox order
    function testUpdateSandboxOrder(
        uint128 newAmountInRemaining,
        uint128 newAmountOutRemaining
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);
        if (newAmountInRemaining > IERC20(swapToken).balanceOf(address(this))) {
            newAmountInRemaining = uint128(
                IERC20(swapToken).balanceOf(address(this))
            );
        }
        //create a new order
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(
                swapToken,
                wnato,
                1000000000000000000,
                1000000000000000000
            );

        //place a mock order
        bytes32 orderId = placeMockSandboxLimitOrder(order);

        //submit the updated order
        sandboxLimitOrderBook.updateSandboxLimitOrder(
            orderId,
            newAmountInRemaining,
            newAmountOutRemaining
        );

        SandboxLimitOrderBook.SandboxLimitOrder
            memory updatedOrder = sandboxLimitOrderBook
                .getSandboxLimitOrderById(orderId);

        //Cache the total orders value after the update
        uint256 totalOrdersValueAfter = sandboxLimitOrderBook
            .totalOrdersQuantity(
                keccak256(abi.encode(address(this), swapToken))
            );

        //Make sure the order was updated properly
        assertEq(newAmountInRemaining, totalOrdersValueAfter);
        assertEq(newAmountInRemaining, updatedOrder.amountInRemaining);
        assertEq(newAmountOutRemaining, updatedOrder.amountOutRemaining);
    }

    ///@notice Test fail update order insufficient allowance
    function testFailUpdateOrder_InsufficientAllowanceForOrderUpdate(
        uint128 price,
        uint64 quantity,
        uint128 amountOutMin,
        uint128 newPrice
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), quantity);

        cheatCodes.deal(address(swapHelper), MAX_UINT);
        swapHelper.swapEthForTokenWithUniV2(100000000000 ether, swapToken);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            price,
            quantity,
            amountOutMin
        );

        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //submit the updated order should revert since approved quantity is less than order quantity
        limitOrderBook.updateOrder(orderId, newPrice, quantity + 1);
    }

    ///@notice Test fail update order order does not exist
    function testFailUpdateOrder_OrderDoesNotExist(
        uint256 swapAmount,
        uint256 executionPrice,
        bytes32 orderId
    ) public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        try swapHelper.swapEthForTokenWithUniV2(swapAmount, swapToken) returns (
            uint256 amountOut
        ) {
            //create a new order
            LimitOrderBook.LimitOrder memory order = newOrder(
                swapToken,
                wnato,
                uint128(amountOut),
                uint128(executionPrice),
                uint128(executionPrice)
            );

            //place a mock order
            placeMockOrder(order);

            limitOrderBook.updateOrder(orderId, 100, 0);
        } catch {
            require(false, "swap failed");
        }
    }

    // ///@notice Test min gas credits
    // function testMinGasCredits() public {
    //     cheatCodes.deal(address(this), MAX_UINT);
    //     IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

    //     //swap 20 ether for the swap token
    //     swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

    //     LimitOrderBook.LimitOrder memory order = newOrder(
    //         swapToken,
    //         wnato,
    //         2450000000000000,
    //         5,
    //         5
    //     );

    //     placeMockOrder(order);

    //     //Pass in a sample min gas credits that is sufficiently above the threshold
    //     bool hasMinGasCredits = limitOrderBook.hasMinGasCredits(
    //         50000000000,
    //         300000,
    //         address(this),
    //         15000000000000000000000,
    //         1
    //     );

    //     assert(hasMinGasCredits);
    // }

    // //Test fail hasMinGasCredits
    // function testFailMinGasCredits() public {
    //     cheatCodes.deal(address(this), MAX_UINT);
    //     IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

    //     //swap 20 ether for the swap token
    //     swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

    //     LimitOrderBook.LimitOrder memory order = newOrder(
    //         swapToken,
    //         wnato,
    //         245000000000000000000,
    //         5,
    //         5
    //     );
    //     placeMockOrder(order);

    //     //set the gasCredit balance to a value too low for the min gas credit check to pass
    //     bool hasMinGasCredits = limitOrderBook.hasMinGasCredits(
    //         50000000000,
    //         300000,
    //         address(this),
    //         15000000000,
    //         1
    //     );

    //     assert(hasMinGasCredits);
    // }

    //Test cancel order
    function testCancelOrder() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        uint256 amountOut = swapHelper.swapEthForTokenWithUniV2(
            100000,
            swapToken
        );
        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            uint128(amountOut),
            uint128(1),
            uint128(1)
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //submit the updated order
        limitOrderBook.cancelOrder(orderId);
    }

    ///@notice Test Fail cancel order order does not exist
    function testFailCancelOrder_OrderDoesNotExist(bytes32 orderId) public {
        //submit the updated order
        limitOrderBook.cancelOrder(orderId);
    }

    ///@notice Test to cancel multiple order
    function testCancelOrders() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        uint256 amountOut = swapHelper.swapEthForTokenWithUniV2(
            100000,
            swapToken
        );
        //Create a new order
        LimitOrderBook.LimitOrder memory order1 = newOrder(
            swapToken,
            wnato,
            uint128(amountOut / 2),
            uint128(1),
            uint128(1)
        );
        //Create a second order
        LimitOrderBook.LimitOrder memory order2 = newOrder(
            swapToken,
            wnato,
            uint128((amountOut / 2) - 1),
            uint128(1),
            uint128(1)
        );

        //create a new array of orders
        LimitOrderBook.LimitOrder[]
            memory orderGroup = new LimitOrderBook.LimitOrder[](2);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order1;
        orderGroup[1] = order2;

        //place order
        bytes32[] memory orderIds = limitOrderBook.placeLimitOrder(orderGroup);

        //Cancel the orders
        limitOrderBook.cancelOrders(orderIds);
    }

    ///@notice Test Fail cancel orders OrderDoesNotExist
    function testFailCancelOrders_OrderDoesNotExist(
        bytes32 orderId,
        bytes32 orderId1
    ) public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //place order
        bytes32[] memory orderIds = new bytes32[](2);
        orderIds[0] = orderId;
        orderIds[1] = orderId1;
        limitOrderBook.cancelOrders(orderIds);
    }

    // ///@notice Test calculate min gas credits
    // function testCalculateMinGasCredits(uint128 _amount) public {
    //     swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);
    //     IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

    //     //create a new order
    //     LimitOrderBook.LimitOrder memory order = newOrder(
    //         swapToken,
    //         wnato,
    //         245000000000000000000,
    //         5,
    //         5
    //     );

    //     //place a mock order
    //     placeMockOrder(order);

    //     bool overflow;
    //     assembly {
    //         overflow := lt(_amount, add(_amount, 1))
    //     }

    //     uint256 totalOrdersCount = 1;
    //     uint256 executionCost = 300000;
    //     uint256 multiplier = 2;

    //     if (!overflow) {
    //         if (_amount > 0) {
    //             unchecked {
    //                 if (
    //                     totalOrdersCount *
    //                         multiplier *
    //                         executionCost *
    //                         _amount <
    //                     MAX_UINT
    //                 ) {
    //                     uint256 minGasCredits = limitOrderBook
    //                         .calculateMinGasCredits(
    //                             _amount,
    //                             executionCost,
    //                             address(this),
    //                             multiplier
    //                         );
    //                     uint256 expected = totalOrdersCount *
    //                         _amount *
    //                         executionCost *
    //                         multiplier;
    //                     assertEq(expected, minGasCredits);
    //                 }
    //             }
    //         }
    //     }
    // }

    ///@notice Test get total orders value
    function testGetTotalOrdersValue() public {
        swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        //create a new order
        LimitOrderBook.LimitOrder memory order = newOrder(
            swapToken,
            wnato,
            245000000000000000000,
            5,
            5
        );

        //place a mock order
        placeMockOrder(order);

        uint256 totalOrdersValue = limitOrderBook.totalOrdersQuantity(
            keccak256(abi.encode(address(this), swapToken))
        );
        assertEq(5, totalOrdersValue);
    }

    // ///@notice Test has min gas credits
    // function testHasMinGasCredits() public {
    //     cheatCodes.deal(address(this), MAX_UINT);
    //     IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

    //     (bool depositSuccess, ) = address(limitOrderBook).call{
    //         value: 100000000000000
    //     }(abi.encodeWithSignature("depositGasCredits()"));
    //     swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

    //     //create a new order
    //     LimitOrderBook.LimitOrder memory order = newOrder(
    //         swapToken,
    //         wnato,
    //         245000000000000000000,
    //         5,
    //         5
    //     );

    //     //place a mock order
    //     placeMockOrder(order);

    //     bool hasMinGasCredits = limitOrderBook.hasMinGasCredits(
    //         1000000,
    //         300000,
    //         address(this),
    //         100000000000000,
    //         1
    //     );
    //     //Assert the order should have the minimum gas credit requirements
    //     assertTrue(hasMinGasCredits);
    // }

    // ///@notice Test fail has min gas credits
    // function testFailHasMinGasCredits() public {
    //     IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

    //     cheatCodes.deal(address(this), MAX_UINT);
    //     (bool depositSuccess, ) = address(limitOrderBook).call{value: 1000000000000}(
    //         abi.encodeWithSignature("depositGasCredits()")
    //     ); //12 wei

    //     swapHelper.swapEthForTokenWithUniV2(20 ether, swapToken);

    //     //create a new order
    //     LimitOrderBook.LimitOrder memory order = newOrder(
    //         swapToken,
    //         wnato,
    //         245000000000000000000,
    //         5,
    //         5
    //     );

    //     //place a mock order
    //     placeMockOrder(order);

    //     bool hasMinGasCredits = limitOrderBook.hasMinGasCredits(
    //         50000000000,
    //         250000,
    //         address(this),
    //         150,
    //         1
    //     );

    //     assertTrue(hasMinGasCredits);
    // }

    //------------------Helper functions-----------------------

    function newOrder(
        address tokenIn,
        address tokenOut,
        uint128 price,
        uint128 quantity,
        uint128 amountOutMin
    ) internal view returns (LimitOrderBook.LimitOrder memory order) {
        //Initialize mock order
        order = LimitOrderBook.LimitOrder({
            stoploss: false,
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

    function newSandboxLimitOrder(
        address tokenIn,
        address tokenOut,
        uint128 amountInRemaining,
        uint128 amountOutRemaining
    )
        internal
        view
        returns (SandboxLimitOrderBook.SandboxLimitOrder memory order)
    {
        //Initialize mock order
        order = SandboxLimitOrderBook.SandboxLimitOrder({
            buy: false,
            fillPercent: 0,
            lastRefreshTimestamp: 0,
            expirationTimestamp: uint32(MAX_UINT),
            fee: 0,
            amountInRemaining: amountInRemaining,
            amountOutRemaining: amountOutRemaining,
            owner: address(this),
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    function placeMockOrder(LimitOrderBook.LimitOrder memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        LimitOrderBook.LimitOrder[]
            memory orderGroup = new LimitOrderBook.LimitOrder[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = limitOrderBook.placeLimitOrder(orderGroup);

        orderId = orderIds[0];
    }

    function placeMockSandboxLimitOrder(
        SandboxLimitOrderBook.SandboxLimitOrder memory order
    ) internal returns (bytes32 orderId) {
        //create a new array of orders
        SandboxLimitOrderBook.SandboxLimitOrder[]
            memory orderGroup = new SandboxLimitOrderBook.SandboxLimitOrder[](
                1
            );
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = sandboxLimitOrderBook
            .placeSandboxLimitOrder(orderGroup);

        orderId = orderIds[0];
    }

    function depositGasCreditsForMockOrders(uint256 _amount) public {
        cheatCodes.deal(address(this), _amount);
        (bool depositSuccess, ) = address(limitOrderExecutor).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        require(depositSuccess, "error when depositing gas credits");
    }
}
