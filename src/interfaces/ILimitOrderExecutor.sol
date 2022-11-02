// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../OrderBook.sol";
import "../SandboxRouter.sol";

interface ILimitOrderExecutor {
    function executeTokenToWethOrders(OrderBook.Order[] memory orders)
        external
        returns (uint256, uint256);

    function executeTokenToTokenOrders(OrderBook.Order[] memory orders)
        external
        returns (uint256, uint256);

    function executeMultiCallOrders(
        OrderBook.MultiCallOrder[] memory orders,
        uint128[] memory amountSpecifiedToFill,
        ChaosRouter.MultiCall memory calls,
        address sandBoxRouter
    ) external;
}
