// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../LimitOrderRouter.sol";
import "../LimitOrderQuoter.sol";
import "../LimitOrderExecutor.sol";
import "../interfaces/ILimitOrderRouter.sol";
import "../interfaces/IOrderBook.sol";
import "../interfaces/ISandboxRouter.sol";

interface CheatCodes {
    function prank(address) external;

    function expectRevert(bytes memory) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

interface Errors {
    error FillAmountSpecifiedGreaterThanAmountRemaining(
        uint256 fillAmountSpecified,
        uint256 amountInRemaining,
        bytes32 orderId
    );
    error SandboxFillAmountNotSatisfied(
        bytes32 orderId,
        uint256 amountFilled,
        uint256 fillAmountRequired
    );

    error SandboxAmountOutRequiredNotSatisfied(
        bytes32 orderId,
        uint256 amountOut,
        uint256 amountOutRequired
    );
    error ConveyorFeesNotPaid(
        uint256 expectedFees,
        uint256 feesPaid,
        uint256 unpaidFeesRemaining
    );
}

contract SandboxRouterTest is DSTest {
    //Initialize All contract and Interface instances
    ILimitOrderRouter limitOrderRouter;
    IOrderBook orderBook;
    LimitOrderExecutorWrapper limitOrderExecutor;
    LimitOrderQuoter limitOrderQuoter;
    ISandboxRouter sandboxRouter;
    ScriptRunner scriptRunner;
    LimitOrderRouterWrapper limitOrderRouterWrapper;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    ///@notice Initialize cheatcodes
    CheatCodes cheatCodes;

    ///@notice Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    ///@notice Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    ///@notice Uniswap v2 Deployment bytescode
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    ///@notice Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _uniswapV2HexDem];
    address[] _dexFactories = [_uniV2FactoryAddress, _uniV3FactoryAddress];
    bool[] _isUniV2 = [true, false];
    uint256 SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST = 250000;
    ///@notice Fast Gwei Aggregator V3 address
    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    address payable mockOwner1 = payable(address(1));
    address payable mockOwner2 = payable(address(2));
    address payable mockOwner3 = payable(address(3));
    address payable mockOwner4 = payable(address(4));
    address payable mockOwner5 = payable(address(5));
    address payable mockOwner6 = payable(address(6));
    address payable mockOwner7 = payable(address(7));
    address payable mockOwner8 = payable(address(8));
    address payable mockOwner9 = payable(address(9));
    address payable mockOwner10 = payable(address(10));

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);

        limitOrderQuoter = new LimitOrderQuoter(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );

        limitOrderExecutor = new LimitOrderExecutorWrapper(
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderQuoter),
            _hexDems,
            _dexFactories,
            _isUniV2,
            aggregatorV3Address,
            300000,
            SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST
        );

        //Wrapper contract to test internal functions
        limitOrderRouterWrapper = new LimitOrderRouterWrapper(
            aggregatorV3Address,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            address(limitOrderExecutor),
            300000,
            250000
        );

        limitOrderRouter = ILimitOrderRouter(
            limitOrderExecutor.LIMIT_ORDER_ROUTER()
        );

        ///@notice Initialize an instance of the SandboxRouter Interface
        sandboxRouter = ISandboxRouter(
            limitOrderRouter.getSandboxRouterAddress()
        );
        {
            cheatCodes.deal(mockOwner1, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner1
            );
            cheatCodes.deal(mockOwner2, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner2
            );
            cheatCodes.deal(mockOwner3, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner3
            );
            cheatCodes.deal(mockOwner4, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner4
            );
            cheatCodes.deal(mockOwner5, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner5
            );
            cheatCodes.deal(mockOwner6, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner6
            );
            cheatCodes.deal(mockOwner7, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner7
            );
            cheatCodes.deal(mockOwner8, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner8
            );
            cheatCodes.deal(mockOwner9, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner9
            );
            cheatCodes.deal(mockOwner10, type(uint128).max);
            depositGasCreditsForMockOrdersCustomOwner(
                type(uint128).max,
                mockOwner10
            );
        }
    }

    //================================================================
    //=========== Sandbox Integration Tests ~ SandboxRouter  =========
    //================================================================

    //================Single Order Execution Tests====================

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderSingleV2() public {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(
            false,
            10000000000000000000,
            1,
            DAI,
            WETH
        );

        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall;

        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);
        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].fee;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;
            ///@notice Set the fill amount to the total amountIn on the order i.e. 1000 DAI.
            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall.
            calls[0] = newUniV2Call(daiWethV2, 0, 100, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        {
            ///@notice Get the Cached balances pre execution

            (
                uint256 txOriginBalanceBefore,
                uint256 gasCompensationUpperBound
            ) = initializePreSandboxExecutionTxOriginGasCompensationState(
                    orderIds,
                    tx.origin
                );

            uint256 wethBalanceBefore = IERC20(WETH).balanceOf(
                address(limitOrderExecutor)
            );
            ///@notice Prank tx.origin to mock an external executor
            cheatCodes.prank(tx.origin);

            ///@notice Execute the SandboxMulticall on the sandboxRouter
            sandboxRouter.executeSandboxMulticall(multiCall);
            address[] memory owners = new address[](1);
            owners[0] = address(this);
            validatePostSandboxExecutionGasCompensation(
                txOriginBalanceBefore,
                gasCompensationUpperBound
            );
            for (uint256 i = 0; i < orders.length; ++i) {
                OrderBook.SandboxLimitOrder memory orderPost = limitOrderRouter
                    .getSandboxLimitOrderById(orders[i].orderId);
                if (orders[i].amountInRemaining == multiCall.fillAmounts[i]) {
                    assert(orderPost.orderId == bytes32(0));
                } else {
                    assertEq(
                        orderPost.amountInRemaining,
                        orders[i].amountInRemaining - multiCall.fillAmounts[i]
                    );
                    assertEq(
                        orderPost.amountOutRemaining,
                        ConveyorMath.mul64U(
                            ConveyorMath.divUU(
                                orders[i].amountOutRemaining,
                                orders[i].amountInRemaining
                            ),
                            multiCall.fillAmounts[i]
                        )
                    );
                }
            }
            validatePostExecutionProtocolFees(wethBalanceBefore, orders);
        }
    }

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderSingleV3() public {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);
        // IERC20(DAI).approve(address(sandboxRouter), type(uint256).max);
        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(
            false,
            100000000000000000000,
            1,
            DAI,
            WETH
        );
        SandboxRouter.SandboxMulticall memory multiCall;
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);
        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);

            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);

            ///@notice Grab the order fee
            orders[0] = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].fee;

            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = address(sandboxRouter);
            ///@notice Set the fill amount to the total amountIn on the order i.e. 1000 DAI.
            fillAmounts[0] = order.amountInRemaining;

            ///@notice Create a single v2 swap call for the multicall.
            calls[0] = newUniV3Call(
                daiWethV3,
                address(sandboxRouter),
                address(this),
                true,
                100000000000000000000,
                DAI
            );
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);

            ///@notice Create a new SandboxMulticall
            multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        {
            ///@notice Get the Cached balances pre execution

            ///@notice Get the txOrigin and GasCompensation upper bound pre execution
            (
                uint256 txOriginBalanceBefore,
                uint256 gasCompensationUpperBound
            ) = initializePreSandboxExecutionTxOriginGasCompensationState(
                    orderIds,
                    tx.origin
                );
            ///@notice Cache the executor weth balance pre execution for fee validation
            uint256 wethBalanceBefore = IERC20(WETH).balanceOf(
                address(limitOrderExecutor)
            );

            ///@notice Prank tx.origin to mock an external executor
            cheatCodes.prank(tx.origin);

            ///@notice Execute the SandboxMulticall on the sandboxRouter
            sandboxRouter.executeSandboxMulticall(multiCall);

            ///@notice Assert the Gas for execution was as expected.
            validatePostSandboxExecutionGasCompensation(
                txOriginBalanceBefore,
                gasCompensationUpperBound
            );
            for (uint256 i = 0; i < orders.length; ++i) {
                OrderBook.SandboxLimitOrder memory orderPost = limitOrderRouter
                    .getSandboxLimitOrderById(orders[i].orderId);
                if (orders[i].amountInRemaining == multiCall.fillAmounts[i]) {
                    assert(orderPost.orderId == bytes32(0));
                } else {
                    assertEq(
                        orderPost.amountInRemaining,
                        orders[i].amountInRemaining - multiCall.fillAmounts[i]
                    );
                    assertEq(
                        orderPost.amountOutRemaining,
                        ConveyorMath.mul64U(
                            ConveyorMath.divUU(
                                orders[i].amountOutRemaining,
                                orders[i].amountInRemaining
                            ),
                            multiCall.fillAmounts[i]
                        )
                    );
                }
            }

            ///@notice Assert the protocol fees were compensated as expected
            validatePostExecutionProtocolFees(wethBalanceBefore, orders);
        }
    }

    //================Multi Order Execution Tests====================

    ///@notice ExecuteMulticallOrder Sandbox Router test
    function testExecuteMulticallOrderBatch() public {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        // IERC20(DAI).approve(address(sandboxRouter), type(uint256).max);
        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);

        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");

        (
            SandboxRouter.SandboxMulticall memory multiCall,
            OrderBook.SandboxLimitOrder[] memory orders,
            bytes32[] memory orderIds
        ) = createSandboxCallMultiOrderMulticall();

        {
            ///@notice Get the txOrigin and GasCompensation upper bound pre execution
            (
                uint256 txOriginBalanceBefore,
                uint256 gasCompensationUpperBound
            ) = initializePreSandboxExecutionTxOriginGasCompensationState(
                    orderIds,
                    tx.origin
                );
            ///@notice Cache the executor weth balance pre execution for fee validation
            uint256 wethBalanceBefore = IERC20(WETH).balanceOf(
                address(limitOrderExecutor)
            );

            ///@notice Prank tx.origin to mock an external executor
            cheatCodes.prank(tx.origin);

            ///@notice Execute the SandboxMulticall on the sandboxRouter
            sandboxRouter.executeSandboxMulticall(multiCall);

            ///@notice Assert the Gas for execution was as expected.
            validatePostSandboxExecutionGasCompensation(
                txOriginBalanceBefore,
                gasCompensationUpperBound
            );

            for (uint256 i = 0; i < orders.length; ++i) {
                OrderBook.SandboxLimitOrder memory order = limitOrderRouter
                    .getSandboxLimitOrderById(orders[i].orderId);
                if (orders[i].amountInRemaining == multiCall.fillAmounts[i]) {
                    assert(order.orderId == bytes32(0));
                } else {
                    assertEq(
                        order.amountInRemaining,
                        orders[i].amountInRemaining - multiCall.fillAmounts[i]
                    );

                    assertEq(
                        order.amountOutRemaining,
                        orders[i].amountOutRemaining -
                            ConveyorMath.mul64U(
                                ConveyorMath.divUU(
                                    orders[i].amountOutRemaining,
                                    orders[i].amountInRemaining
                                ),
                                multiCall.fillAmounts[i]
                            )
                    );
                }
            }

            ///@notice Assert the protocol fees were compensated as expected
            validatePostExecutionProtocolFees(wethBalanceBefore, orders);
        }
    }

    //================Execution Fail Case Tests====================
    function testFailExecuteMulticallOrder_FillAmountSpecifiedGreaterThanAmountRemaining()
        public
    {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(
            false,
            10000000000000000000,
            1,
            DAI,
            WETH
        );

        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall;

        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);
        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].fee;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining + 1; //Set fill amount to more than the amountInRemaining
            ///@notice Create a single v2 swap call for the multicall.
            calls[0] = newUniV2Call(daiWethV2, 0, 100, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function testFailExecuteMulticallOrder_SandboxAmountOutRequiredNotSatisfied()
        public
    {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(
            false,
            10000000000000000000,
            100000000000000000,
            DAI,
            WETH
        );

        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall;

        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);
        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].fee;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall.
            //AmountOutMin set to 1 which won't cover the amountOutRemaining
            calls[0] = newUniV2Call(daiWethV2, 0, 1, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function testFailExecuteMulticallOrder_SandboxFillAmountNotSatisfied()
        public
    {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(
            false,
            10000000000000000000,
            1,
            DAI,
            WETH
        );

        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](2);

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall;

        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);
        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](2);
            uint128[] memory fillAmounts = new uint128[](2);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            bytes32 orderId = placeMockOrder(order);
            orderIds[0] = orderId;
            orderIds[1] = orderId;
            ///@notice Grab the order fee
            orders[0] = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].fee * 2;
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = address(daiWethV2);
            transferAddress[1] = address(daiWethV2);
            fillAmounts[0] = 1;
            fillAmounts[1] = 100000000;

            ///@notice Create a single v2 swap call for the multicall.
            //AmountOutMin set to 1 which won't cover the amountOutRemaining
            calls[0] = newUniV2Call(daiWethV2, 0, 1, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function testFailExecuteMulticallOrder_ConveyorFeesNotPaid() public {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(
            false,
            10000000000000000000,
            1,
            DAI,
            WETH
        );

        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall;

        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);
        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](1);
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = 0; //Dont pay a fee should revert on ConveyorFeesNotPaid
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall.
            //AmountOutMin set to 1 which won't cover the amountOutRemaining
            calls[0] = newUniV2Call(daiWethV2, 0, 1, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    function testFailExecuteMulticallOrder_InvalidTransferAddressArray()
        public
    {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint256).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrders(type(uint128).max);
        ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        ///@notice Max approve the executor on the input token.
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint256).max);

        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order = newMockSandboxOrder(
            false,
            10000000000000000000,
            1,
            DAI,
            WETH
        );

        ///@notice Deal some ETH to compensate the fee
        cheatCodes.deal(address(sandboxRouter), type(uint128).max);
        cheatCodes.prank(address(sandboxRouter));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: 500000 ether}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        ///@notice Initialize Arrays for Multicall struct.
        bytes32[] memory orderIds = new bytes32[](1);

        ///@notice Create a new SandboxMulticall
        SandboxRouter.SandboxMulticall memory multiCall;

        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](2);
        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](1);
        {
            address[] memory transferAddress = new address[](2); //Set transfer addresses to a different size than orderIds, should revert on InvalidTransferAddressArray
            uint128[] memory fillAmounts = new uint128[](1);
            ///NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV2 = 0xA478c2975Ab1Ea89e8196811F51A7B7Ade33eB11;
            ///@notice Place the Order.
            orderIds[0] = placeMockOrder(order);
            ///@notice Grab the order fee
            orders[0] = limitOrderRouter.getSandboxLimitOrderById(orderIds[0]);
            uint256 cumulativeFee = orders[0].fee; //Dont pay a fee should revert on ConveyorFeesNotPaid
            ///@notice Set the DAI/WETH v2 lp address as the transferAddress.
            transferAddress[0] = daiWethV2;

            fillAmounts[0] = order.amountInRemaining;
            ///@notice Create a single v2 swap call for the multicall.
            //AmountOutMin set to 1 which won't cover the amountOutRemaining
            calls[0] = newUniV2Call(daiWethV2, 0, 1, address(this));
            ///@notice Create a call to compensate the feeAmount
            calls[1] = feeCompensationCall(cumulativeFee);
            multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddress,
                calls
            );
        }

        ///@notice Prank tx.origin to mock an external executor
        cheatCodes.prank(tx.origin);

        ///@notice Execute the SandboxMulticall on the sandboxRouter
        sandboxRouter.executeSandboxMulticall(multiCall);
    }

    //================================================================
    //====== Sandbox Execution Unit Tests ~ LimitOrderRouter =========
    //================================================================

    function testInitializeSandboxExecutionState(
        uint128 wethQuantity,
        uint128 daiQuantity,
        uint128 fillAmountWeth,
        uint128 fillAmountDai
    ) public {
        bool run;
        assembly {
            run := and(
                and(
                    lt(1000000000000000, wethQuantity),
                    lt(1000000000000000, daiQuantity)
                ),
                and(
                    lt(wethQuantity, 10000000000000000000000),
                    lt(daiQuantity, 10000000000000000000000)
                )
            )
        }
        if (run) {
            ///@notice Deal funds to all of the necessary receivers
            cheatCodes.deal(address(this), type(uint128).max);
            cheatCodes.deal(address(swapHelper), type(uint128).max);
            ///@notice Deposit Gas Credits to cover order execution.
            depositGasCreditsForMockOrdersWrapper(type(uint128).max);

            ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
            try swapHelper.swapEthForTokenWithUniV2(daiQuantity, DAI) returns (
                uint256 amountOut
            ) {
                ///@notice Max approve the executor on the input token.
                IERC20(DAI).approve(address(limitOrderExecutor), amountOut);
                {
                    cheatCodes.deal(address(this), wethQuantity);

                    ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
                    (bool depositSuccess, ) = address(WETH).call{
                        value: wethQuantity
                    }(abi.encodeWithSignature("deposit()"));
                    require(depositSuccess, "Fudge");
                    IERC20(WETH).approve(
                        address(limitOrderExecutor),
                        wethQuantity
                    );
                }
                ///@notice Dai/Weth sell limit order
                ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
                OrderBook.SandboxLimitOrder
                    memory orderWeth = newMockSandboxOrder(
                        false,
                        wethQuantity,
                        1,
                        WETH,
                        DAI
                    );
                OrderBook.SandboxLimitOrder
                    memory orderDai = newMockSandboxOrder(
                        false,
                        uint128(amountOut),
                        daiQuantity - 10000,
                        DAI,
                        WETH
                    );
                bytes32[] memory orderIds = new bytes32[](2);
                uint128[] memory fillAmounts = new uint128[](2);
                {
                    orderIds[0] = placeMockOrderWrapper(orderWeth);
                    orderIds[1] = placeMockOrderWrapper(orderDai);

                    fillAmounts[0] = fillAmountWeth;
                    fillAmounts[1] = fillAmountDai;
                }

                {
                    if (
                        fillAmountDai > amountOut ||
                        fillAmountWeth > wethQuantity
                    ) {
                        cheatCodes.expectRevert(
                            abi.encodeWithSelector(
                                Errors
                                    .FillAmountSpecifiedGreaterThanAmountRemaining
                                    .selector,
                                fillAmountWeth > wethQuantity
                                    ? fillAmountWeth
                                    : fillAmountDai,
                                fillAmountWeth > wethQuantity
                                    ? wethQuantity
                                    : amountOut,
                                fillAmountWeth > wethQuantity
                                    ? orderIds[0]
                                    : orderIds[1]
                            )
                        );
                        (bool reverted, ) = address(limitOrderRouterWrapper)
                            .call(
                                abi.encodeWithSignature(
                                    "_initializePreSandboxExecutionState(bytes32[],uint128[])",
                                    orderIds,
                                    fillAmounts
                                )
                            );
                        assertTrue(reverted);
                    } else {
                        (
                            ,
                            ,
                            uint256[] memory initialTokenInBalances,
                            uint256[] memory initialTokenOutBalances
                        ) = limitOrderRouterWrapper
                                ._initializePreSandboxExecutionState(
                                    orderIds,
                                    fillAmounts
                                );

                        assertEq(initialTokenInBalances[0], wethQuantity);
                        assertEq(initialTokenOutBalances[0], amountOut);
                        assertEq(initialTokenInBalances[1], amountOut);
                        assertEq(initialTokenOutBalances[1], wethQuantity);
                    }
                }
            } catch {}
        }
    }

    function testValidateSandboxExecutionAndFillOrders(
        uint128 wethQuantity,
        uint128 initialBalanceIn,
        uint128 daiQuantity,
        uint128 amountOutRemaining,
        uint128 fillAmountWeth
    ) public {
        bool run;
        {
            if (
                wethQuantity < 1000000000000000 ||
                daiQuantity < 1000000000000000 ||
                wethQuantity > 10000000000000000000000 ||
                daiQuantity > 10000000000000000000000
            ) {
                run = false;
            }
        }
        if (run) {
            if (
                fillAmountWeth <= wethQuantity &&
                initialBalanceIn < wethQuantity
            ) {
                initializeTestBalanceState(wethQuantity);

                uint256[] memory initialBalancesIn = new uint256[](1);
                uint256[] memory initialBalancesOut = new uint256[](1);

                {
                    initialBalancesIn[0] = initialBalanceIn;
                    initialBalancesOut[0] = 0;
                }
                ///@notice Swap 1000 Ether into Dai to fund the test contract on the input token
                try
                    swapHelper.swapEthForTokenWithUniV2(daiQuantity, DAI)
                returns (uint256 amountOut) {
                    {}
                    OrderBook.SandboxLimitOrder[]
                        memory orders = new OrderBook.SandboxLimitOrder[](1);

                    uint128[] memory fillAmounts = new uint128[](2);

                    {
                        ///@notice Dai/Weth sell limit order
                        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
                        orders[0] = newMockSandboxOrder(
                            false,
                            wethQuantity,
                            amountOutRemaining,
                            WETH,
                            DAI
                        );
                        bytes32[] memory orderIds = new bytes32[](2);
                        orderIds[0] = placeMockOrderWrapper(orders[0]);
                        fillAmounts[0] = fillAmountWeth;
                    }

                    validateSandboxExecutionAndFillOrders(
                        initialBalancesIn,
                        initialBalancesOut,
                        wethQuantity,
                        orders,
                        fillAmounts,
                        amountOut
                    );
                } catch {}
            }
        }
    }

    function validateSandboxExecutionAndFillOrders(
        uint256[] memory initialBalancesIn,
        uint256[] memory initialBalancesOut,
        uint256 wethQuantity,
        OrderBook.SandboxLimitOrder[] memory orders,
        uint128[] memory fillAmounts,
        uint256 amountOut
    ) internal {
        if (
            initialBalancesIn[0] - wethQuantity > fillAmounts[0] ||
            amountOut < orders[0].amountOutRemaining
        ) {
            cheatCodes.expectRevert(
                abi.encodeWithSelector(
                    initialBalancesIn[0] - wethQuantity > fillAmounts[0]
                        ? Errors.SandboxFillAmountNotSatisfied.selector
                        : Errors.SandboxAmountOutRequiredNotSatisfied.selector,
                    orders[0].orderId,
                    initialBalancesIn[0] - wethQuantity > fillAmounts[0]
                        ? initialBalancesIn[0] - wethQuantity
                        : amountOut,
                    initialBalancesIn[0] - wethQuantity > fillAmounts[0]
                        ? fillAmounts[0]
                        : ConveyorMath.mul64U(
                            ConveyorMath.divUU(
                                orders[0].amountOutRemaining,
                                orders[0].amountInRemaining
                            ),
                            fillAmounts[0]
                        )
                )
            );
            (bool status, ) = address(limitOrderRouterWrapper).call(
                abi.encodeWithSignature(
                    "_validateSandboxExecutionAndFillOrders(OrderBook.SandboxLimitOrder[],uint128[],uint256[],uint256[])",
                    orders,
                    fillAmounts,
                    initialBalancesIn,
                    initialBalancesOut
                )
            );
            assertTrue(status);
        } else {
            limitOrderRouterWrapper._validateSandboxExecutionAndFillOrders(
                orders,
                fillAmounts,
                initialBalancesIn,
                initialBalancesOut
            );
            {
                OrderBook.SandboxLimitOrder
                    memory postExecutionOrder = limitOrderRouterWrapper
                        .getSandboxLimitOrderById(orders[0].orderId);
                if (fillAmounts[0] == orders[0].amountInRemaining) {
                    assert(postExecutionOrder.orderId == bytes32(0));
                } else {
                    assertEq(
                        postExecutionOrder.amountInRemaining,
                        orders[0].amountInRemaining - fillAmounts[0]
                    );
                    assertEq(
                        postExecutionOrder.amountOutRemaining,
                        ConveyorMath.mul64U(
                            ConveyorMath.divUU(
                                orders[0].amountOutRemaining,
                                orders[0].amountInRemaining
                            ),
                            fillAmounts[0]
                        )
                    );
                }
            }
        }
    }

    function initializeTestBalanceState(uint128 wethQuantity) internal {
        ///@notice Deal funds to all of the necessary receivers
        cheatCodes.deal(address(this), type(uint128).max);
        cheatCodes.deal(address(swapHelper), type(uint128).max);
        ///@notice Deposit Gas Credits to cover order execution.
        depositGasCreditsForMockOrdersWrapper(type(uint128).max);
        cheatCodes.deal(address(this), wethQuantity);

        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: wethQuantity}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");
        IERC20(WETH).approve(address(limitOrderExecutor), wethQuantity);
    }

    //================================================================
    //====== Sandbox Execution Unit Tests ~ LimitOrderExecutor =======
    //================================================================
    function _requireConveyorFeeIsPaid(
        uint128 contractBalancePreExecution,
        uint128 expectedAccumulatedFees,
        uint128 compensationAmount
    ) public {
        cheatCodes.deal(address(limitOrderExecutor), compensationAmount);
        cheatCodes.prank(address(limitOrderExecutor));
        ///@notice Wrap the weth to send from the sandboxRouter to the executor in a call.
        (bool depositSuccess, ) = address(WETH).call{value: compensationAmount}(
            abi.encodeWithSignature("deposit()")
        );
        require(depositSuccess, "Fudge");

        if (
            contractBalancePreExecution + expectedAccumulatedFees >
            compensationAmount
        ) {
            cheatCodes.expectRevert(
                abi.encodeWithSelector(
                    Errors.ConveyorFeesNotPaid.selector,
                    expectedAccumulatedFees,
                    IERC20(WETH).balanceOf(address(limitOrderExecutor)) -
                        contractBalancePreExecution,
                    expectedAccumulatedFees -
                        ((compensationAmount + contractBalancePreExecution) -
                            contractBalancePreExecution)
                )
            );
            (bool reverted, ) = address(limitOrderExecutor).call(
                abi.encodeWithSignature(
                    "requireConveyorFeeIsPaid(uint256, uint256)",
                    uint256(contractBalancePreExecution),
                    uint256(expectedAccumulatedFees)
                )
            );
            contractBalancePreExecution + expectedAccumulatedFees >
                compensationAmount
                ? assertTrue(reverted)
                : assertTrue(!reverted);
        }
    }

    //================================================================
    //=========== Sandbox Execution State Assertion Helpers ==========
    //================================================================
    ///@notice Helper function to Cache the order owners token balances and gas credit balances
    function initializePreExecutionOwnerBalances(
        address[] memory owners,
        address[] memory tokenIn,
        address[] memory tokenOut
    )
        internal
        returns (
            uint256[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        uint256[] memory tokenInBalances = new uint256[](owners.length);
        uint256[] memory tokenOutBalances = new uint256[](owners.length);
        uint256[] memory gasCreditBalances = new uint256[](owners.length);

        for (uint256 i = 0; i < owners.length; ++i) {
            tokenInBalances[i] = IERC20(tokenIn[i]).balanceOf(owners[i]);
            tokenOutBalances[i] = IERC20(tokenOut[i]).balanceOf(owners[i]);
            gasCreditBalances[i] = limitOrderRouter.gasCreditBalance(owners[i]);
        }

        return (tokenInBalances, tokenOutBalances, gasCreditBalances);
    }

    ///@notice Helper to get the txOrigin balance and upper limit on gas compensation prior to execution
    function initializePreSandboxExecutionTxOriginGasCompensationState(
        bytes32[] memory orderIds,
        address txOrigin
    )
        internal
        returns (
            uint256 txOriginBalanceBefore,
            uint256 gasCompensationUpperBound
        )
    {
        gasCompensationUpperBound =
            limitOrderRouterWrapper.getGasPrice() *
            orderIds.length *
            SANDBOX_LIMIT_ORDER_EXECUTION_GAS_COST;
        txOriginBalanceBefore = address(txOrigin).balance;
        for (uint256 i = 0; i < orderIds.length; ++i) {
            OrderBook.SandboxLimitOrder memory order = limitOrderRouter
                .getSandboxLimitOrderById(orderIds[i]);
            ///@notice The order has been placed so it should have an orderId
            assert(order.orderId != bytes32(0));
        }
    }

    function validatePostSandboxExecutionGasCompensation(
        uint256 txOriginBalanceBefore,
        uint256 gasCompensationUpperBound
    ) internal {
        ///@notice The ETH balance of tx.origin - txOriginBalanceBefore is the total amount of gas credits compensated to the beacon for execution.
        uint256 totalGasCompensated = address(tx.origin).balance -
            txOriginBalanceBefore;

        ///@notice Ensure the totalGasCompensation didn't exceed the upper bound.
        assertLe(totalGasCompensated, gasCompensationUpperBound);
    }

    function validatePostExecutionProtocolFees(
        uint256 wethBalanceBefore,
        OrderBook.SandboxLimitOrder[] memory orders
    ) internal {
        uint256 totalOrderFees = 0;
        for (uint256 i = 0; i < orders.length; ++i) {
            totalOrderFees += orders[i].fee;
        }
        uint256 feesCompensated = IERC20(WETH).balanceOf(
            address(limitOrderExecutor)
        ) - wethBalanceBefore;
        assertEq(feesCompensated, totalOrderFees);
    }

    //================================================================
    //====================== Misc Helpers ============================
    //================================================================

    function createSandboxCallMultiOrderMulticall()
        internal
        returns (
            SandboxRouter.SandboxMulticall memory,
            OrderBook.SandboxLimitOrder[] memory,
            bytes32[] memory
        )
    {
        bytes32[] memory orderIds = placeNewMockMultiOrderMultiCall();

        uint256 cumulativeFee;

        OrderBook.SandboxLimitOrder[]
            memory orders = new OrderBook.SandboxLimitOrder[](10);
        {
            for (uint256 i = 0; i < orderIds.length; ++i) {
                OrderBook.SandboxLimitOrder memory order = limitOrderRouter
                    .getSandboxLimitOrderById(orderIds[i]);
                cumulativeFee += order.fee;
                orders[i] = order;
            }
        }

        uint128[] memory fillAmounts = new uint128[](10);
        {
            ///@dev DAI/WETH Order 1 Full Fill Against WETH/DAI Order1
            fillAmounts[0] = 120000000000000000000000;
            ///@dev DAI/WETH Order 2 Full Fill Against WETH/DAI Order2
            fillAmounts[1] = 120000000000000000000000;
            ///@dev DAI/WETH Order 3 Partial Fill amount = order.amountInRemaining/2.
            fillAmounts[2] = 5000000000000000000;
            ///@dev DAI/WETH Order 4 Full Fill amount.
            fillAmounts[3] = 100000000000000000000;
            ///@dev DAI/WETH Order 4 Partial Fill amount = order.amountInRemaining/2.
            fillAmounts[4] = 5000000000000000000;
            ///@dev USDC/WETH Order 1 Partial Fill amount = order.amountInRemaining/5.
            fillAmounts[5] = 2000000000;
            ///@dev USDC/WETH Order 2 Full Fill.
            fillAmounts[6] = 10000000000;
            ///@dev USDC/WETH Order 3 Full Fill.
            fillAmounts[7] = 10000000000;
            ///@dev WETH/DAI Order 1 Full Fill Against DAI/WETH Order1
            fillAmounts[8] = 100000000000000000000;
            ///@dev WETH/DAI Order 2 Full Fill Against DAI/WETH Order2
            fillAmounts[9] = 100000000000000000000;
        }

        SandboxRouter.Call[] memory calls = new SandboxRouter.Call[](3);
        {
            ///NOTE: Token0 = USDC & Token1 = WETH
            address usdcWethV2 = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
            //NOTE: Token0 = DAI & Token1 = WETH
            address daiWethV3 = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            calls[0] = newUniV3Call(
                daiWethV3,
                address(sandboxRouter),
                address(this),
                true,
                110000000000000000000,
                DAI
            );
            calls[1] = newUniV2Call(usdcWethV2, 0, 3000000, address(this));
            calls[2] = feeCompensationCall(cumulativeFee);
            address[] memory transferAddresses = new address[](10);
            transferAddresses[0] = address(mockOwner10); //Synthetically fill with WETH/DAI Order 10
            transferAddresses[1] = address(mockOwner9); //Synthetically fill with WETH/DAI Order 9
            transferAddresses[2] = address(sandboxRouter);
            transferAddresses[3] = address(sandboxRouter);
            transferAddresses[4] = address(sandboxRouter);
            transferAddresses[5] = usdcWethV2;
            transferAddresses[6] = usdcWethV2;
            transferAddresses[7] = usdcWethV2;
            transferAddresses[8] = address(mockOwner1); //Synthetically fill with DAI/WETH Order 1
            transferAddresses[9] = address(mockOwner2); //Synthetically fill with DAI/WETH Order 2
            SandboxRouter.SandboxMulticall memory multiCall = newMockMulticall(
                orderIds,
                fillAmounts,
                transferAddresses,
                calls
            );
            return (multiCall, orders, orderIds);
        }
    }

    ///@notice Helper function to create call to compensate the fees during execution
    function feeCompensationCall(uint256 cumulativeFee)
        public
        view
        returns (SandboxRouter.Call memory)
    {
        bytes memory callData = abi.encodeWithSignature(
            "transfer(address,uint256)",
            address(limitOrderExecutor),
            cumulativeFee
        );
        return SandboxRouter.Call({target: WETH, callData: callData});
    }

    ///@notice Helper function to create a single mock call for a v2 swap.
    function newUniV2Call(
        address _lp,
        uint256 amount0Out,
        uint256 amount1Out,
        address _receiver
    ) public pure returns (SandboxRouter.Call memory) {
        bytes memory callData = abi.encodeWithSignature(
            "swap(uint256,uint256,address,bytes)",
            amount0Out,
            amount1Out,
            _receiver,
            new bytes(0)
        );
        return SandboxRouter.Call({target: _lp, callData: callData});
    }

    ///@notice Helper function to create a single mock call for a v3 swap.
    function newUniV3Call(
        address _lp,
        address _sender,
        address _receiver,
        bool _zeroForOne,
        uint256 _amountIn,
        address _tokenIn
    ) public pure returns (SandboxRouter.Call memory) {
        ///@notice Pack the required data for the call.
        bytes memory data = abi.encode(_zeroForOne, _tokenIn, _sender);
        ///@notice Encode the callData for the call.
        bytes memory callData = abi.encodeWithSignature(
            "swap(address,bool,int256,uint160,bytes)",
            _receiver,
            _zeroForOne,
            int256(_amountIn),
            _zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1,
            data
        );
        ///@notice Return the call
        return SandboxRouter.Call({target: _lp, callData: callData});
    }

    ///@notice Helper function to create a Sandox Multicall
    function newMockMulticall(
        bytes32[] memory orderId,
        uint128[] memory fillAmounts,
        address[] memory transferAddresses,
        SandboxRouter.Call[] memory _calls
    ) public pure returns (SandboxRouter.SandboxMulticall memory) {
        return
            SandboxRouter.SandboxMulticall({
                orderIds: orderId,
                fillAmounts: fillAmounts,
                transferAddresses: transferAddresses,
                calls: _calls
            });
    }

    ///@notice Helper function to initialize a mock sandbox limit order
    function newMockSandboxOrder(
        bool buy,
        uint128 amountInRemaining,
        uint128 amountOutRemaining,
        address tokenIn,
        address tokenOut
    ) internal view returns (OrderBook.SandboxLimitOrder memory order) {
        //Initialize mock order
        order = OrderBook.SandboxLimitOrder({
            buy: buy,
            amountOutRemaining: amountOutRemaining,
            amountInRemaining: amountInRemaining,
            lastRefreshTimestamp: 0,
            expirationTimestamp: type(uint32).max,
            fee: 0,
            owner: msg.sender,
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0)
        });
    }

    ///@notice Gas credit deposit helper function.
    function depositGasCreditsForMockOrders(uint256 _amount) public {
        (bool depositSuccess, ) = address(limitOrderRouter).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        require(depositSuccess, "error when depositing gas credits");
    }

    function depositGasCreditsForMockOrdersWrapper(uint256 _amount) public {
        (bool depositSuccess, ) = address(limitOrderRouterWrapper).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        require(depositSuccess, "error when depositing gas credits");
    }

    ///@notice Gas credit deposit helper function.
    function depositGasCreditsForMockOrdersCustomOwner(
        uint256 _amount,
        address owner
    ) public {
        cheatCodes.prank(owner);
        (bool depositSuccess, ) = address(limitOrderRouter).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        require(depositSuccess, "error when depositing gas credits");
    }

    ///@notice Helper function to place a single sandbox limit order
    function placeMockOrder(OrderBook.SandboxLimitOrder memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        OrderBook.SandboxLimitOrder[]
            memory orderGroup = new OrderBook.SandboxLimitOrder[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = limitOrderRouter.placeSandboxLimitOrder(
            orderGroup
        );

        orderId = orderIds[0];
    }

    ///@notice Helper function to place a single sandbox limit order
    function placeMockOrderWrapper(OrderBook.SandboxLimitOrder memory order)
        internal
        returns (bytes32 orderId)
    {
        //create a new array of orders
        OrderBook.SandboxLimitOrder[]
            memory orderGroup = new OrderBook.SandboxLimitOrder[](1);
        //add the order to the arrOrder and add the arrOrder to the orderGroup
        orderGroup[0] = order;

        //place order
        bytes32[] memory orderIds = limitOrderRouterWrapper
            .placeSandboxLimitOrder(orderGroup);

        orderId = orderIds[0];
    }

    ///@notice helper function to place multiple sandbox orders
    function placeMultipleMockOrder(
        OrderBook.SandboxLimitOrder[] memory orderGroup
    ) internal returns (bytes32[] memory) {
        //place order
        bytes32[] memory orderIds = limitOrderRouter.placeSandboxLimitOrder(
            orderGroup
        );

        return orderIds;
    }

    function placeNewMockMultiOrderMultiCall()
        internal
        returns (bytes32[] memory)
    {
        cheatCodes.prank(mockOwner1);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner1);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        bytes32[] memory orderIds = new bytes32[](10);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order1 = newMockSandboxOrder(
            false,
            120000000000000000000000,
            100000000000000000000,
            DAI,
            WETH
        );
        cheatCodes.prank(mockOwner2);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner2);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order2 = newMockSandboxOrder(
            false,
            120000000000000000000000,
            100000000000000000000,
            DAI,
            WETH
        );
        cheatCodes.prank(mockOwner3);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner3);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order3 = newMockSandboxOrder(
            false,
            100000000000000000000,
            1,
            DAI,
            WETH
        );
        cheatCodes.prank(mockOwner4);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner4);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order4 = newMockSandboxOrder(
            false,
            100000000000000000000,
            1,
            DAI,
            WETH
        );
        cheatCodes.prank(mockOwner5);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, DAI);
        cheatCodes.prank(mockOwner5);
        IERC20(DAI).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice Dai/Weth sell limit order
        ///@dev amountInRemaining 1000 DAI amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order5 = newMockSandboxOrder(
            false,
            100000000000000000000,
            1,
            DAI,
            WETH
        );

        cheatCodes.prank(mockOwner6);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);
        cheatCodes.prank(mockOwner6);
        IERC20(USDC).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice USDC/Weth sell limit order
        ///@dev amountInRemaining 10000 USDC amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order6 = newMockSandboxOrder(
            false,
            10000000000,
            1,
            USDC,
            WETH
        );
        cheatCodes.prank(mockOwner7);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);
        cheatCodes.prank(mockOwner7);
        IERC20(USDC).approve(address(limitOrderExecutor), type(uint128).max);
        ///@notice USDC/Weth sell limit order
        ///@dev amountInRemaining 10000 USDC amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order7 = newMockSandboxOrder(
            false,
            10000000000,
            1,
            USDC,
            WETH
        );

        cheatCodes.prank(mockOwner8);
        swapHelper.swapEthForTokenWithUniV2(1000 ether, USDC);
        cheatCodes.prank(mockOwner8);
        IERC20(USDC).approve(address(limitOrderExecutor), type(uint128).max);

        ///@notice USDC/Weth sell limit order
        ///@dev amountInRemaining 10000 USDC amountOutRemaining 1 Wei
        OrderBook.SandboxLimitOrder memory order8 = newMockSandboxOrder(
            false,
            10000000000,
            1,
            USDC,
            WETH
        );
        cheatCodes.deal(address(mockOwner9), 1000000 ether);
        cheatCodes.prank(mockOwner9);
        IERC20(WETH).approve(address(limitOrderExecutor), type(uint128).max);

        {
            cheatCodes.prank(mockOwner9);
            ///@notice Wrap the weth to send to the executor in a call.
            (bool success, ) = address(WETH).call{value: 1000000 ether}(
                abi.encodeWithSignature("deposit()")
            );
            require(success, "fudge");
        }
        ///@notice Weth/Dai sell limit order
        ///@dev amountInRemaining 1000 WETH amountOutRemaining 120000.0 DAI
        OrderBook.SandboxLimitOrder memory order9 = newMockSandboxOrder(
            true,
            100000000000000000000,
            120000000000000000000000,
            WETH,
            DAI
        );
        cheatCodes.deal(address(mockOwner10), 1000000 ether);
        cheatCodes.prank(mockOwner10);
        IERC20(WETH).approve(address(limitOrderExecutor), type(uint128).max);

        {
            cheatCodes.prank(mockOwner10);
            ///@notice Wrap the weth to send to the executor in a call.
            (bool depositSuccess, ) = address(WETH).call{value: 1000000 ether}(
                abi.encodeWithSignature("deposit()")
            );
            require(depositSuccess, "fudge");
        }
        ///@notice Weth/Dai sell limit order
        ///@dev amountInRemaining 1000 WETH amountOutRemaining 120000.0 DAI
        OrderBook.SandboxLimitOrder memory order10 = newMockSandboxOrder(
            true,
            100000000000000000000,
            120000000000000000000000,
            WETH,
            DAI
        );
        {
            cheatCodes.prank(mockOwner1);
            orderIds[0] = placeMockOrder(order1);
            cheatCodes.prank(mockOwner2);
            orderIds[1] = placeMockOrder(order2);
            cheatCodes.prank(mockOwner3);
            orderIds[2] = placeMockOrder(order3);
            cheatCodes.prank(mockOwner4);
            orderIds[3] = placeMockOrder(order4);
            cheatCodes.prank(mockOwner5);
            orderIds[4] = placeMockOrder(order5);
            cheatCodes.prank(mockOwner6);
            orderIds[5] = placeMockOrder(order6);
            cheatCodes.prank(mockOwner7);
            orderIds[6] = placeMockOrder(order7);
            cheatCodes.prank(mockOwner8);
            orderIds[7] = placeMockOrder(order8);
            cheatCodes.prank(mockOwner9);
            orderIds[8] = placeMockOrder(order9);
            cheatCodes.prank(mockOwner10);
            orderIds[9] = placeMockOrder(order10);
        }
        return orderIds;
    }
}

//wrapper around SwapRouter to expose internal functions for testing
contract LimitOrderExecutorWrapper is LimitOrderExecutor {
    constructor(
        address _weth,
        address _usdc,
        address _limitOrderQuoter,
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2,
        address _gasOracle,
        uint256 _limitOrderExecutionGasCost,
        uint256 _sandboxLimitOrderExecutionGasCost
    )
        LimitOrderExecutor(
            _weth,
            _usdc,
            _limitOrderQuoter,
            _initBytecodes,
            _dexFactories,
            _isUniV2,
            _gasOracle,
            _limitOrderExecutionGasCost,
            _sandboxLimitOrderExecutionGasCost
        )
    {}

    function requireConveyorFeeIsPaid(
        uint256 contractBalancePreExecution,
        uint256 expectedAccumulatedFees
    ) public view {
        _requireConveyorFeeIsPaid(
            contractBalancePreExecution,
            expectedAccumulatedFees
        );
    }
}

contract LimitOrderRouterWrapper is LimitOrderRouter {
    constructor(
        address _gasOracle,
        address _weth,
        address _usdc,
        address _limitOrderExecutor,
        uint256 _limitOrderExecutionGasCost,
        uint256 _sandboxLimitOrderExecutionGasCost
    )
        LimitOrderRouter(
            _gasOracle,
            _weth,
            _usdc,
            _limitOrderExecutor,
            _limitOrderExecutionGasCost,
            _sandboxLimitOrderExecutionGasCost
        )
    {}

    function _initializePreSandboxExecutionState(
        bytes32[] calldata orderIds,
        uint128[] calldata fillAmounts
    )
        public
        view
        returns (
            SandboxLimitOrder[] memory,
            address[] memory,
            uint256[] memory,
            uint256[] memory
        )
    {
        return initializePreSandboxExecutionState(orderIds, fillAmounts);
    }

    function _validateSandboxExecutionAndFillOrders(
        SandboxLimitOrder[] memory sandboxLimitOrders,
        uint128[] memory fillAmounts,
        uint256[] memory initialTokenInBalances,
        uint256[] memory initialTokenOutBalances
    ) public {
        validateSandboxExecutionAndFillOrders(
            sandboxLimitOrders,
            fillAmounts,
            initialTokenInBalances,
            initialTokenOutBalances
        );
    }

    function executeSandboxLimitOrders(
        OrderBook.SandboxLimitOrder[] memory orders,
        SandboxRouter.SandboxMulticall calldata sandboxMulticall,
        address limitOrderExecutor
    ) public {
        ILimitOrderExecutor(address(limitOrderExecutor))
            .executeSandboxLimitOrders(orders, sandboxMulticall);
    }
}
