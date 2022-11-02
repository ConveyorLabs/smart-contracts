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
    ///@param orderIds - A full list of the orderIds that will be executed in execution.
    ///@param amountSpecifiedToFill - Array of quantities representing the quantity to be filled on the input amount for each order indexed identically in the orderIds array.
    struct SandboxMulticall {
        bytes32[] orderIds;
        uint128[] amountSpecifiedToFill;
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
        ///TODO: need to edit this
        /**@notice 
                ✨This function is to be used exclusively for non stoploss orders. The contract works by accepting an array of `Call`, containing arbitrary calldata and a target address  passed from the  off chain executor. 
                This function first calls initializeMulticallCallbackState() on the LimitOrderRouter contract where the state prior to execution of all the order owners balances is stored.

                The LimitOrderRouter makes a single external call to the LimitOrderExecutor which calls safeTransferFrom() on the users wallet to the ChaosRouter contract. The LimitOrderExecutor
                then calls executeMultiCallCallback() on the ChaosRouter. The ChaosRouter optimistically executes the calldata passed by the offchain executor. Once all the callback has finished 
                the LimitOrderRouter contract then cross references the Initial State vs the Current State of Token balances in the contract to determine if all Orders have received their target quantity
                based on the amountSpecifiedToFill*order.price. 
                
                The ChaosRouter works in a much different way than traditional LimitOrder systems to date. It allows for Executors to be creative in the
                strategies they employ for execution. To be clear, the only rule when executing with the ChaosRouter is there are no rules. An executor is welcome to do whatever they want with the funds
                during execution, so long as each Order gets filled their exact amount. Further, any profit reaped on the multicall goes 100% back to the executor.✨
         **/

        ///@notice Upon initialization call the LimitOrderRouter contract to cache the initial state prior to execution.
        ILimitOrderRouter(LIMIT_ORDER_ROUTER).executeOrdersViaSandboxMulticall(
            sandboxMultiCall
        );
    }

    ///@notice Callback function that executes a sandbox multicall and is only accessible by the limitOrderExecutor.
    ///@param sandBoxMulticall //TODO
    function sandboxRouterCallback(SandboxMulticall memory sandBoxMulticall)
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

    //TODO: function for arbitrary execution, ensuring that the user has their tokens at the end
}
