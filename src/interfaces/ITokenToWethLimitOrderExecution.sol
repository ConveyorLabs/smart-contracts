// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../OrderBook.sol";

interface ITokenToWethLimitOrderExecution {
    function executeTokenToWethOrderSingle(OrderBook.Order[] memory orders)
        external;

    function executeTokenToWethOrders(OrderBook.Order[] memory orders) external;
}
