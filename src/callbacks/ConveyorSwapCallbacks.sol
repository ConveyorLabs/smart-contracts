// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {ElkSwapCallback} from "./ElkSwapCallback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {KyberSwapV3Callback} from "./KyberSwapV3Callback.sol";
import {VelodromeCallback} from "./VelodromeCallback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";

contract ConveyorSwapCallbacks is
    ElkSwapCallback,
    UniswapV3Callback,
    KyberSwapV3Callback,
    VelodromeCallback,
    UniswapV2Callback
{}
