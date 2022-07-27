pragma solidity >=0.8.14;

import "./Uniswap/FullMath.sol";
import "./Uniswap/LowGasSafeMath.sol";
import './Uniswap/SafeCast.sol';

library ConveyorTickMath {
    
    /// @notice maximum uint128 64.64 fixed point number
    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    function fromX96(uint160 x) internal pure returns (uint128){
        unchecked {
            require(uint128(x>>32)<= MAX_64x64);
            return uint128(x>>32);
        }
    }
}