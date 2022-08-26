// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "./OrderBook.sol";
import "./OrderRouter.sol";

interface ILimitOrderBatcher {
    function batchTokenToTokenOrders(
        OrderBook.Order[] memory orders,
        OrderRouter.TokenToTokenExecutionPrice[] memory executionPrices
    ) external returns (OrderRouter.TokenToTokenBatchOrder[] memory);
}
