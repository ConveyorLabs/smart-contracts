// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";

/// @title SandboxRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract SandboxRouter {

    address immutable LIMIT_ORDER_EXECUTOR;
    address immutable LIMIT_ORDER_ROUTER;

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
    constructor(address _limitOrderExecutor, address _limitOrderRouter) {
        LIMIT_ORDER_EXECUTOR=_limitOrderExecutor;
        LIMIT_ORDER_ROUTER=_limitOrderRouter;
    }

    ///@notice Function to execute multiple OrderGroups
    ///@param calls The calldata to be executed by the contract.
    function executeMulticall(MultiCall calldata calls) external {
        bool success;
        ///@notice Upon initialization call the LimitOrderExecutor to transfer the tokens to the contract. 
        bytes memory bytesSig = abi.encodeWithSignature("initializeMulticallCallbackState(MultiCall)", calls);
        address limitOrderRouter= LIMIT_ORDER_ROUTER;
        
        assembly {
            mstore(
                0x00,
                bytesSig
            )

            success := call(
                gas(), // gas remaining
                limitOrderRouter, // destination address
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
