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
        cheatCodes.deal(address(1352), 1 ether);
        cheatCodes.prank(address(1352));
        // require(false, "got here")       
        uint256 balanceBefore = address(conveyorLimitOrders).balance;
        console.logUint(balanceBefore);
        // require(false, "Got here");
        
        conveyorLimitOrders.depositCredits{value: 1 ether};
        console.log(address(this).balance);
        assertTrue(balanceBefore < address(conveyorLimitOrders).balance);
    }
}
