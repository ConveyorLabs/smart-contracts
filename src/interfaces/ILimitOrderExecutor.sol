// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../LimitOrderBook.sol";
import "../SandboxLimitOrderBook.sol";
import "../SandboxRouter.sol";

interface ILimitOrderExecutor {
    function executeTokenToWethOrders(OrderBook.LimitOrder[] memory orders)
        external
        returns (uint256, uint256);

    function executeTokenToTokenOrders(OrderBook.LimitOrder[] memory orders)
        external
        returns (uint256, uint256);

    function executeSandboxLimitOrders(
        SandboxLimitOrderBook.SandboxLimitOrder[] memory orders,
        SandboxLimitOrderBook.SandboxMulticall calldata calls
    ) external;

    function gasCreditBalance(address user) external view returns (uint256);
}
