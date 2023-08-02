// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import {AlgebraCallback} from "./AlgebraCallback.sol";
import {ConvergenceXCallback} from "./ConvergenceXCallback.sol";
import {DXSwapCallback} from "./DXSwapCallback.sol";
import {ElkSwapCallback} from "./ElkSwapCallback.sol";
import {JetSwapCallback} from "./JetSwapCallback.sol";
import {LinkSwapCallback} from "./LinkSwapCallback.sol";
import {MeerkatCallback} from "./MeerkatCallback.sol";
import {PancakeV2Callback} from "./PancakeV2Callback.sol";
import {PancakeV3Callback} from "./PancakeV3Callback.sol";
import {SakeSwapCallback} from "./SakeSwapCallback.sol";
import {UniFiCallback} from "./UniFiCallback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {VerseCallback} from "./VerseCallback.sol";
import {WaultSwapCallback} from "./WaultSwapCallback.sol";

contract ConveyorSwapCallbacks is
    AlgebraCallback,
    ConvergenceXCallback,
    DXSwapCallback,
    ElkSwapCallback,
    JetSwapCallback,
    LinkSwapCallback,
    MeerkatCallback,
    PancakeV2Callback,
    PancakeV3Callback,
    SakeSwapCallback,
    UniFiCallback,
    UniswapV2Callback,
    UniswapV3Callback,
    VerseCallback,
    WaultSwapCallback
{}
