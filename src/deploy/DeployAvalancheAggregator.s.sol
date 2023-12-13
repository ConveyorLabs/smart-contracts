// SPDX-License-Identifier: MIT
pragma solidity =0.8.21;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";
import {ICREATE3Factory} from "../../lib/create3-factory/src/ICREATE3Factory.sol";

contract Deploy is Script {
    ///@dev Avalanche Constructor Constants
    address constant WETH = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;

    function run() public returns (address conveyorRouterV1) {
        bytes32 salt = bytes32("0x8fbb158");
        bytes memory creationCode = abi.encodePacked(type(ConveyorRouterV1).creationCode, abi.encode(WETH));

        vm.startBroadcast();
        conveyorRouterV1 = ICREATE3Factory(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1).deploy(salt, creationCode);
        vm.stopBroadcast();
    }
}
