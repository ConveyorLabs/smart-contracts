// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "../../lib/forge-std/src/Script.sol";
import {ConveyorRouterV1} from "../ConveyorRouterV1.sol";
import {ICREATE3Factory} from "../../lib/create3-factory/src/ICREATE3Factory.sol";
import "../../test/utils/Console.sol";
import {ICREATE3Factory} from "../../lib/create3-factory/src/ICREATE3Factory.sol";

contract Deploy is Script {
    ///@dev GOERLI Constructor Constants
    address constant GOERLI_WETH = 0xdD69DB25F6D620A7baD3023c5d32761D353D3De9;

    function run() public {
        // uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        bytes32 salt = bytes32("0x3rlk7N6qpQ");
        bytes memory creationCode = abi.encodePacked(
            type(ConveyorRouterV1).creationCode,
            abi.encode(GOERLI_WETH)
        );

        vm.startBroadcast();
        ICREATE3Factory(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1).deploy(
            salt,
            creationCode
        );
        vm.stopBroadcast();
    }
}
