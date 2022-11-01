// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";

/// @title ChaosRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice ChaosRouter uses a MultiCall Architecture to execute LimitOrders. 
contract ChaosRouter {

    address immutable LIMIT_ORDER_EXECUTOR;
    address LIMIT_ORDER_ROUTER;

    ///@notice Modifier to restrict smart contracts from calling a function.
    modifier onlyLimitOrderExecutor() {
        if (msg.sender != LIMIT_ORDER_EXECUTOR) {
            revert MsgSenderIsNotLimitOrderRouter();
        }
        _;
    }
    ///@notice Multicall Order Struct for multicall optimistic Order execution.
    ///@param orderIds - A full list of the orderIds that will be executed in execution.
    ///@param targets - Array of identical length to calldata array. Represents the list of target addresses to be called during execution.
    ///@param callData - Array of identical length to targets array. Represents the list of calldata to be called to the target address at the same index.
    ///@param amountSpecifiedToFill - Array of quantities representing the quantity to be filled on the input amount for each order indexed identically in the orderIds array.
    struct MultiCall {
        bytes32[] orderIds;
        address[] targets;
        bytes[] callData;
        uint128[] amountSpecifiedToFill;
    }

    ///@notice Constructor for the sandbox router contract.
    ///@param _limitOrderExecutor - The LimitOrderExecutor contract address.
    ///@param _limitOrderRouter - The LimitOrderRouter contract address.
    constructor(address _limitOrderExecutor, address _limitOrderRouter) {
        LIMIT_ORDER_EXECUTOR=_limitOrderExecutor;
        LIMIT_ORDER_ROUTER=_limitOrderRouter;
    }

    ///@notice Function to execute multiple OrderGroups
    ///@param calls The calldata to be executed by the contract.
    function executeMulticall(MultiCall calldata calls) external {
        /**@notice 
                ✨This function is to be used exclusively for non stoploss. The Multicall contract works by accepting arbitrary calldata passed from the off chain executor. 
                The first order of logic calls initializeMulticallCallbackState() to the LimitOrderRouter contract where the state prior to execution of all the order owners balances is stored. 
                The LimitOrderRouter makes a single external call to the LimitOrderExecutor which calls safeTransferFrom() on the users wallet to the ChaosRouter contract. The LimitOrderExecutor
                then calls executeMultiCallCallback() on the ChaosRouter. The ChaosRouter optimistically executes the calldata passed by the offchain executor. Once all the callback has finished 
                the LimitOrderRouter contract then cross references the Initial State vs the Current State of Token balances in the contract to determine if all Orders have received their target quantity
                based on the amountSpecifiedToFill*order.price. The ChaosRouter works in a much different way than traditional LimitOrder systems to date. It allows for Executors to be creative in the
                strategies they employ for execution. To be clear, the only rule when executing with the ChaosRouter is there are no rules. An executor is welcome to do whatever they want with the funds
                during execution, so long as each Order gets filled their exact amount. Further, any profit reaped on the multicall goes 100% back to the executor.✨
         **/ 
        ///@notice Bool indicating whether low level call was successful.
        bool success;
        ///@notice Upon initialization call the LimitOrderRouter contract to cache the initial state prior to execution. 
        bytes memory bytesSig = abi.encodeWithSignature("initializeMulticallCallbackState(MultiCall)", calls);
        
        assembly {
            mstore(
                0x00,
                bytesSig
            )

            success := call(
                gas(), // gas remaining
                LIMIT_ORDER_ROUTER.offset, // destination address
                0, // no ether
                0x00, // input buffer (starts after the first 32 bytes in the `data` array)
                0x04, // input length (loaded from the first 32 bytes in the `data` array)
                0x00, // output buffer
                0x00 // output length
            )
        }
    }

    ///@notice Function called by the LimitOrderExecutor contract to execute the multicall.
    ///@param calls - The multicall calldata.
    function executeMultiCallCallback(MultiCall memory calls) external onlyLimitOrderExecutor {
        ///@notice Iterate through each target in the calls, and optimistically call the calldata.
        for (uint256 k = 0; k < calls.targets.length; ) {
            ///@notice Call the target address on the specified calldata
            (bool success, ) = calls.targets[k].call(calls.callData[k]);
            require(success, "Call failed in multicall");
            unchecked {
                ++k;
            }
        }
    }
}
