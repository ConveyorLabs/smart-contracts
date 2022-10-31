// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "./interfaces/ILimitOrderQuoter.sol";
import "./interfaces/ILimitOrderExecutor.sol";

/// @title LimitOrderRouter
/// @author LeytonTaylor, 0xKitsune, Conveyor Labs
/// @notice Limit Order contract to execute existing limit orders within the OrderBook contract.
contract SandboxRouter {

    address immutable LIMIT_ORDER_EXECUTOR;

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
    constructor(address _limitOrderExecutor) {
        LIMIT_ORDER_EXECUTOR=_limitOrderExecutor;
    }

    ///@notice Function to execute multiple OrderGroups
    function executeMultipleGroups(MultiCall calldata calls) public {
        bytes memory data = abi.encode(calls);
        ///@notice Upon initialization call the LimitOrderExecutor to transfer the tokens to the contract. 
        (bool succeeded, )=address(LIMIT_ORDER_EXECUTOR).call(abi.encodeWithSignature("executeMultiCallOrders(Multicall)", data));
        require(succeeded);
        
    }

    function executeMultiCallCallback(bytes memory data) external onlyLimitOrderExecutor {
        (MultiCall memory calls) = abi.decode(data,(MultiCall));
        
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
