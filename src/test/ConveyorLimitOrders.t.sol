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

    function testSimulatePriceChange() public {
        uint128[] memory reserves = new uint128[](2);
        reserves[0]= 82965859*2**18;
        reserves[1]=42918*2**18;
        uint128 alphaX = 1000000*2**18;
        console.logString("TEST SIMULATE PRICE CHANGE");
        uint256 spot = conveyorLimitOrders.simulatePriceChange(alphaX, reserves);
        assertEq(0x000000000000000000000000000007bc019f93509a129114c8df914ab5340000, spot);
        
    }
}
