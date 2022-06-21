// SPDX-License-Identifier: MIT
pragma solidity >=0.8.13;

interface IAlphaX {

    function alphaX(uint128 reserve0Snapshot, uint128 reserve1Snapshot, uint128 reserve0Execution, uint128 reserve1Execution) external returns (uint256);
}