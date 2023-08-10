// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {AlgebraCallback} from "./AlgebraCallback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {TraderJoeCallback} from "./TraderJoeCallback.sol";
import {ZyberSwapElasticCallback} from "./ZyberSwapElasticCallback.sol";
import {ZyberSwapCallback} from "./ZyberSwapCallback.sol";
import {ArbDexCallback} from "./ArbDexCallback.sol";
import {ArbSwapCallback} from "./ArbSwapCallback.sol";

contract ConveyorSwapCallbacks is
    UniswapV3Callback,
    AlgebraCallback,
    TraderJoeCallback,
    UniswapV2Callback,
    ZyberSwapElasticCallback,
    ZyberSwapCallback,
    ArbDexCallback,
    ArbSwapCallback
{}
