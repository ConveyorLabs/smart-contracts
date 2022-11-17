// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;
import "../SandboxLimitOrderRouter.sol";

interface ISandboxLimitOrderBook {
    function totalOrdersPerAddress(address owner)
        external
        view
        returns (uint256);

    function executeOrdersViaSandboxMulticall(
        SandboxLimitOrderRouter.SandboxMulticall calldata sandboxMulticall
    ) external;
}
