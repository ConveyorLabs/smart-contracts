// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import {PancakeV2Callback} from "./PancakeV2Callback.sol";
import {PancakeV3Callback} from "./PancakeV3Callback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {ApeSwapCallback} from "./ApeSwapCallback.sol";
import {AlgebraCallback} from "./AlgebraCallback.sol";

contract ConveyorSwapCallbacks is
    PancakeV2Callback,
    PancakeV3Callback,
    UniswapV2Callback,
    UniswapV3Callback,
    ApeSwapCallback,
    AlgebraCallback
{}
