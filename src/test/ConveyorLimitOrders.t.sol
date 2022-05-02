// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import "./utils/test.sol";
import "../ConveyorLimitOrders.sol";

contract ConveyorLimitOrdersTest is DSTest {
    ConveyorLimitOrders conveyorLimitOrders;

    function setUp() public {
        conveyorLimitOrders = new ConveyorLimitOrders();
    }

    function testExample() public {
        assertTrue(true);
    }

    function testCancelOrder() public {}
}
