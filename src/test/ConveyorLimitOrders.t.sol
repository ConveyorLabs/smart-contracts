// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.14;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract ConveyorLimitOrdersTest is DSTest {
    //Initialize limit-v0 contract for testing
    ConveyorLimitOrders conveyorLimitOrders;
    ConveyorLimitOrdersWrapper limitOrderWrapper;
    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    //MAX_UINT for testing
    uint256 constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        conveyorLimitOrders = new ConveyorLimitOrders(
            0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2
        );
    }

    //----------------------------TokenToToken Execution Tests-----------------------------------------

    //Single order TokenToToken success
    function testExecuteTokenToTokenSingleSuccess() public {
        //Roughly 5.2
        OrderBook.Order memory order1 = newMockOrder(
            UNI,
            DAI,
            110680464442257309696,
            false,
            6900000000000000000,
            1
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](1);

        orderBatch[0]= order1;

        conveyorLimitOrders.executeOrders(orderBatch);
    }

    //Token to Token batch success
    function testExecuteTokenToTokenOrderBatchSuccess() public {
        OrderBook.Order[]
            memory tokenToTokenOrderBatch = newMockTokenToTokenBatchPass();
        conveyorLimitOrders.executeOrders(tokenToTokenOrderBatch);
    }



    //----------------------------TokenToWeth Execution Tests-----------------------------------------
    //Single order TokenToWeth success
    function testExecuteTokenToWethSingleSuccess() public {
        
        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](1);

        orderBatch[0]= order1;

        conveyorLimitOrders.executeOrders(orderBatch);
    }

    //Token to Weth Batch success
    function testExecuteTokenToWethOrderBatchSuccess() public {
        OrderBook.Order[]
            memory tokenToWethOrderBatch = newMockTokenToWethBatchPass();
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
            6900000000000000000,
            1
        );

        OrderBook.Order[] memory orderBatch = new OrderBook.Order[](1);

        orderBatch[0]= order1;

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

        //deposit gas credits
        (bool success, ) = address(conveyorLimitOrders).call{value: _amount}(
            abi.encodeWithSignature("depositCredits()")
        );

        //require that the deposit was a success
        require(success, "testDepositGasCredits: deposit failed");

        //get the updated gasCreditBalance for the address
        uint256 gasCreditBalance = conveyorLimitOrders.creditBalance(
            address(this)
        );

        //check that the creditBalance map has been updated
        require(gasCreditBalance == _amount);
    }

    function testFailDepositGasCredits() public {
        cheatCodes.deal(address(1337), 5);

        //deposit gas credits
        (bool success, ) = address(conveyorLimitOrders).call{value: 6}(
            abi.encodeWithSignature("depositCredits()")
        );

        //require that the deposit was a success
        require(success, "testDepositGasCredits: deposit failed");

        //get the updated gasCreditBalance for the address
        uint256 gasCreditBalance = conveyorLimitOrders.creditBalance(
            address(this)
        );

        //check that the creditBalance map has been updated
        require(gasCreditBalance == 5);
    }

    

    function testRemoveGasCredits() public {
        cheatCodes.deal(address(1227), 5);

        //deposit gas credits
        (bool success, ) = address(conveyorLimitOrders).call{value: 5}(
            abi.encodeWithSignature("depositCredits()")
        );

        //require that the deposit was a success
        require(success, "testDepositGasCredits: deposit failed");

        //get the updated gasCreditBalance for the address
        uint256 gasCreditBalance = conveyorLimitOrders.creditBalance(
            address(this)
        );

        //check that the creditBalance map has been updated
        require(gasCreditBalance == 5);
        cheatCodes.prank(address(1227));

        bool succ = conveyorLimitOrders.withdrawGasCredits(5);

        require(succ, "Unable to withdraw credits");
    }

    function testFailRemoveGasCredits() public {
        cheatCodes.deal(address(1228), 5);

        //deposit gas credits
        (bool success, ) = address(conveyorLimitOrders).call{value: 5}(
            abi.encodeWithSignature("depositCredits()")
        );

        //require that the deposit was a success
        require(success, "testDepositGasCredits: deposit failed");

        //get the updated gasCreditBalance for the address
        uint256 gasCreditBalance = conveyorLimitOrders.creditBalance(
            address(this)
        );

        //check that the creditBalance map has been updated
        require(gasCreditBalance == 5);

        cheatCodes.prank(address(1228));
        //Withdraw more than user creditBalance==5

        bool succ = conveyorLimitOrders.withdrawGasCredits(6);

        require(succ, "Unable to withdraw credits");

    }

    function testSimulatePriceChange() public {}

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
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            LINK,
            DAI,
            7 << 64,
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

    function newMockTokenToWethBatchPass()
        internal
        view
        returns (OrderBook.Order[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
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

    function newMockTokenToTokenBatchPass1()
        internal
        view
        returns (OrderBook.Order[] memory)
    {
        OrderBook.Order memory order1 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            LINK,
            DAI,
            83010348331692980000,
            true,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            UNI,
            DAI,
            83010348331692980000,
            true,
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
            6900000000000000000,
            1
        );
        OrderBook.Order memory order2 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order3 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order4 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order5 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
            false,
            6900000000000000000,
            1
        );
        OrderBook.Order memory order6 = newMockOrder(
            DAI,
            WETH,
            18446744073709550,
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
        uint256 amountOutMin,
        uint256 quantity
    ) internal view returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = OrderBook.Order({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            orderId: bytes32(0),
            buy: buy,
            price: price,
            amountOutMin: amountOutMin,
            quantity: quantity,
            owner: msg.sender
        });
    }

    function testOptimizeBatchLPOrderWithCancellation() public {}
}

abstract contract ConveyorLimitOrdersWrapper is ConveyorLimitOrders {
    function executeTokenToWethOrders(Order[] calldata orders) external {
        _executeTokenToWethOrders(orders);
    }
}
