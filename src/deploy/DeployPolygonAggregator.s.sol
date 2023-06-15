// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";
import {ICREATE3Factory} from "../../lib/create3-factory/src/ICREATE3Factory.sol";
import "../../test/utils/Console.sol";
import {ICREATE3Factory} from "../../lib/create3-factory/src/ICREATE3Factory.sol";

contract Deploy is Script {
    ///@dev Polygon Constructor Constants
    address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;

    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        bytes32 salt = bytes32("0xffffff");
        bytes memory creationCode = abi.encodePacked(
            type(ConveyorRouterV1).creationCode,
            abi.encode(WMATIC)
        );

        vm.startBroadcast();
        ICREATE3Factory(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1).deploy(
            salt,
            creationCode
        );
        vm.stopBroadcast();
    }
}
