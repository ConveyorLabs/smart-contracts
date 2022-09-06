// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "../interfaces/IOrderBook.sol";
import "./utils/test.sol";
import "./utils/Console.sol";
import "../OrderBook.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

contract NewTestTest is DSTest {
    function setUp() public {}

    function testGetOrderById() public view {
        // IOrderBook(address(0x154b7A7B3F78d0434751a6c99eA26C59952abBE2))
        //     .getOrderById(
        //         stringToBytes32(
        //             "0x5c412b4b78477445d3286fbb5dcf9ef373234ad91d8aa24928509241dca00641"
        //         )
        //     );
    }

    function stringToBytes32(string memory source)
        public
        pure
        returns (bytes32 result)
    {
        bytes memory tempEmptyStringTest = bytes(source);
        if (tempEmptyStringTest.length == 0) {
            return 0x0;
        }

        assembly {
            result := mload(add(source, 32))
        }
    }
}
