// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

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

    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //MAX_UINT for testing
    uint256 constant MAX_UINT =
        115792089237316195423570985008687907853269984665640564039457584007913129639935;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        conveyorLimitOrders = new ConveyorLimitOrders(0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C);
    }

    function testExecuteOrder() public {}

    function testDepositGasCredits() public {
        cheatCodes.deal(address(1337), MAX_UINT);
        cheatCodes.prank(address(1337));

        uint256 balanceBefore = address(conveyorLimitOrders).balance;
        (bool success, ) = address(conveyorLimitOrders).call{value: 100}(
            abi.encodeWithSignature("depositCredits()")
        );

        assertTrue(balanceBefore < address(conveyorLimitOrders).balance);
    }

    // function testSimulatePriceChange() public {
    //     uint128[] memory reserves = new uint128[](2);
    //     reserves[0]= 82965859*2**18;
    //     reserves[1]=42918*2**18;
    //     uint128 alphaX = 1000000*2**18;
    //     console.logString("TEST SIMULATE PRICE CHANGE");
    //     uint256 spot = conveyorLimitOrders.simulatePriceChange(alphaX, reserves);
    //     assertEq(0x000000000000000000000000000007bc019f93509a129114c8df914ab5340000, spot);
        
    // }
    function newOrder(
        address tokenIn,
        address tokenOut,
        uint256 price,
        uint256 quantity
    ) internal pure returns (ConveyorLimitOrders.Order memory order) {
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
    function testOptimizeBatchLPOrder() public  {
        address token0 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address token1 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint128[][] memory reserveSizes = new uint128[][](2);
        uint128[] memory reserve1 = new uint128[](2);
        uint128[] memory reserve2 = new uint128[](2);
        reserve1[0]=82965859*2**18;
        reserve1[1]=42918*2**18;
        reserve2[0]=82965959*2**18;
        reserve2[1]=42918*2**18;
        reserveSizes[0]= reserve1;
        reserveSizes[1]=reserve2;
        
        reserveSizes[1][0]= 82965858*2**18;
        reserveSizes[1][1]=42918*2**18;
        
        address[] memory pairAddress = new address[](2);
        pairAddress[0]=0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        pairAddress[1]=0xB4e16D0168E52d35cacd2c6185B44281eC28c9Dd;
         OrderBook.Order memory order1 = newOrder(
            token0,
            token1,
            245000000000000000000,
            5
        );
        OrderBook.Order memory order2 = newOrder(
            token0,
            token1,
            245000000000000000000,
            8
        );
        OrderBook.Order memory order3 = newOrder(
            token0,
            token1,
            245000000000000000000,
            10
        );

        OrderBook.Order[] memory orders = new OrderBook.Order[](3);
        orders[0] = order1;
        orders[1]= order2;
        orders[2]= order3;
        
        address[] memory pairAddressOrder = conveyorLimitOrders.optimizeBatchLPOrder(orders, reserveSizes, pairAddress, false);
        

        console.logString("PAIR ADDRESS ORDER");
        console.logAddress(pairAddressOrder[0]);
        console.logAddress(pairAddressOrder[1]);
        console.logAddress(pairAddressOrder[2]);
    }
}
