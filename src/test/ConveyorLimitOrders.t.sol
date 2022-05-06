// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";

import "../ConveyorLimitOrders.sol";
import "../../lib/interfaces/IUniswapV2Router02.sol";
import "../../lib/interfaces/IUniswapV2Factory.sol";
import "../../lib/interfaces/IERC20.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract ConveyorLimitOrdersTest is DSTest {
    ConveyorLimitOrders conveyorLimitOrders;
    CheatCodes cheatCodes;
    IUniswapV2Router02 _uniV2Router;
    IUniswapV2Factory _uniV2Factory;

    //MAX_UINT for testing
    uint256 constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    //Native token address WETH
    address _wnatoAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    //Factory and router address's
    address _uniV2Address = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    function setUp() public {
        conveyorLimitOrders = new ConveyorLimitOrders();

        cheatCodes = CheatCodes(HEVM_ADDRESS);
        _uniV2Router = IUniswapV2Router02(_uniV2Address);
        _uniV2Factory = IUniswapV2Factory(_uniV2FactoryAddress);
    }

    receive() external payable {}

    function testPlaceOrder() public {
        cheatCodes.deal(address(this), MAX_UINT);

        //swap 20 ether for the swap token
        swapEthForToken(20 ether, 0x514910771AF9Ca656af840dff83E8264EcF986CA);

        ConveyorLimitOrders.Order memory order = newOrder(
            swapToken,
            245000000000000000000,
            5
        );

        placeMockOrder(order);
    }

    function testUpdateOrder() public {
        //swap 20 ether for the swap token
        swapEthForToken(20 ether, 0x514910771AF9Ca656af840dff83E8264EcF986CA);

        //create a new order
        ConveyorLimitOrders.Order memory order = newOrder(
            swapToken,
            245000000000000000000,
            5
        );
        //place a mock order
        bytes32 orderId = placeMockOrder(order);

        //create a new order to replace the old order
        ConveyorLimitOrders.Order memory updatedOrder = newOrder(
            swapToken,
            245000000000000000000,
            5
        );
        updatedOrder.orderId = orderId;

        //submit the updated order
        conveyorLimitOrders.updateOrder(updatedOrder);
    }

    function testCancelOrder() public {}

    function testCancelAllOrders() public {}

    function testExecuteOrder() public {}

    //-----------------------------Helper Functions----------------------------

    function swapEthForToken(uint256 amount, address _swapToken) internal {
        cheatCodes.deal(address(this), amount);

        //set the path
        address[] memory path = new address[](2);
        path[0] = _wnatoAddress;
        path[1] = _swapToken;

        // swap eth for tokens
        _uniV2Router.swapExactETHForTokens{value: amount}(
            1,
            path,
            address(this),
            (2**256 - 1)
        );
    }

    function newOrder(
        address token,
        uint256 price,
        uint256 quantity
    ) internal returns (ConveyorLimitOrders.Order memory order) {
        //Initialize mock order
        order = ConveyorLimitOrders.Order({
            token: token,
            orderId: bytes32(0),
            orderType: ConveyorLimitOrders.OrderType.SELL,
            price: price,
            quantity: quantity,
            exists: true
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
        bytes32[] memory orderIds = conveyorLimitOrders.placeOrder(orderGroup);

        orderId = orderIds[0];
    }
}
