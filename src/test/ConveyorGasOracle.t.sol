// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../ConveyorGasOracle.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;

    function warp(uint256) external;

    function rollFork(uint256) external;

    function rollFork(uint256 forkId, uint256 blockNumber) external;

    function activeFork() external returns (uint256);

    function createFork(string calldata) external returns (uint256);

    function makePersistent(address) external;

    function createSelectFork(string calldata, uint256)
        external
        returns (uint256);
}

contract ConveyorGasOracleTest is DSTest {
    ConveyorGasOracle gasOracle;
    //Initialize cheatcodes
    CheatCodes cheatCodes;
    uint256 forkId;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        ///@notice This is the fast gas oracle address for Ethereum Mainnet

        forkId = cheatCodes.createSelectFork(
            "https://mainnet.infura.io/v3/5eb79c68c5a3401f94685c5661b621e2",
            15233771
        );
        address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;
        gasOracle = new ConveyorGasOracle(aggregatorV3Address);
        cheatCodes.makePersistent(address(gasOracle));
    }

    function testGetPrice() public {
        cheatCodes.rollFork(forkId, 15333771);

        uint256 gasPrice = gasOracle.getGasPrice();
        cheatCodes.rollFork(forkId, 15433771);

        uint256 gasPrice2 = gasOracle.getGasPrice();
        cheatCodes.rollFork(forkId, 15533771);

        uint256 gasPrice3 = gasOracle.getGasPrice();
        cheatCodes.rollFork(forkId, 15633771);

        uint256 gasPrice4 = gasOracle.getGasPrice();
        cheatCodes.rollFork(forkId, 15733771);

        console.log(gasPrice, gasPrice2, gasPrice3, gasPrice4);
    }
}
