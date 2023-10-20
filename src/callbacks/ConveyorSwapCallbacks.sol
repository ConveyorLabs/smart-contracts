// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {AlgebraCallback} from "./AlgebraCallback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {ConvergenceXCallback} from "./ConvergenceXCallback.sol";
import {UniFiCallback} from "./UniFiCallback.sol";
import {VerseCallback} from "./VerseCallback.sol";
import {ApeSwapCallback} from "./ApeSwapCallback.sol";
import {LinkSwapCallback} from "./LinkSwapCallback.sol";
import {SakeSwapCallback} from "./SakeSwapCallback.sol";
import {DefiSwapCallback} from "./DefiSwapCallback.sol";
import {KyberSwapV3Callback} from "./KyberSwapV3Callback.sol";
import {AlgebraCallback} from "./AlgebraCallback.sol";

contract ConveyorSwapCallbacks is
    UniswapV3Callback,
    AlgebraCallback,
    TraderJoeCallback,
    UniswapV2Callback,
    UniswapV3Callback,
    ConvergenceXCallback,
    UniFiCallback,
    VerseCallback,
    ApeSwapCallback,
    LinkSwapCallback,
    SakeSwapCallback,
    DefiSwapCallback,
    KyberSwapV3Callback,
    AlgebraCallback
{}