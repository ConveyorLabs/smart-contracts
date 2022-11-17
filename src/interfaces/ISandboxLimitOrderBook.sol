// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import "../SandboxLimitOrderRouter.sol";
import "../SandboxLimitOrderBook.sol";

interface ISandboxLimitOrderBook {
    function totalOrdersPerAddress(address owner)
        external
        view
        returns (uint256);

    function executeOrdersViaSandboxMulticall(
        SandboxLimitOrderRouter.SandboxMulticall calldata sandboxMulticall
    ) external;

    function getSandboxLimitOrderRouterAddress()
        external
        view
        returns (address);

    function getSandboxLimitOrderById(bytes32 orderId)
        external
        view
        returns (SandboxLimitOrderBook.SandboxLimitOrder memory);

    function addressToOrderIds(address owner, bytes32 orderId)
        external
        view
        returns (SandboxLimitOrderBook.OrderType);

    function placeSandboxLimitOrder(
        SandboxLimitOrderBook.SandboxLimitOrder[] calldata orderGroup
    ) external payable returns (bytes32[] memory);
}
