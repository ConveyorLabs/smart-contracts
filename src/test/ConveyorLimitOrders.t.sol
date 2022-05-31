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

    function testSimulatePriceChange() public  view{
        uint256[] memory reserves = new uint256[](2);
        reserves[0]= 8363;
        reserves[1]=42574176;
        uint256 alphaX = 10;
        console.logString("TEST SIMULATE PRICE CHANGE");
        uint256 spot = conveyorLimitOrders.simulatePriceChange(alphaX, reserves);
        console.logString("Got here");
        
    }
}
