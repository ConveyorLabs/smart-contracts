// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../OrderBook.sol";
import "../SandboxRouter.sol";
import "../LimitOrderExecutor.sol";

interface ILimitOrderExecutor {
    function executeTokenToWethOrders(OrderBook.LimitOrder[] memory orders)
        external
        returns (uint256, uint256);

    function executeTokenToTokenOrders(OrderBook.LimitOrder[] memory orders)
        external
        returns (uint256, uint256);

    function executeSandboxLimitOrders(
        OrderBook.SandboxLimitOrder[] memory orders,
        SandboxRouter.SandboxMulticall calldata calls
    ) external;
}
