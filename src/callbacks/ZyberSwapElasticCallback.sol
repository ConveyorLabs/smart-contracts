// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

contract ZyberSwapElasticCallback {
    ///@notice ZyberSwap Elastic callback function called during a swap on a v3 liqudity pool.
    ///@param deltaQty0 - The change in token0 reserves from the swap.
    ///@param deltaQty1 - The change in token1 reserves from the swap.
    ///@param data - The data packed into the swap.
    function swapCallback(int256 deltaQty0, int256 deltaQty1, bytes calldata data) external {
        assembly {
            // Start at fmp
            let freeMemoryPointer := mload(0x40)
            let token := calldataload(data.offset)
            mstore(freeMemoryPointer, 0xa9059cbb00000000000000000000000000000000000000000000000000000000)
            mstore(add(freeMemoryPointer, 4), and(caller(), 0xffffffffffffffffffffffffffffffffffffffff)) // Append and mask the "to" argument.
            switch slt(deltaQty0, 0)
            case 0 { mstore(add(freeMemoryPointer, 36), deltaQty0) }
            // Append the "amount" argument. Masking not required as it's a full 32 byte type.
            default { mstore(add(freeMemoryPointer, 36), deltaQty1) } // Append the "amount" argument. Masking not required as it's a full 32 byte type.

            if iszero(
                and(
                    or(and(eq(mload(0), 1), gt(returndatasize(), 31)), iszero(returndatasize())),
                    call(gas(), token, 0, freeMemoryPointer, 68, 0, 32)
                )
            ) {
                // Revert if the call failed.
                revert(0, 0)
            }
        }
    }
}
