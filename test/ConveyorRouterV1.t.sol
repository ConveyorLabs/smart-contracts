// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.21;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Swap.sol";
import "../src/interfaces/IConveyorRouterV1.sol";
import "../src/lib/ConveyorTickMath.sol";
import "../lib/create3-factory/src/ICREATE3Factory.sol";
import {IConveyorMulticall} from "../src/ConveyorRouterV1.sol";
import "../lib/libraries/token/SafeERC20.sol";
import "../lib/interfaces/token/IERC20.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function createSelectFork(string calldata, uint256) external returns (uint256);

    function rollFork(uint256 forkId, uint256 blockNumber) external;

    function activeFork() external returns (uint256);

    function makePersistent(address) external;
}

contract ConveyorRouterV1Test is DSTest {
    using SafeERC20 for IERC20;

    IConveyorRouterV1 conveyorRouterV1;
    IConveyorMulticall conveyorMulticall;
    Swap swapHelper;
    CheatCodes vm;
    uint256 forkId;

    function setUp() public {
        vm = CheatCodes(HEVM_ADDRESS);

        address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        swapHelper = new Swap(uniV2Addr, WETH);
        vm.deal(address(swapHelper), type(uint256).max);

        forkId = vm.activeFork();

        //Set the owner to the test contract.
        conveyorRouterV1 = IConveyorRouterV1(address(new ConveyorRouterV1(WETH)));
        conveyorMulticall = IConveyorMulticall(conveyorRouterV1.CONVEYOR_MULTICALL());
        vm.prank(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38));
        //Setup the affiliate
        conveyorRouterV1.initializeAffiliate(address(this));
        conveyorRouterV1.initializeReferrer();
        vm.makePersistent(address(conveyorRouterV1));
        vm.makePersistent(address(this));

        vm.makePersistent(address(0xba5BDe662c17e2aDFF1075610382B9B691296350));

        vm.makePersistent(address(conveyorRouterV1.CONVEYOR_MULTICALL()));
        vm.makePersistent(address(swapHelper));
    }

    function testSplitRouteV2() public {
        vm.rollFork(forkId, 16749139);
        vm.deal(address(this), type(uint128).max);

        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //Input
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //Intermediary
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //Output

        //Split the input quantity 50/50 between the two pools.
        address sushiDaiUsdc = 0xAaF5110db6e744ff70fB339DE037B990A20bdace;
        address uniDaiUsdc = 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5;

        //Split the output quantity 50/50 between the two pools.
        address sushiUsdcWeth = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
        address uniUsdcWeth = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        uint256 amountIn = 2e20;
        //Get some DAI
        swapHelper.swapEthForTokenWithUniV2(100 ether, dai);
        //Approve the router to spend the DAI
        IERC20(dai).approve(address(conveyorRouterV1), type(uint256).max);

        //Setup the calls
        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](6);
        //Transfer 50% of the input quantity from the conveyorMulticall to sushiDaiUsdc
        calls[0] = newTransferCall(dai, sushiDaiUsdc, 1e20);
        //Transfer 50% of the input quantity from the conveyorMulticall to uniDaiUsdc
        calls[1] = newTransferCall(dai, uniDaiUsdc, 1e20);

        //Call 2,3 - Swap DAI for USDC on Sushi/Uni - Send tokens out to the the next pool
        calls[2] = newUniV2Call(sushiDaiUsdc, 0, 1000000, sushiUsdcWeth, new bytes(0));
        calls[3] = newUniV2Call(uniDaiUsdc, 0, 1000000, uniUsdcWeth, new bytes(0));

        //Call 4,5 - Swap USDC for WETH on Sushi/Uni - Send tokens out to the msg.sender
        calls[4] = newUniV2Call(sushiUsdcWeth, 0, 1, address(this), new bytes(0));
        calls[5] = newUniV2Call(uniUsdcWeth, 0, 1, address(this), new bytes(0));

        //Create the multicall
        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
            conveyorRouterV1.CONVEYOR_MULTICALL(), //Transfer the full input quantity to the multicall contract first
            calls
        );

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(dai, weth, uint112(amountIn), 1, 0, 0);

        //Execute the swap
        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testSplitRouteV2WithCallback() public {
        vm.rollFork(forkId, 16749139);
        vm.deal(address(this), type(uint128).max);
        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //Input
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //Intermediary
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //Output

        //Split the input quantity 50/50 between the two pools.
        address sushiDaiUsdc = 0xAaF5110db6e744ff70fB339DE037B990A20bdace;
        address uniDaiUsdc = 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5;

        //Split the output quantity 50/50 between the two pools.
        address sushiUsdcWeth = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
        address uniUsdcWeth = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        uint256 amountIn = 2e20;
        //Get some DAI
        swapHelper.swapEthForTokenWithUniV2(100 ether, dai);
        //Approve the router to spend the DAI
        IERC20(dai).approve(address(conveyorRouterV1), type(uint256).max);

        //Setup the calls
        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](5);
        // //Transfer 50% of the input quantity from the conveyorMulticall to sushiDaiUsdc
        // calls[0] = newTransferCall(dai, sushiDaiUsdc, 1e20);
        // //Transfer 50% of the input quantity from the conveyorMulticall to uniDaiUsdc
        // calls[1] = newTransferCall(dai, uniDaiUsdc, 1e20);
        bytes memory data_1 = abi.encode(dai, 300);
        //Call 2,3 - Swap DAI for USDC on Sushi/Uni - Send tokens out to the the next pool
        calls[0] = newUniV2Call(sushiDaiUsdc, 0, 1000000, conveyorRouterV1.CONVEYOR_MULTICALL(), data_1);
        calls[1] = newUniV2Call(uniDaiUsdc, 0, 1000000, conveyorRouterV1.CONVEYOR_MULTICALL(), data_1);
        bytes memory data_2 = abi.encode(usdc, 300);
        //Call 4,5 - Swap USDC for WETH on Sushi/Uni - Send tokens out to the msg.sender
        calls[2] = newUniV2Call(sushiUsdcWeth, 0, 1, conveyorRouterV1.CONVEYOR_MULTICALL(), data_2);
        calls[3] = newUniV2Call(uniUsdcWeth, 0, 1, conveyorRouterV1.CONVEYOR_MULTICALL(), data_2);

        calls[4] = newTransferCall(weth, address(this), 2);

        //Create the multicall
        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
            conveyorRouterV1.CONVEYOR_MULTICALL(), //Transfer the full input quantity to the multicall contract first
            calls
        );

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(dai, weth, uint112(amountIn), 1, 0, 0);

        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testUsdtV2Callback() public {
        vm.deal(address(this), type(uint128).max);
        address tether = 0xdAC17F958D2ee523a2206206994597C13D831ec7; //Input
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //Output

        //Split the input quantity 50/50 between the two pools.
        address tetherWethPool = 0x0d4a11d5EEaaC28EC3F61d100daF4d40471f1852;

        uint256 amountIn = 2e10; //20000 USDT
        //Get some DAI
        swapHelper.swapEthForTokenWithUniV2(100 ether, tether);
        //Approve the router to spend the DAI
        IERC20(tether).safeApprove(address(conveyorRouterV1), type(uint256).max);

        //Setup the calls
        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](2);

        bytes memory data_1 = abi.encode(tether, 300);
        //Call 2,3 - Swap DAI for USDC on Sushi/Uni - Send tokens out to the the next pool
        calls[0] = newUniV2Call(tetherWethPool, 10000000000000000000, 0, conveyorRouterV1.CONVEYOR_MULTICALL(), data_1);
        calls[1] = newTransferCall(weth, address(this), 10000000000000000000);
        //Create the multicall
        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
            conveyorRouterV1.CONVEYOR_MULTICALL(), //Transfer the full input quantity to the multicall contract first
            calls
        );

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(tether, weth, uint112(amountIn), 10000000000000000000, 0, 0);

        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testSplitRouteV2WithCallbackGeneric() public {
        vm.rollFork(forkId, 16749139);
        vm.deal(address(this), type(uint128).max);

        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //Input
        address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //Intermediary
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //Output

        //Split the input quantity 50/50 between the two pools.
        address sushiDaiUsdc = 0xAaF5110db6e744ff70fB339DE037B990A20bdace;
        address uniDaiUsdc = 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5;

        //Split the output quantity 50/50 between the two pools.
        address sushiUsdcWeth = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
        address uniUsdcWeth = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
        uint256 amountIn = 2e22;
        //Get some DAI
        swapHelper.swapEthForTokenWithUniV2(100 ether, dai);
        //Approve the router to spend the DAI
        IERC20(dai).approve(address(conveyorRouterV1), type(uint256).max);

        //Setup the calls
        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](7);
        // //Transfer 50% of the input quantity from the conveyorMulticall to sushiDaiUsdc
        calls[0] = newTransferCall(dai, sushiDaiUsdc, 1e22);
        // //Transfer 50% of the input quantity from the conveyorMulticall to uniDaiUsdc
        calls[1] = newTransferCall(dai, uniDaiUsdc, 1e22);
        //Call 2,3 - Swap DAI for USDC on Sushi/Uni - Send tokens out to the the next pool
        calls[2] = newUniV2Call(sushiDaiUsdc, 0, 1000000, sushiUsdcWeth, new bytes(0));
        calls[3] = newUniV2Call(uniDaiUsdc, 0, 1000000, uniUsdcWeth, new bytes(0));
        //Call 4,5 - Swap USDC for WETH on Sushi/Uni - Send tokens out to the msg.sender
        calls[4] = newUniV2Call(sushiUsdcWeth, 0, 10000, conveyorRouterV1.CONVEYOR_MULTICALL(), new bytes(0));
        calls[5] = newUniV2Call(uniUsdcWeth, 0, 10000, conveyorRouterV1.CONVEYOR_MULTICALL(), new bytes(0));

        calls[6] = newTransferCall(weth, address(this), 20000);

        //Create the multicall
        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
            conveyorRouterV1.CONVEYOR_MULTICALL(), //Transfer the full input quantity to the multicall contract first
            calls
        );

        conveyorRouterV1.initializeReferrer(); //Set the referrer at referrerNonce 0.

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(dai, weth, uint112(amountIn), 1, 1, 1); //referrer 1 since first index is used to set the referrer bool.

        //Execute the swap
        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testInitializeReferrer() public {
        vm.deal(address(this), type(uint128).max);
        vm.deal(address(1), type(uint128).max);
        vm.deal(address(2), type(uint128).max);
        vm.deal(address(3), type(uint128).max);
        vm.deal(address(4), type(uint128).max);
        vm.deal(address(5), type(uint128).max);
        vm.deal(address(6), type(uint128).max);
        vm.deal(address(7), type(uint128).max);
        vm.deal(address(8), type(uint128).max);
        vm.deal(address(9), type(uint128).max);
        vm.deal(address(10), type(uint128).max);
        vm.deal(address(11), type(uint128).max);
        vm.deal(address(12), type(uint128).max);
        vm.deal(address(13), type(uint128).max);
        vm.deal(address(14), type(uint128).max);
        vm.deal(address(15), type(uint128).max);
        vm.deal(address(16), type(uint128).max);
        vm.deal(address(17), type(uint128).max);
        vm.deal(address(18), type(uint128).max);
        vm.deal(address(19), type(uint128).max);
        vm.deal(address(20), type(uint128).max);
        vm.prank(address(this));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(1));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(2));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(3));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(4));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(5));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(6));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(7));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(8));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(9));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(10));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(11));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(12));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(13));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(14));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(15));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(16));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(17));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(18));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        vm.prank(address(19));
        conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
        // vm.prank(address(20));
        // conveyorRouterV1.initializeReferrer{value: type(uint128).max}();
    }

    function testSwapUniv2SingleLPOptimized() public {
        vm.rollFork(forkId, 16749139);

        vm.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(this), new bytes(0));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(lp, calls);

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(tokenIn, tokenOut, uint112(amountIn), 1, 0, 0);

        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testSwapUniv2SingleLPOptimizedQuote() public {
        vm.rollFork(forkId, 16749139);

        vm.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(this), new bytes(0));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(lp, calls);

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(tokenIn, tokenOut, uint112(amountIn), 1, 0, 0);

        uint256 gasConsumed = conveyorRouterV1.quoteSwapExactTokenForToken{value: 100 ether}(swapData, multicall);

        console.log(gasConsumed);
    }

    function testSwapExactEthForTokensOptimized() public {
        vm.rollFork(forkId, 16749139);

        vm.deal(address(this), type(uint128).max);
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint128 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(lp, calls);

        ConveyorRouterV1.EthToTokenSwapData memory swapData = ConveyorRouterV1.EthToTokenSwapData(tokenOut, 0, 1, 0, 0);

        conveyorRouterV1.swapExactEthForToken{value: amountIn}(swapData, multicall);
    }

    function testSwapExactEthForTokensOptimizedQuote() public {
        vm.rollFork(forkId, 16749139);

        vm.deal(address(this), type(uint128).max);
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint128 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(lp, calls);
        ConveyorRouterV1.EthToTokenSwapData memory swapData = ConveyorRouterV1.EthToTokenSwapData(tokenOut, 0, 1, 0, 0);
        uint256 gas = conveyorRouterV1.quoteSwapExactEthForToken{value: amountIn}(swapData, multicall);
        console.log(gas);
    }

    function testSwapExactTokenForETH() public {
        vm.rollFork(forkId, 16749139);

        vm.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        uint256 amountOutMin = 54776144172760093;

        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
        uint256 balanceBefore = address(this).balance;
        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(lp, calls);

        ConveyorRouterV1.TokenToEthSwapData memory swapData =
            ConveyorRouterV1.TokenToEthSwapData(tokenIn, uint112(amountIn), 1, 0, 0);

        conveyorRouterV1.swapExactTokenForEth(swapData, multicall);
        console.log("balance before", balanceBefore);
        console.log("balance after", address(this).balance);
    }

    function testSwapExactTokenForETHOptimizedQuote() public {
        vm.rollFork(forkId, 16749139);

        vm.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        uint256 amountOutMin = 54776144172760093;

        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(lp, calls);
        //Upgrade the multicall just to make sure it points to the right address.
        bytes memory bytecode = type(ConveyorMulticall).creationCode;
        bytes32 salt = bytes32("0x7fab158");
        vm.deal(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38), type(uint128).max);
        vm.prank(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38));
        conveyorRouterV1.upgradeMulticall(bytecode, salt);
        ConveyorRouterV1.TokenToEthSwapData memory swapData =
            ConveyorRouterV1.TokenToEthSwapData(tokenIn, uint112(amountIn), 1, 0, 0);

        uint256 gas = conveyorRouterV1.quoteSwapExactTokenForEth(swapData, multicall);
        console.log("gas", gas);
    }

    receive() external payable {}

    function testSwapUniv3SingleLP_ZeroForOneTrue() public {
        vm.deal(address(this), type(uint256).max);
        console.log(address(this));
        address tokenIn = 0xba5BDe662c17e2aDFF1075610382B9B691296350;
        uint256 amountIn = 5678000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 453245423220749265;
        address lp = 0x7685cD3ddD862b8745B1082A6aCB19E14EAA74F3;

        //Deposit weth to address(this)
        (bool depositSuccess,) = address(tokenOut).call{value: 500000000 ether}(abi.encodeWithSignature("deposit()"));
        require(depositSuccess, "deposit failed");
        IUniswapV3Pool(lp).swap(
            address(this), false, 500 ether, TickMath.MAX_SQRT_RATIO - 1, abi.encode(false, tokenOut, address(this))
        );

        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);
        bytes memory bytecode = type(ConveyorMulticall).creationCode;
        bytes32 salt = bytes32("0x7fab158");
        vm.prank(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38));
        conveyorRouterV1.upgradeMulticall(bytecode, salt);
        calls[0] = newUniV3Call(lp, conveyorRouterV1.CONVEYOR_MULTICALL(), address(this), true, amountIn, tokenIn);
        console.log(IERC20(tokenIn).balanceOf(address(this)));

        forkId = vm.activeFork();
        vm.rollFork(forkId, 16749139);
        console.log(IERC20(tokenIn).balanceOf(address(this)));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall =
            ConveyorRouterV1.SwapAggregatorMulticall(conveyorRouterV1.CONVEYOR_MULTICALL(), calls);

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(tokenIn, tokenOut, uint112(amountIn), uint112(amountOutMin), 0, 0);
        vm.prank(address(this));
        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testSwapUniv3SingleLP_ZeroForOneFalse() public {
        vm.deal(address(this), type(uint256).max);
        address tokenOut = 0xba5BDe662c17e2aDFF1075610382B9B691296350;
        uint256 amountIn = 5678000000000000000000;
        address tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 453245423220749265;
        address lp = 0x7685cD3ddD862b8745B1082A6aCB19E14EAA74F3;

        //Deposit weth to address(this)
        (bool depositSuccess,) = address(tokenIn).call{value: 500000000 ether}(abi.encodeWithSignature("deposit()"));
        require(depositSuccess, "deposit failed");

        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV3Call(lp, conveyorRouterV1.CONVEYOR_MULTICALL(), address(this), false, amountIn, tokenIn);
        console.log(IERC20(tokenIn).balanceOf(address(this)));

        forkId = vm.activeFork();
        vm.rollFork(forkId, 16749139);
        console.log(IERC20(tokenIn).balanceOf(address(this)));

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall =
            ConveyorRouterV1.SwapAggregatorMulticall(conveyorRouterV1.CONVEYOR_MULTICALL(), calls);

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(tokenIn, tokenOut, uint112(amountIn), uint112(amountOutMin), 0, 0);
        vm.prank(address(this));
        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testSwapUniv3SingleLPTether() public {
        vm.deal(address(this), type(uint256).max);
        address tokenIn = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        uint256 amountIn = 2e11;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 1000000000000000000;
        address lp = 0x11b815efB8f581194ae79006d24E0d814B7697F6;
        //Deposit weth to address(this)
        (bool depositSuccess,) = address(tokenOut).call{value: 500000000 ether}(abi.encodeWithSignature("deposit()"));
        require(depositSuccess, "deposit failed");
        IUniswapV3Pool(lp).swap(
            address(this), true, 500 ether, TickMath.MIN_SQRT_RATIO + 1, abi.encode(true, tokenOut, address(this))
        );

        IERC20(tokenIn).safeApprove(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV3Call(lp, conveyorRouterV1.CONVEYOR_MULTICALL(), address(this), false, amountIn, tokenIn);

        forkId = vm.activeFork();
        vm.rollFork(forkId, 16749139);

        ConveyorRouterV1.SwapAggregatorMulticall memory multicall =
            ConveyorRouterV1.SwapAggregatorMulticall(conveyorRouterV1.CONVEYOR_MULTICALL(), calls);

        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(tokenIn, tokenOut, uint112(amountIn), uint112(amountOutMin), 0, 0);
        vm.prank(address(this));
        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    function testWithdrawal() public {
        uint256 balanceBefore = address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38).balance;
        vm.deal(address(conveyorRouterV1), type(uint128).max);
        vm.prank(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38));
        conveyorRouterV1.withdraw();
        assertGt(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38).balance, balanceBefore);
    }

    function testFailWithdrawal_MsgSenderIsNotOwner() public {
        vm.deal(address(conveyorRouterV1), type(uint128).max);
        vm.prank(address(1));
        conveyorRouterV1.withdraw();
    }

    function testRouterDeployment() public view {
        ICREATE3Factory create3Factory = ICREATE3Factory(address(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1));
        bytes32 salt = bytes32("0x7fab158");
        address deployed = create3Factory.getDeployed(address(0x2f37bC8900EB1176C689c63c5E781B96DCC0C48E), salt);

        console.log(deployed);
    }

    function testUpgradeMulticall() public {
        bytes memory bytecode = type(ConveyorMulticall).creationCode;
        console.logBytes(bytecode);
        bytes32 salt = bytes32("0x7fab158");
        vm.deal(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38), type(uint128).max);
        vm.prank(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38));
        address upgradedMulticall = conveyorRouterV1.upgradeMulticall(bytecode, salt);

        console.log(upgradedMulticall);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory data) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address tokenIn, address _sender) = abi.decode(data, (bool, address, address));

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(tokenIn).safeTransferFrom(_sender, msg.sender, amountIn);
        } else {
            IERC20(tokenIn).safeTransfer(msg.sender, amountIn);
        }
    }

    ///@notice Helper function to create a single mock call for a v3 swap.
    function newUniV3Call(
        address _lp,
        address _sender,
        address _receiver,
        bool _zeroForOne,
        uint256 _amountIn,
        address _tokenIn
    ) public pure returns (ConveyorRouterV1.Call memory) {
        ///@notice Pack the required data for the call.
        bytes memory data = abi.encode(_tokenIn);
        ///@notice Encode the callData for the call.
        bytes memory callData = abi.encodeWithSignature(
            "swap(address,bool,int256,uint160,bytes)",
            _receiver,
            _zeroForOne,
            int256(_amountIn),
            _zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
            data
        );
        ///@notice Return the call
        return ConveyorRouterV1.Call({target: _lp, callData: callData});
    }

    ///@notice Helper function to create a single mock call for a v2 swap.
    function newUniV2Call(address _lp, uint256 amount0Out, uint256 amount1Out, address _receiver, bytes memory _data)
        public
        pure
        returns (ConveyorRouterV1.Call memory)
    {
        bytes memory callData =
            abi.encodeWithSignature("swap(uint256,uint256,address,bytes)", amount0Out, amount1Out, _receiver, _data);
        return ConveyorRouterV1.Call({target: _lp, callData: callData});
    }

    function newTransferCall(address _token, address _receiver, uint256 _amount)
        public
        pure
        returns (ConveyorRouterV1.Call memory)
    {
        bytes memory callData = abi.encodeWithSignature("transfer(address,uint256)", _receiver, _amount);
        return ConveyorRouterV1.Call({target: _token, callData: callData});
    }
}
