// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "../../lib/interfaces/token/IERC20.sol";

contract ZyberSwapElasticCallback {
    ///@notice ZyberSwap Elastic callback function called during a swap on a v3 liqudity pool.
    ///@param deltaQty0 - The change in token0 reserves from the swap.
    ///@param deltaQty1 - The change in token1 reserves from the swap.
    ///@param data - The data packed into the swap.
    function swapCallback(int256 deltaQty0, int256 deltaQty1, bytes calldata data) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address _tokenIn, address _sender) = abi.decode(data, (bool, address, address));

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne ? uint256(deltaQty0) : uint256(deltaQty1);

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(_tokenIn).transferFrom(_sender, msg.sender, amountIn);
        } else {
            IERC20(_tokenIn).transfer(msg.sender, amountIn);
        }
    }
}
