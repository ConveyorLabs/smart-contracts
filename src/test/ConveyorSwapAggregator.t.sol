// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Swap.sol";
import "../ConveyorSwapAggregator.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function createSelectFork(string calldata, uint256)
        external
        returns (uint256);
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
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        conveyorSwapAggregator = new ConveyorSwapAggregator();
    }

    function testSwapUniv2SingleLP() public {
        // cheatCodes.createSelectFork("mainnet", 16000200);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(
            address(conveyorSwapAggregator),
            type(uint256).max
        );

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(this));

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

    function testSwapUniv2MultiLP() public {
        // cheatCodes.createSelectFork("mainnet", 16000233);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint256 amountIn = 825000000;
        address tokenOut = 0x2e85ae1C47602f7927bCabc2Ff99C40aA222aE15;
        uint256 amountOutMin = 4948702184313056519683340;
        address firstLP = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
        address secondLP = 0xdC1D67Bc953Bf67F007243c7DED42d67410a6De5;

        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(
            address(conveyorSwapAggregator),
            type(uint256).max
        );

        ConveyorSwapAggregator.Call[]
            memory calls = new ConveyorSwapAggregator.Call[](2);

        calls[0] = newUniV2Call(firstLP, 0, 680641423375285542, secondLP);
        calls[1] = newUniV2Call(
            secondLP,
            4948702184313056519683340,
            0,
            address(this)
        );

        ConveyorSwapAggregator.SwapAggregatorMulticall
            memory multicall = ConveyorSwapAggregator.SwapAggregatorMulticall(
                firstLP,
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
