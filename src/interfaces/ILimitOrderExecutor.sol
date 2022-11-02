// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../OrderBook.sol";
import "../SandboxRouter.sol";

interface ILimitOrderExecutor {
    function executeTokenToWethOrders(OrderBook.LimitOrder[] memory orders)
        external
        returns (uint256, uint256);

    function executeTokenToTokenOrders(OrderBook.LimitOrder[] memory orders)
        external
        returns (uint256, uint256);

    function executeMultiCallOrders(
        OrderBook.SandboxLimitOrder[] memory orders,
        uint128[] memory amountSpecifiedToFill,
        SandboxRouter.SandboxMulticall memory calls,
        address sandBoxRouter
    ) external;
}
