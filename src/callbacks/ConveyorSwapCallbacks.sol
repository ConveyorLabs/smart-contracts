// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import {ElkSwapCallback} from "./ElkSwapCallback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {KyberSwapV3Callback} from "./KyberSwapV3Callback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {VelodromeCallback} from "./VeloDromeCallback.sol";

contract ConveyorSwapCallbacks is
    ElkSwapCallback,
    UniswapV3Callback,
    KyberSwapV3Callback,
    UniswapV2Callback,
    VelodromeCallback
{}
