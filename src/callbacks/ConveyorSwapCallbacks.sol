// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {AlgebraCallback} from "./AlgebraCallback.sol";
import {PancakeV2Callback} from "./PancakeV2Callback.sol";
import {PancakeV3Callback} from "./PancakeV3Callback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {BiswapCallback} from "./BiswapCallback.sol";
import {BabySwapCallback} from "./BabySwapCallback.sol";
import {TraderJoeCallback} from "./TraderJoeCallback.sol";
import {MdexSwapCallback} from "./MdexSwapCallback.sol";
import {BabyDogeCallback} from "./BabyDogeCallback.sol";
import {NomiswapCallback} from "./NomiswapCallback.sol";
import {CafeSwapCallback} from "./CafeSwapCallback.sol";

contract ConveyorSwapCallbacks is
    AlgebraCallback,
    PancakeV2Callback,
    PancakeV3Callback,
    UniswapV2Callback,
    UniswapV3Callback,
    BiswapCallback,
    BabySwapCallback,
    TraderJoeCallback,
    MdexSwapCallback,
    BabyDogeCallback,
    NomiswapCallback,
    CafeSwapCallback
{}
