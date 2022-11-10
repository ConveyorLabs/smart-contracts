// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "./interfaces/ILimitOrderRouter.sol";

/// @title SandboxRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice SandboxRouter uses a multiCall architecture to execute limit orders.
contract SandboxRouter {
    ///@notice LimitOrderExecutor & LimitOrderRouter Addresses.
    address immutable LIMIT_ORDER_EXECUTOR;
    address immutable LIMIT_ORDER_ROUTER;

    ///@notice Modifier to restrict addresses other than the LimitOrderExecutor from calling the contract
    modifier onlyLimitOrderExecutor() {
        if (msg.sender != LIMIT_ORDER_EXECUTOR) {
            revert MsgSenderIsNotLimitOrderExecutor();
        }
        _;
    }

    ///@notice Multicall Order Struct for multicall optimistic Order execution.
    ///@param orderIds - Array of orderIds that will be executed.
    ///@param fillAmounts - Array of quantities representing the quantity to be filled.
    ///@param transferAddresses - Array of addresses specifying where to transfer each order quantity at the corresponding index in the array.
    ///@param calls - Array of Call, specifying the address to call and the calldata to execute within the targetAddress context.
    struct SandboxMulticall {
        bytes32[] orderIds;
        uint128[] fillAmounts;
        address[] transferAddresses;
        Call[] calls;
    }

    ///@param target - Represents the target addresses to be called during execution.
    ///@param callData - Represents the calldata to be executed at the target address.
    struct Call {
        address target;
        bytes callData;
    }

    ///@notice Constructor for the sandbox router contract.
    ///@param _limitOrderExecutor - The LimitOrderExecutor contract address.
    ///@param _limitOrderRouter - The LimitOrderRouter contract address.
    constructor(address _limitOrderExecutor, address _limitOrderRouter) {
        LIMIT_ORDER_EXECUTOR = _limitOrderExecutor;
        LIMIT_ORDER_ROUTER = _limitOrderRouter;
    }

    ///@notice Function to execute multiple OrderGroups
    ///@param sandboxMultiCall The calldata to be executed by the contract.
    function executeSandboxMulticall(SandboxMulticall calldata sandboxMultiCall)
        external
    {
        ILimitOrderRouter(LIMIT_ORDER_ROUTER).executeOrdersViaSandboxMulticall(
            sandboxMultiCall
        );
    }

    ///@notice Callback function that executes a sandbox multicall and is only accessible by the limitOrderExecutor.
    ///@param sandBoxMulticall //TODO
    function sandboxRouterCallback(SandboxMulticall calldata sandBoxMulticall)
        external
        onlyLimitOrderExecutor
    {
        ///@notice Iterate through each target in the calls, and optimistically call the calldata.
        for (uint256 i = 0; i < sandBoxMulticall.calls.length; ) {
            Call memory sandBoxCall = sandBoxMulticall.calls[i];
            ///@notice Call the target address on the specified calldata
            (bool success, ) = sandBoxCall.target.call(sandBoxCall.callData);

            if (!success) {
                revert SandboxCallFailed();
            }

            unchecked {
                ++i;
            }
        }
    }
}
