// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../SandboxValidator.sol";

interface ISandboxValidator {
    function initializePreSandboxExecutionState(
        bytes32[][] calldata orderIdBundles,
        uint128[] calldata fillAmounts
    ) external returns (SandboxValidator.PreSandboxExecutionState memory);

    function validateSandboxExecutionAndFillOrders(
        bytes32[][] memory orderIdBundles,
        uint128[] memory fillAmounts,
        SandboxValidator.PreSandboxExecutionState
            memory preSandboxExecutionState
    ) external;
}
