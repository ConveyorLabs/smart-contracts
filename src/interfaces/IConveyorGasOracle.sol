// SPDX-License-Identifier: MIT
pragma solidity 0.8.16;

interface IConveyorGasOracle {
    function getGasPrice() external returns (uint256);
}
