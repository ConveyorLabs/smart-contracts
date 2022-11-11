// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../SandboxRouter.sol";

interface ISandboxRouter {
    ///TODO: Maybe low level call this
    ///@notice Callback function that executes a sandbox multicall and is only accessible by the limitOrderExecutor.
    ///@param sandboxMulticall - Struct containing the SandboxMulticall data. See the SandboxMulticall struct for a description of each parameter.
    function sandboxRouterCallback(
        SandboxRouter.SandboxMulticall calldata sandboxMulticall
    ) external;

    function executeSandboxMulticall(SandboxRouter.SandboxMulticall calldata sandboxMultiCall)
        external;
        
}
