// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;
import "./ConveyorRouterV1.sol";
import "./ConveyorErrors.sol";
contract GenericMulticall {
    function executeGenericMulticall(ConveyorRouterV1.SwapAggregatorGenericMulticall calldata multicall) external {
        for (uint256 i = 0; i < multicall.calls.length; i++) {
            (bool success, ) = multicall.calls[i].target.call(multicall.calls[i].callData);
            if (!success) {
                revert CallFailed();
            }
        }
    }
}