// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../SandboxRouter.sol";

interface ISandboxRouter {
    ///@notice Callback function that executes a sandbox multicall and is only accessible by the limitOrderExecutor.
    ///@param sandBoxMulticall //TODO
    function sandboxRouterCallback(
        SandboxRouter.SandboxMulticall calldata sandBoxMulticall
    ) external;
}
