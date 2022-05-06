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
    struct Order {
        address token;
        bytes32 orderId;
        OrderType orderType;
        uint256 price;
        uint256 quantity;
        bool exists;
    }
        enum OrderType {
        BUY,
        SELL,
        STOP,
        TAKE_PROFIT
    }
    //Instantiate limit-v0 contract for testing
    ConveyorLimitOrders conveyorLimitOrders;

    //Initialize cheatcodes
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

    //Link token
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;

    function setUp() public {
        
        conveyorLimitOrders = new ConveyorLimitOrders();
        
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        _uniV2Router = IUniswapV2Router02(_uniV2Address);
        _uniV2Factory = IUniswapV2Factory(_uniV2FactoryAddress);
        
    }

    receive() external payable {}

    function testPlaceOrder() public {
        //Deal address(1337) MAX Eth
        cheatCodes.deal(address(this), MAX_UINT);
        console.logString("Balance: " );
        
        cheatCodes.prank(address(this));
        //Swap Eth for UNI/Link to address(1337)
        //swapEthForToken(20, address(1337), 0x514910771AF9Ca656af840dff83E8264EcF986CA);
        //swapEthForToken(20, address(1337), 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984);
        console.logString("Got her");
        //Initialize mock orders
        // Order memory order1 = Order({
        //     token: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
        //     orderId: bytes32(keccak256(abi.encodePacked(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D))), //<--- just temporary 
        //     orderType: ConveyorLimitOrders.OrderType.SELL,
        //     price: 2700,
        //     quantity: 5,
        //     exists: true
        // });

        ConveyorLimitOrders.Order memory order2 = ConveyorLimitOrders.Order({
            token: 0x514910771AF9Ca656af840dff83E8264EcF986CA,
            orderId: bytes32(keccak256(abi.encodePacked(0x514910771AF9Ca656af840dff83E8264EcF986CA))), //<--- just temporary 
            orderType: ConveyorLimitOrders.OrderType.SELL,
            price: 11,
            quantity: 5,
            exists: true
        });

        ConveyorLimitOrders.Order memory order3 = ConveyorLimitOrders.Order({
            token: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984,
            orderId: bytes32(keccak256(abi.encodePacked(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984))), //<--- just temporary 
            orderType: ConveyorLimitOrders.OrderType.SELL,
            price: 8,
            quantity: 5,
            exists: true
        });
        
        ConveyorLimitOrders.Order[][] memory arrOrders;
        

        arrOrders[0][0]= order2;
        

        conveyorLimitOrders.placeOrder(arrOrders);
        

        

    }

    function testUpdateOrder() public {}

    function testCancelOrder() public {}

    function testCancelAllOrders() public {}

    function testExecuteOrder() public {}

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
}
