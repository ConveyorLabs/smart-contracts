// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../SandboxRouter.sol";
import "../OrderBook.sol";

interface ILimitOrderRouter {
    function placeSandboxLimitOrder(
        OrderBook.SandboxLimitOrder[] calldata orderGroup
    ) external payable returns (bytes32[] memory);

    function getSandboxLimitOrderById(bytes32 orderId)
        external
        view
        returns (OrderBook.SandboxLimitOrder memory);

    function getSandboxRouterAddress() external view returns (address);

    function gasCreditBalance(address addr) external returns (uint256);

    function depositGasCredits() external payable returns (bool success);

    function withdrawGasCredits(uint256 value) external returns (bool success);

    function refreshOrder(bytes32[] memory orderIds) external;

    function validateAndCancelOrder(bytes32 orderId)
        external
        returns (bool success);

    function executeLimitOrders(bytes32[] calldata orderIds) external;

    function executeOrdersViaSandboxMulticall(
        SandboxRouter.SandboxMulticall calldata sandboxMulticall
    ) external;

    function confirmTransferOwnership() external;

    function transferOwnership(address newOwner) external;
}
