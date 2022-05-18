// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;



import "../lib/libraries/ConveyorMath64x64.sol";




contract ABDKMathPrecision {
    function divide(int128 x, int128 y) public pure returns (int128 result) {
        result =ConveyorMath64x64.div(x, y);
    }

    function expon(int128 x) public pure returns (int128 result) {
        result =ConveyorMath64x64.exp(x);
    }

}