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
}

contract ConveyorLimitOrdersTest is DSTest {
    //Initialize limit-v0 contract for testing
    ConveyorLimitOrders conveyorLimitOrders;
    ConveyorLimitOrdersWrapper limitOrderWrapper;

    Swap swapHelper;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    //TODO: add univ3 address
    address uniV3Addr = address(0);

    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    //Factory and router address's
    address _uniV2Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _pancakeFactoryAddress = 0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    //pancake, sushi, uni create2 factory initialization bytecode
    bytes32 _pancakeHexDem =
        0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5;
    bytes32 _sushiHexDem =
        0xe18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303;
    bytes32 _uniswapV2HexDem =
        0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f;

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [_uniswapV2HexDem, _sushiHexDem, _uniswapV2HexDem];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [true, true, false];

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(uniV2Addr, uniV3Addr, WETH);
        conveyorLimitOrders = new ConveyorLimitOrders(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            5,
            2592000
        );
        conveyorLimitOrders.addDex(_dexFactories, _hexDems, _isUniV2);
    }

    //----------------------------TokenToToken Execution Tests-----------------------------------------

    // //Single order TokenToToken success
    function testExecuteTokenToTokenSingleSuccess() public {
        cheatCodes.prank(tx.origin);
        //Roughly 5.2
        OrderBook.Order memory order = newMockOrder(
            UNI,
            DAI,
            110680464442257309696,
            false,
            false,
            6900000000000000000,
            1
        );
        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = order.orderId;

        conveyorLimitOrders.executeOrders(orderBatch);
    }

    //Token to Token batch success
    function testExecuteTokenToTokenOrderBatchSuccess() public {
        cheatCodes.prank(tx.origin);
        bytes32[] memory tokenToTokenOrderBatch = newMockTokenToTokenBatch();

        conveyorLimitOrders.executeOrders(tokenToTokenOrderBatch);
    }

    //----------------------------TokenToWeth Execution Tests-----------------------------------------
    //Single order TokenToWeth success
    function testExecuteTokenToWethSingleSuccess() public {
        cheatCodes.prank(tx.origin);
        OrderBook.Order memory order = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );

        bytes32[] memory orderBatch = new bytes32[](1);

        orderBatch[0] = order.orderId;

        conveyorLimitOrders.executeOrders(orderBatch);
    }

    //Token to Weth Batch success
    function testExecuteTokenToWethOrderBatchSuccess() public {
        cheatCodes.prank(tx.origin);
        bytes32[] memory tokenToWethOrderBatch = newMockTokenToWethBatch();
        conveyorLimitOrders.executeOrders(tokenToWethOrderBatch);
    }

    //----------------------------_executeTokenToWethOrders Tests-----------------------------------------
    //Single success
    function executeTokenToWethOrdersSingleSuccess() public {
        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            16602069666338596454400,
            true,
            false,
            6900000000000000000,
            1
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](1);

        orderBatch[0] = order1;

        limitOrderWrapper.executeTokenToWethOrders(orderBatch);
    }

    //Batch success
    function executeTokenToWethOrdersBatchSuccess() public {
        OrderBook.Order[]
            memory tokenToWethOrderBatch = newMockTokenToWethBatchPass1();
        limitOrderWrapper.executeTokenToWethOrders(tokenToWethOrderBatch);
    }

    //----------------------------_executeTokenToWethBatchOrders Tests-----------------------------------------

    //----------------------------Gas Credit Tests-----------------------------------------
    function testDepositGasCredits(uint256 _amount) public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        //for fuzzing make sure that the input amount is < the balance of the test contract
        if (address(this).balance - _amount > _amount) {
            //deposit gas credits
            (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                value: _amount
            }(abi.encodeWithSignature("depositGasCredits()"));

            //require that the deposit was a success
            require(depositSuccess, "testDepositGasCredits: deposit failed");

            //get the updated gasCreditBalance for the address
            uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
                address(this)
            );

            //check that the creditBalance map has been updated
            require(gasCreditBalance == _amount);
        }
    }

    function testFailDepositGasCredits_InsufficientWalletBalance(
        uint256 _amount
    ) public {
        //for fuzzing make sure that the input amount is < the balance of the test contract
        console.log(address(this).balance);
        console.log(_amount);

        if (_amount > 0 && _amount > address(this).balance) {
            //deposit gas credits
            (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                value: _amount
            }(abi.encodeWithSignature("depositGasCredits()"));

            //require that the deposit was a success
            require(depositSuccess, "testDepositGasCredits: deposit failed");
        } else {
            require(false, "amount is 0");
        }
    }

    function testFailDepositGasCredits_InsufficientGasCreditBalanceForOrderExecution(
        uint256 _amount
    ) public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        //for fuzzing make sure that the input amount is < the balance of the test contract
        if (address(this).balance - _amount > _amount) {
            //deposit gas credits
            (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                value: _amount
            }(abi.encodeWithSignature("depositGasCredits()"));

            //require that the deposit was a success
            require(depositSuccess, "testDepositGasCredits: deposit failed");

            //get the updated gasCreditBalance for the address
            uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
                address(this)
            );

            //check that the creditBalance map has been updated
            require(gasCreditBalance == _amount);
        }
    }

    function testWithdrawGasCredits(uint256 _amount) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //deposit gas credits
        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: _amount
        }(abi.encodeWithSignature("depositGasCredits()"));

        //require that the deposit was a success
        require(depositSuccess, "testDepositGasCredits: deposit failed");

        //get the updated gasCreditBalance for the address
        uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
            address(this)
        );

        //check that the creditBalance map has been updated
        require(gasCreditBalance == _amount);

        bool withdrawSuccess = conveyorLimitOrders.withdrawGasCredits(_amount);

        require(withdrawSuccess, "Unable to withdraw credits");
    }

    function testFailRemoveGasCredits_InsufficientGasCreditBalance(
        uint256 _amount
    ) public {
        cheatCodes.deal(address(this), MAX_UINT);

        //ensure there is not an overflow for fuzzing
        bool overflow;
        assembly {
            overflow := lt(_amount, add(_amount, 1))
        }

        //make sure that amount+1 does not overflow
        if (!overflow) {
            if (_amount > 0) {
                //deposit gas credits
                (bool depositSuccess, ) = address(conveyorLimitOrders).call{
                    value: _amount
                }(abi.encodeWithSignature("depositGasCredits()"));

                //require that the deposit was a success
                require(
                    depositSuccess,
                    "testDepositGasCredits: deposit failed"
                );

                //withdraw one more than the
                bool withdrawSuccess = conveyorLimitOrders.withdrawGasCredits(
                    _amount + 1
                );

                require(withdrawSuccess, "Unable to withdraw credits");
            } else {
                require(false, "input is 0");
            }
        } else {
            require(false, "overflow");
        }
    }

    function testRefreshOrder() public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        // cheatCodes.deal(address(swapHelper), MAX_UINT);

        cheatCodes.prank(address(this));
        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: 90000000000000000000000000090000000
        }(abi.encodeWithSignature("depositGasCredits()"));

        uint256 gasCreditBalance = conveyorLimitOrders.gasCreditBalance(
            address(this)
        );

        //require that the deposit was a success
        require(depositSuccess, "testDepositGasCredits: deposit failed");

        swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);

        ConveyorLimitOrders.Order memory order = OrderBook.Order({
            tokenIn: swapToken,
            tokenOut: WETH,
            price: 16602069666338596454400,
            orderId: bytes32(0),
            buy: true,
            taxed: false,
            lastRefreshTimestamp: 0,
            expirationTimestamp: 2419200,
            quantity: 0,
            amountOutMin: 6900000000000000000,
            owner: address(this)
        });

        bytes32 orderId = placeMockOrder(order);

        bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);

        require(refreshSuccess == true, "Order Refresh failed");
    }

    function testRefreshOrder_CancelOrder_OrderHasReachedExpiration() public {
        // //deal this address max eth
        // cheatCodes.deal(address(this), MAX_UINT);
        // // cheatCodes.deal(address(swapHelper), MAX_UINT);
        // cheatCodes.prank(address(this));
        // (bool depositSuccess, ) = address(conveyorLimitOrders).call{
        //     value: 90000000000000000000000000090000000
        // }(abi.encodeWithSignature("depositGasCredits()"));
        // //require that the deposit was a success
        // require(depositSuccess, "testDepositGasCredits: deposit failed");
        // swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);
        // ConveyorLimitOrders.Order memory order = OrderBook.Order({
        //     tokenIn: swapToken,
        //     tokenOut: WETH,
        //     price: 16602069666338596454400,
        //     orderId: bytes32(0),
        //     buy: true,
        //     taxed: false,
        //     lastRefreshTimestamp: 0,
        //     expirationTimestamp: 0x0000000000000000000000000000000000000000000000000000008062c30102,
        //     quantity: 0,
        //     amountOutMin: 6900000000000000000,
        //     owner: address(this)
        // });
        // bytes32 orderId = placeMockOrder(order);
        // bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);
        // require(refreshSuccess == true, "Order Refresh failed");
    }

    function testlRefreshOrder_CancelOrder_InsufficientGasCreditBalance()
        public
    {
        // //deal this address max eth
        // cheatCodes.deal(address(this), MAX_UINT);
        // swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);
        // ConveyorLimitOrders.Order memory order = OrderBook.Order({
        //     tokenIn: swapToken,
        //     tokenOut: WETH,
        //     price: 16602069666338596454400,
        //     orderId: bytes32(0),
        //     buy: true,
        //     taxed: false,
        //     lastRefreshTimestamp: 0,
        //     expirationTimestamp: 2419200,
        //     quantity: 0,
        //     amountOutMin: 6900000000000000000,
        //     owner: address(this)
        // });
        // bytes32 orderId = placeMockOrder(order);
        // bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);
        // require(refreshSuccess == true, "Order Refresh failed");
    }

    function testFailRefreshOrder_OrderNotRefreshable() public {
        //deal this address max eth
        cheatCodes.deal(address(this), MAX_UINT);

        cheatCodes.prank(address(this));

        (bool depositSuccess, ) = address(conveyorLimitOrders).call{
            value: 90000000000000000000000000090000000
        }(abi.encodeWithSignature("depositGasCredits()"));

        //require that the deposit was a success
        require(depositSuccess, "testDepositGasCredits: deposit failed");

        swapHelper.swapEthForTokenWithUniV2(5 ether, swapToken);

        ConveyorLimitOrders.Order memory order = OrderBook.Order({
            tokenIn: swapToken,
            tokenOut: WETH,
            price: 16602069666338596454400,
            orderId: bytes32(0),
            buy: true,
            taxed: false,
            lastRefreshTimestamp: 0x0000000000000000000000000000000000000000000000000000000062c30102,
            expirationTimestamp: 2419200,
            quantity: 0,
            amountOutMin: 6900000000000000000,
            owner: address(this)
        });
        bytes32 orderId = placeMockOrder(order);

        bool refreshSuccess = conveyorLimitOrders.refreshOrder(orderId);

        require(refreshSuccess == true, "Order Refresh failed");
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
        bytes32[] memory orderIds = conveyorLimitOrders.placeOrder(orderGroup);

        orderId = orderIds[0];
    }

    receive() external payable {}

    // function testRefreshOrderFailOrderNotRefreshable(){
    //     OrderBook.Order memory order = OrderBook.Order({
    //         tokenIn: tokenIn,
    //         tokenOut: tokenOut,
    //         orderId: bytes32(0),
    //         buy: buy,
    //         taxed: taxed,
    //         lastRefreshTimestamp: 0,
    //         expirationTimestamp: 2419200,
    //         price: price,
    //         amountOutMin: amountOutMin,
    //         quantity: quantity,
    //         owner: msg.sender
    //     });
    // }

    // function testFailRemoveGasCredits_InsufficientGasCreditBalanceForOrderExecution(
    //     uint256 _amount
    // ) public {}

    // function testSimulatePriceChange() public {}

    // function testSimulatePriceChange() public {
    //     uint128[] memory reserves = new uint128[](2);
    //     reserves[0]= 82965859*2**18;
    //     reserves[1]=42918*2**18;
    //     uint128 alphaX = 1000000*2**18;
    //     console.logString("TEST SIMULATE PRICE CHANGE");
    //     uint256 spot = conveyorLimitOrders.simulatePriceChange(alphaX, reserves);
    //     assertEq(0x000000000000000000000000000007bc019f93509a129114c8df914ab5340000, spot);

    // }

    //----------------------------Order Batch Generators-----------------------------------------
    function newMockTokenToTokenBatchPass()
        internal
        view
        returns (OrderBook.Order[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            false,
            6900000000000000000,
            1
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](6);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        orderBatch[4] = order5;
        orderBatch[5] = order6;

        return orderBatch;
    }

    function newMockTokenToWethBatch()
        internal
        view
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );

        bytes32[] memory orderBatch = new bytes32[](6);
        orderBatch[0] = order1.orderId;
        orderBatch[1] = order2.orderId;
        orderBatch[2] = order3.orderId;
        orderBatch[3] = order4.orderId;
        orderBatch[4] = order5.orderId;
        orderBatch[5] = order6.orderId;

        return orderBatch;
    }

    function newMockTokenToTokenBatch()
        internal
        view
        returns (bytes32[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            false,
            6900000000000000000,
            1
        );

        bytes32[] memory orderBatch = new bytes32[](6);
        orderBatch[0] = order1.orderId;
        orderBatch[1] = order2.orderId;
        orderBatch[2] = order3.orderId;
        orderBatch[3] = order4.orderId;
        orderBatch[4] = order5.orderId;
        orderBatch[5] = order6.orderId;

        return orderBatch;
    }

    function newMockTokenToWethBatchPass1()
        internal
        view
        returns (OrderBook.Order[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            false,
            6900000000000000000,
            1
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](6);
        orderBatch[0] = order1;
        orderBatch[1] = order2;
        orderBatch[2] = order3;
        orderBatch[3] = order4;
        orderBatch[4] = order5;
        orderBatch[5] = order6;

        return orderBatch;
    }

    function newMockOrder(
        address tokenIn,
        address tokenOut,
        uint256 price,
        bool buy,
        bool taxed,
        uint256 amountOutMin,
        uint256 quantity
    ) internal view returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0),
            buy: buy,
            taxed: taxed,
            lastRefreshTimestamp: 0,
            expirationTimestamp: 2419200,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: msg.sender
        });
    }

    // function testOptimizeBatchLPOrderWithCancellation() public {}
}

abstract contract ConveyorLimitOrdersWrapper is ConveyorLimitOrders {
    function executeTokenToWethOrders(Order[] calldata orders) external {
        _executeTokenToWethOrders(orders);
    }
}
