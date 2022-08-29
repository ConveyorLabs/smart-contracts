// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "../OrderBook.sol";

interface ITaxedLimitOrderExecution {
    function executeTokenToTokenTaxedOrders(OrderBook.Order[] memory orders)
        external;

    function executeTokenToWethTaxedOrders(OrderBook.Order[] memory orders)
        external;
}
