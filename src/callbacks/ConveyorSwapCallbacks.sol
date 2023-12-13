// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {ElkSwapCallback} from "./ElkSwapCallback.sol";
import {TraderJoeCallback} from "./TraderJoeCallback.sol";
import {PangolinSwapCallback} from "./PangolinSwapCallback.sol";
import {LydiaSwapCallback} from "./LydiaSwapCallback.sol";

contract ConveyorSwapCallbacks is
    UniswapV2Callback,
    UniswapV3Callback,
    ElkSwapCallback,
    TraderJoeCallback,
    PangolinSwapCallback,
    LydiaSwapCallback
{}
