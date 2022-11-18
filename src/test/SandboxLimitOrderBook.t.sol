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
import "../LimitOrderSwapRouter.sol";
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
    ISandboxLimitOrderBook sandboxLimitOrderBook;

    event OrderPlaced(bytes32[] orderIds);
    event OrderCanceled(bytes32[] orderIds);
    event OrderUpdated(bytes32[] orderIds);

    //----------------State variables for testing--------------------
    ///@notice initialize swap helper
    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

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

        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
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

    //Test to get SandboxLimitOrder
    function testGetSandboxLimitOrderById() public {
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);

        swapHelper.swapEthForTokenWithUniV2(100 ether, swapToken);

        //create a new order
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(swapToken, WETH, 10e21, 5);
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
    function testFailGetSandboxLimitOrderById_OrderDoesNotExist() public view {
        sandboxLimitOrderBook.getSandboxLimitOrderById(bytes32(0));
    }

    function testGetOrderIds() public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);
        //if the fuzzed amount is enough to complete the swap
        swapHelper.swapEthForTokenWithUniV2(100 ether, swapToken);

        bytes32 orderId1 = placeMockSandboxLimitOrder(
            newSandboxLimitOrder(swapToken, WETH, 10e21, uint112(1))
        );

        bytes32 orderId2 = placeMockSandboxLimitOrder(
            newSandboxLimitOrder(swapToken, WETH, 10e21, uint112(1))
        );

        sandboxLimitOrderBook.cancelOrder(orderId2);

        uint256 orderIdsLength = sandboxLimitOrderBook.getAllOrderIdsLength(
            address(this)
        );

        bytes32[] memory pendingSandboxLimitOrders = sandboxLimitOrderBook
            .getOrderIds(
                address(this),
                SandboxLimitOrderBook.OrderType.PendingSandboxLimitOrder,
                0,
                orderIdsLength
            );

        bytes32[] memory canceledSandboxLimitOrders = sandboxLimitOrderBook
            .getOrderIds(
                address(this),
                SandboxLimitOrderBook.OrderType.CanceledSandboxLimitOrder,
                0,
                orderIdsLength
            );

        assertEq(pendingSandboxLimitOrders.length, 1);
        assertEq(canceledSandboxLimitOrders.length, 1);

        assertEq(pendingSandboxLimitOrders[0], orderId1);
        assertEq(canceledSandboxLimitOrders[0], orderId2);
    }

    ///@notice Test palce order fuzz test
    function testPlaceSandboxOrder(
        uint112 amountInRemaining,
        uint112 amountOutRemaining
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);
        IERC20(swapToken).approve(address(limitOrderExecutor), MAX_UINT);
        if (!(amountInRemaining < 10e21)) {
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
                        WETH,
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
                WETH,
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
                    WETH,
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
                WETH,
                10e21,
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

    function testValidateAndCancelOrder() public {
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(WETH, swapToken, 1 ether, 0);

        depositGasCreditsForMockOrders(type(uint128).max);

        cheatCodes.deal(address(this), type(uint128).max);

        (bool depositSuccess, ) = address(WETH).call{value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "failure when depositing ether into weth");

        IERC20(WETH).approve(address(limitOrderExecutor), MAX_UINT);
        bytes32 orderId = placeMockSandboxLimitOrder(order);

        IWETH(WETH).withdraw(100000);

        bool canceled = sandboxLimitOrderBook.validateAndCancelOrder(orderId);
        assertTrue(canceled);

        SandboxLimitOrderBook.OrderType orderType = sandboxLimitOrderBook
            .addressToOrderIds(address(this), orderId);

        assert(
            orderType ==
                SandboxLimitOrderBook.OrderType.CanceledSandboxLimitOrder
        );
    }

    //Should fail validateAndCancel since user has the min credit balance
    function testFailValidateAndCancelOrder() public {
        SandboxLimitOrderBook.SandboxLimitOrder
            memory order = newSandboxLimitOrder(WETH, swapToken, 10e16, 0);

        cheatCodes.deal(address(this), MAX_UINT);

        IERC20(WETH).approve(address(limitOrderExecutor), MAX_UINT);

        depositGasCreditsForMockOrders(type(uint128).max);

        (bool depositSuccess, ) = address(WETH).call{value: 1 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "failure when depositing ether into weth");

        bytes32 orderId = placeMockSandboxLimitOrder(order);

        bool canceled = sandboxLimitOrderBook.validateAndCancelOrder(orderId);
        assertTrue(!canceled);

        SandboxLimitOrderBook.OrderType orderType = sandboxLimitOrderBook
            .addressToOrderIds(address(this), orderId);

        assert(
            orderType ==
                SandboxLimitOrderBook.OrderType.CanceledSandboxLimitOrder
        );
    }

    //------------------Helper functions-----------------------

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

    receive() external payable {}
}
