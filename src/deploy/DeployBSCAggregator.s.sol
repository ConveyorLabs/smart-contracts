// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";
import {ICREATE3Factory} from "../../lib/create3-factory/src/ICREATE3Factory.sol";
import "../../test/utils/Console.sol";
import {ICREATE3Factory} from "../../lib/create3-factory/src/ICREATE3Factory.sol";

contract Deploy is Script {
    ///@dev Polygon Constructor Constants
    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    function run() public returns (address conveyorRouterV1) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        bytes32 salt = bytes32("0x8fbb158");
        bytes memory creationCode =
            abi.encodePacked(type(ConveyorRouterV1).creationCode, abi.encode(WBNB));

        vm.startBroadcast(deployerPrivateKey);
        conveyorRouterV1 = ICREATE3Factory(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1).deploy(salt, creationCode);
        vm.stopBroadcast();
    }
}
