// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.21;

import {AlgebraCallback} from "./AlgebraCallback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {ApeSwapCallback} from "./ApeSwapCallback.sol";
import {MeerkatCallback} from "./MeerkatCallback.sol";
import {KyberSwapV3Callback} from "./KyberSwapV3Callback.sol";
import {WaultSwapCallback} from "./WaultSwapCallback.sol";
import {JetSwapCallback} from "./JetSwapCallback.sol";
import {ElkSwapCallback} from "./ElkSwapCallback.sol";
import {DystopiaCallback} from "./DystopiaCallback.sol";
import {UniFiCallback} from "./UniFiCallback.sol";
import {VerseCallback} from "./VerseCallback.sol";

contract ConveyorSwapCallbacks is
    AlgebraCallback,
    ApeSwapCallback,
    UniswapV2Callback,
    UniswapV3Callback,
    MeerkatCallback,
    KyberSwapV3Callback,
    WaultSwapCallback,
    JetSwapCallback,
    ElkSwapCallback,
    DystopiaCallback,
    UniFiCallback
{}