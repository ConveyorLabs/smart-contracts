// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../OrderBook.sol";

interface IConveyorExecutor {
    function executeTokenToWethOrders(OrderBook.Order[] memory orders) external;

    function executeTokenToTokenOrders(OrderBook.Order[] memory orders)
        external;
}
