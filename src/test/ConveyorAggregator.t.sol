// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Swap.sol";
import "../ConveyorSwapAggregator.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;
}

contract ConveyorSwapAggregatorTest is DSTest {
    ConveyorSwapAggregator conveyorSwapAggregator;

    Swap swapHelper;
    CheatCodes cheatCodes;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        swapHelper = new Swap(uniV2Addr, WETH);

        conveyorSwapAggregator = new ConveyorSwapAggregator();
    }

    function testSwap() public {
        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 1;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(
            address(conveyorSwapAggregator),
            type(uint256).max
        );

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](1);

        calls[0] = newUniV2Call(lp, 0, 54776144172760093, address(this));

        ConveyorSwapAggregator.SwapAggregatorMulticall
            memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
                lp,
                calls
            );

        conveyorSwapAggregator.swap(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall
        );
    }

    ///@notice Helper function to create a single mock call for a v2 swap.
    function newUniV2Call(
        address _lp,
        uint256 amount0Out,
        uint256 amount1Out,
        address _receiver
    ) public pure returns (ConveyorSwapAggregator.Call memory) {
        bytes memory callData = abi.encodeWithSignature(
            "swap(uint256,uint256,address,bytes)",
            amount0Out,
            amount1Out,
            _receiver,
            new bytes(0)
        );
        return ConveyorSwapAggregator.Call({target: _lp, callData: callData});
    }
}
