// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Swap.sol";
import "../src/interfaces/IConveyorRouterV1.sol";
import "../src/lib/ConveyorTickMath.sol";
import "../lib/create3-factory/src/ICREATE3Factory.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function createSelectFork(string calldata, uint256) external returns (uint256);

    function rollFork(uint256 forkId, uint256 blockNumber) external;

    function activeFork() external returns (uint256);

    function makePersistent(address) external;
}

contract ConveyorRouterV1Test is DSTest {
    IConveyorRouterV1 conveyorRouterV1;
    ConveyorMulticallWrapper conveyorMulticallWrapper;
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

        uint128 REFERRAL_INITIALIZATION_FEE = 18446744073709550;
        //Set the owner to the test contract.
        conveyorRouterV1 = IConveyorRouterV1(address(new ConveyorRouterV1(WETH, REFERRAL_INITIALIZATION_FEE)));

        conveyorMulticallWrapper = new ConveyorMulticallWrapper(
            address(conveyorRouterV1)
        );
        vm.prank(address(0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38));
        //Setup the affiliate
        conveyorRouterV1.initializeAffiliate(address(this));
        vm.makePersistent(address(conveyorMulticallWrapper));
        vm.makePersistent(address(conveyorRouterV1));
        vm.makePersistent(address(this));

        vm.makePersistent(address(0xba5BDe662c17e2aDFF1075610382B9B691296350));

        vm.makePersistent(address(conveyorRouterV1.CONVEYOR_MULTICALL()));
        vm.makePersistent(address(swapHelper));
    }

    // function testSplitRouteV2() public {
    //     vm.rollFork(forkId, 16749139);
    //     vm.deal(address(this), type(uint128).max);

    //     address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F; //Input
    //     address usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; //Intermediary
    //     address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; //Output

    //     //Split the input quantity 50/50 between the two pools.
    //     address sushiDaiUsdc = 0xAaF5110db6e744ff70fB339DE037B990A20bdace;
    //     address uniDaiUsdc = 0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5;

    //     //Split the output quantity 50/50 between the two pools.
    //     address sushiUsdcWeth = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
    //     address uniUsdcWeth = 0xB4e16d0168e52d35CaCD2c6185b44281Ec28C9Dc;
    //     uint256 amountIn = 2e20;
    //     //Get some DAI
    //     swapHelper.swapEthForTokenWithUniV2(100 ether, dai);
    //     //Approve the router to spend the DAI
    //     IERC20(dai).approve(address(conveyorRouterV1), type(uint256).max);

    //     //Setup the calls
    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](6);
    //     //Transfer 50% of the input quantity from the conveyorMulticall to sushiDaiUsdc
    //     calls[0] = newTransferCall(dai, sushiDaiUsdc, 1e20);
    //     //Transfer 50% of the input quantity from the conveyorMulticall to uniDaiUsdc
    //     calls[1] = newTransferCall(dai, uniDaiUsdc, 1e20);

    //     //Call 2,3 - Swap DAI for USDC on Sushi/Uni - Send tokens out to the the next pool
    //     calls[2] = newUniV2Call(sushiDaiUsdc, 0, 1000000, sushiUsdcWeth, new bytes(0));
    //     calls[3] = newUniV2Call(uniDaiUsdc, 0, 1000000, uniUsdcWeth, new bytes(0));

    //     //Call 4,5 - Swap USDC for WETH on Sushi/Uni - Send tokens out to the msg.sender
    //     calls[4] = newUniV2Call(sushiUsdcWeth, 0, 1, address(this), new bytes(0));
    //     calls[5] = newUniV2Call(uniUsdcWeth, 0, 1, address(this), new bytes(0));

    //     //Generate the callTypeBitmap - Notice we preconstructed the v2 swap calldata our callType will be generic for all calls.
    //     uint40 callTypeBitmap = 0x2; //Call 0 is Generic
    //     callTypeBitmap += 0x2 << 2; //Call 1 is Generic
    //     callTypeBitmap += 0x2 << 4; //Call 2 is Generic
    //     callTypeBitmap += 0x2 << 6; //Call 3 is Generic
    //     callTypeBitmap += 0x2 << 8; //Call 4 is Generic
    //     callTypeBitmap += 0x2 << 10; //Call 5 is Generic
    //     //Create the multicall
    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         0, //Irrelevant for generic calls
    //         callTypeBitmap, //callTypeBitmap
    //         1, //Irrelevant for generic calls
    //         0, //Irrelevant for generic calls
    //         conveyorRouterV1.CONVEYOR_MULTICALL(), //Transfer the full input quantity to the multicall contract first
    //         calls
    //     );

    //     //Execute the swap
    //     conveyorRouterV1.swapExactTokenForToken(
    //         dai,
    //         amountIn,
    //         weth,
    //         1, //Amount out min of 1 wei
    //         multicall
    //     );
    // }

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
        bytes memory data_1 = abi.encode(true, dai, 300);
        //Call 2,3 - Swap DAI for USDC on Sushi/Uni - Send tokens out to the the next pool
        calls[0] = newUniV2Call(sushiDaiUsdc, 0, 1000000, conveyorRouterV1.CONVEYOR_MULTICALL(), data_1);
        calls[1] = newUniV2Call(uniDaiUsdc, 0, 1000000, conveyorRouterV1.CONVEYOR_MULTICALL(), data_1);
        bytes memory data_2 = abi.encode(true, usdc, 300);
        //Call 4,5 - Swap USDC for WETH on Sushi/Uni - Send tokens out to the msg.sender
        calls[2] = newUniV2Call(sushiUsdcWeth, 0, 1, conveyorRouterV1.CONVEYOR_MULTICALL(), data_2);
        calls[3] = newUniV2Call(uniUsdcWeth, 0, 1, conveyorRouterV1.CONVEYOR_MULTICALL(), data_2);

        calls[4] = newTransferCall(weth, address(this), 2);

      
        //Create the multicall
        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
            conveyorRouterV1.CONVEYOR_MULTICALL(), //Transfer the full input quantity to the multicall contract first
            calls
        );

        ConveyorRouterV1.TokenToTokenSwapData memory swapData = ConveyorRouterV1.TokenToTokenSwapData(
            dai,
            weth,
            uint112(amountIn),
            1,
            0,
            0
        );

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
        uint256 amountIn = 2e20;
        //Get some DAI
        swapHelper.swapEthForTokenWithUniV2(100 ether, dai);
        //Approve the router to spend the DAI
        IERC20(dai).approve(address(conveyorRouterV1), type(uint256).max);

        //Setup the calls
        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](7);
        // //Transfer 50% of the input quantity from the conveyorMulticall to sushiDaiUsdc
        calls[0] = newTransferCall(dai, sushiDaiUsdc, 1e20);
        // //Transfer 50% of the input quantity from the conveyorMulticall to uniDaiUsdc
        calls[1] = newTransferCall(dai, uniDaiUsdc, 1e20);
        //Call 2,3 - Swap DAI for USDC on Sushi/Uni - Send tokens out to the the next pool
        calls[2] = newUniV2Call(sushiDaiUsdc, 0, 1000000, sushiUsdcWeth, new bytes(0));
        calls[3] = newUniV2Call(uniDaiUsdc, 0, 1000000, uniUsdcWeth, new bytes(0));
        //Call 4,5 - Swap USDC for WETH on Sushi/Uni - Send tokens out to the msg.sender
        calls[4] = newUniV2Call(sushiUsdcWeth, 0, 1, conveyorRouterV1.CONVEYOR_MULTICALL(), new bytes(0));
        calls[5] = newUniV2Call(uniUsdcWeth, 0, 1, conveyorRouterV1.CONVEYOR_MULTICALL(), new bytes(0));

        calls[6] = newTransferCall(weth, address(this), 2);

        //Create the multicall
        ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1
            .SwapAggregatorMulticall(
            conveyorRouterV1.CONVEYOR_MULTICALL(), //Transfer the full input quantity to the multicall contract first
            calls
        );

        conveyorRouterV1.initializeReferrer(); //Set the referrer at referrerNonce 0.
        ConveyorRouterV1.TokenToTokenSwapData memory swapData =
            ConveyorRouterV1.TokenToTokenSwapData(dai, weth, uint112(amountIn), 1, 1, 1); //referrer 1 since first index is used to set the referrer bool.

        //Execute the swap
        conveyorRouterV1.swapExactTokenForToken(swapData, multicall);
    }

    // function testDeriveCallTypeFromBitmap() public {
    //     uint40 bitmap = 0x0;
    //     bitmap += 0x1 << 2;
    //     bitmap += 0x2 << 4;
    //     uint256 callType0 = conveyorMulticallWrapper.deriveCallFromBitmapWrapper(bitmap, 0);
    //     uint256 callType1 = conveyorMulticallWrapper.deriveCallFromBitmapWrapper(bitmap, 1);
    //     uint256 callType2 = conveyorMulticallWrapper.deriveCallFromBitmapWrapper(bitmap, 2);

    //     assertEq(callType0, 0x0);
    //     assertEq(callType1, 0x1);
    //     assertEq(callType2, 0x2);
    // }

    // function testSwapUniv2SingleLP() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );

    //     conveyorRouterV1.swapExactTokenForToken(tokenIn, amountIn, tokenOut, amountOutMin, multicall);
    // }

    // function testSwapUniv2SingleLPOptimized() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorGenericMulticall memory multicall =
    //         ConveyorRouterV1.SwapAggregatorGenericMulticall(lp, calls);

    //     conveyorRouterV1.swapExactTokenForTokenOptimized(tokenIn, amountIn, tokenOut, amountOutMin, multicall);
    // }

    // function testSwapUniv2SingleLPOptimizedQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorGenericMulticall memory multicall =
    //         ConveyorRouterV1.SwapAggregatorGenericMulticall(lp, calls);

    //     uint256 gasConsumed = conveyorRouterV1.quoteSwapExactTokenForTokenOptimized{value: 100 ether}(
    //         tokenIn, amountIn, tokenOut, amountOutMin, multicall
    //     );

    //     console.log(gasConsumed);
    // }

    // function testSwapUniv2SingleLPQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );

    //     ConveyorRouterV1.ReferralInfo memory referralInfo;
    //     uint256 gasConsumed = conveyorRouterV1.quoteSwapExactTokenForToken(
    //         tokenIn, amountIn, tokenOut, amountOutMin, multicall, referralInfo, false
    //     );
    //     console.log(gasConsumed);
    // }

    // function testSwapUniv2SingleLPWithReferral() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );

    //     uint256 referralFee = 1e16;
    //     uint256 protocolFee = 5e16;

    //     ConveyorRouterV1.ReferralInfo memory referralInfo =
    //         ConveyorRouterV1.ReferralInfo({referrer: address(this), referralFee: referralFee});

    //     conveyorRouterV1.swapExactTokenForTokenWithReferral{value: protocolFee}(
    //         tokenIn, amountIn, tokenOut, amountOutMin, multicall, referralInfo
    //     );
    // }

    // function testSwapUniv2SingleLPWithReferralQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );

    //     uint256 referralFee = 1e16;
    //     uint256 protocolFee = 5e16;

    //     ConveyorRouterV1.ReferralInfo memory referralInfo =
    //         ConveyorRouterV1.ReferralInfo({referrer: address(this), referralFee: referralFee});

    //     uint256 gasQuote = conveyorRouterV1.quoteSwapExactTokenForToken{value: protocolFee}(
    //         tokenIn, amountIn, tokenOut, amountOutMin, multicall, referralInfo, true
    //     );

    //     console.log(gasQuote);
    // }

    // function testSwapExactEthForTokens() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint128 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         0, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );

    //     conveyorRouterV1.swapExactEthForToken{value: amountIn}(tokenOut, amountOutMin, uint128(0), multicall);
    // }

    // function testSwapExactEthForTokensOptimized() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint128 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorGenericMulticall memory multicall =
    //         ConveyorRouterV1.SwapAggregatorGenericMulticall(lp, calls);

    //     conveyorRouterV1.swapExactEthForTokenOptimized{value: amountIn}(tokenOut, amountOutMin, uint128(0), multicall);
    // }

    // function testSwapExactEthForTokensOptimizedQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint128 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorGenericMulticall memory multicall =
    //         ConveyorRouterV1.SwapAggregatorGenericMulticall(lp, calls);

    //     uint256 gas = conveyorRouterV1.quoteSwapExactEthForTokenOptimized{value: amountIn}(
    //         tokenOut, amountOutMin, uint128(0), multicall
    //     );
    //     console.log(gas);
    // }

    // function testSwapExactEthForTokensQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint128 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         0, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );

    //     ConveyorRouterV1.ReferralInfo memory referralInfo =
    //         ConveyorRouterV1.ReferralInfo({referrer: address(this), referralFee: 0});

    //     uint256 gasQuote = conveyorRouterV1.quoteSwapExactEthForToken{value: amountIn}(
    //         tokenOut, amountOutMin, uint128(0), multicall, referralInfo, false
    //     );

    //     console.log(gasQuote);
    // }

    // function testSwapExactEthForTokensWithReferral() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint128 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         0, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );
    //     uint128 protocolFee = 5e16;
    //     uint128 referralFee = 1e16;

    //     ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1.ReferralInfo(address(this), referralFee);

    //     conveyorRouterV1.swapExactEthForTokenWithReferral{value: amountIn + protocolFee}(
    //         tokenOut, amountOutMin, protocolFee, multicall, referralInfo
    //     );
    // }

    // function testSwapExactEthForTokensWithReferralQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     uint256 amountIn = 1900000000000000000000;
    //     address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint128 amountOutMin = 54776144172760093;
    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         0, //zeroForOne
    //         0, //univ2
    //         1, //msg.sender
    //         300,
    //         lp,
    //         calls
    //     );
    //     uint128 protocolFee = 5e16;
    //     uint128 referralFee = 1e16;

    //     ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1.ReferralInfo(address(this), referralFee);

    //     uint256 gasQuote = conveyorRouterV1.quoteSwapExactEthForToken{value: amountIn + protocolFee}(
    //         tokenOut, amountOutMin, protocolFee, multicall, referralInfo, true
    //     );

    //     console.log(gasQuote);
    // }

    // function testSwapExactTokenForETH() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     uint256 amountOutMin = 54776144172760093;

    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
    //     uint256 balanceBefore = address(this).balance;
    //     swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         0, //SwapAggregator
    //         300,
    //         lp,
    //         calls
    //     );

    //     conveyorRouterV1.swapExactTokenForEth(tokenIn, amountIn, amountOutMin, multicall);
    //     console.log("balance before", balanceBefore);
    //     console.log("balance after", address(this).balance);
    // }

    // function testSwapExactTokenForETHOptimized() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     uint256 amountOutMin = 54776144172760093;

    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
    //     uint256 balanceBefore = address(this).balance;
    //     swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorGenericMulticall memory multicall =
    //         ConveyorRouterV1.SwapAggregatorGenericMulticall(lp, calls);

    //     conveyorRouterV1.swapExactTokenForEthOptimized(tokenIn, amountIn, amountOutMin, multicall);
    //     console.log("balance before", balanceBefore);
    //     console.log("balance after", address(this).balance);
    // }

    // function testSwapExactTokenForETHOptimizedQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     uint256 amountOutMin = 54776144172760093;

    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
    //     swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorGenericMulticall memory multicall =
    //         ConveyorRouterV1.SwapAggregatorGenericMulticall(lp, calls);

    //     uint256 gas = conveyorRouterV1.quoteSwapExactTokenForEthOptimized(tokenIn, amountIn, amountOutMin, multicall);
    //     console.log("gas", gas);
    // }

    // function testSwapExactTokenForETHQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     uint256 amountOutMin = 54776144172760093;

    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
    //     uint256 balanceBefore = address(this).balance;
    //     swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         0, //SwapAggregator
    //         300,
    //         lp,
    //         calls
    //     );
    //     ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1.ReferralInfo(address(this), 0);

    //     uint256 gasQuote = conveyorRouterV1.quoteSwapExactTokenForEth{value: 6e17}(
    //         tokenIn, amountIn, amountOutMin, multicall, referralInfo, false
    //     );
    //     console.log(gasQuote);
    //     console.log("balance before", balanceBefore);
    //     console.log("balance after", address(this).balance);
    // }

    // function testSwapExactTokenForETHWithReferral() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     uint256 amountOutMin = 54776144172760093;

    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
    //     uint256 balanceBefore = address(this).balance;
    //     swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         0, //SwapAggregator
    //         300,
    //         lp,
    //         calls
    //     );

    //     uint128 protocolFee = 5e16;

    //     ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1.ReferralInfo(address(this), 1e16);

    //     conveyorRouterV1.swapExactTokenForEthWithReferral{value: protocolFee}(
    //         tokenIn, amountIn, amountOutMin, multicall, referralInfo
    //     );
    //     console.log("balance before", balanceBefore);
    //     console.log("balance after", address(this).balance);
    // }

    // function testSwapExactTokenForETHWithReferralQuote() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
    //     uint256 amountIn = 1900000000000000000000;
    //     uint256 amountOutMin = 54776144172760093;

    //     address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
    //     uint256 balanceBefore = address(this).balance;
    //     swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1), new bytes(0));

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         0, //SwapAggregator
    //         300,
    //         lp,
    //         calls
    //     );

    //     uint128 protocolFee = 5e16;

    //     ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1.ReferralInfo(address(this), 1e16);

    //     uint256 gasUsed = conveyorRouterV1.quoteSwapExactTokenForEth{value: protocolFee}(
    //         tokenIn, amountIn, amountOutMin, multicall, referralInfo, true
    //     );
    //     console.log(gasUsed);
    //     console.log("balance before", balanceBefore);
    //     console.log("balance after", address(this).balance);
    // }

    // function testRouterDeployment() public view {
    //     ICREATE3Factory create3Factory = ICREATE3Factory(address(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1));
    //     bytes32 salt = bytes32("0x7fab158");
    //     address deployed = create3Factory.getDeployed(address(0x2f37bC8900EB1176C689c63c5E781B96DCC0C48E), salt);
    //     bytes memory initCode = type(ConveyorRouterV1).creationCode;
    //     bytes32 initHash = keccak256(abi.encode(initCode));
    //     console.logBytes32(initHash);
    //     console.logBytes(abi.encode(0xdD69DB25F6D620A7baD3023c5d32761D353D3De9));
    //     console.log(deployed);
    // }

    receive() external payable {}

    // function testSwapUniv2MultiLP() public {
    //     vm.rollFork(forkId, 16749139);

    //     vm.deal(address(this), type(uint128).max);
    //     address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    //     uint256 amountIn = 825000000;
    //     address tokenOut = 0x2e85ae1C47602f7927bCabc2Ff99C40aA222aE15;
    //     uint256 amountOutMin = 1335082888253395999149663;
    //     address firstLP = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
    //     address secondLP = 0xdC1D67Bc953Bf67F007243c7DED42d67410a6De5;

    //     swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](2);

    //     calls[0] = ConveyorRouterV1.Call({target: firstLP, callData: new bytes(0)});

    //     calls[1] = ConveyorRouterV1.Call({target: secondLP, callData: new bytes(0)});

    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         0, //univ2
    //         7, //lp, msg.sender
    //         307500, //300, 300
    //         firstLP,
    //         calls
    //     );

    //     conveyorRouterV1.swapExactTokenForToken(tokenIn, amountIn, tokenOut, amountOutMin, multicall);
    // }

    // function testSwapUniv3SingleLP() public {
    //     vm.deal(address(this), type(uint256).max);
    //     address tokenIn = 0xba5BDe662c17e2aDFF1075610382B9B691296350;
    //     uint256 amountIn = 5678000000000000000000;
    //     address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    //     uint256 amountOutMin = 453245423220749265;
    //     address lp = 0x7685cD3ddD862b8745B1082A6aCB19E14EAA74F3;

    //     //Deposit weth to address(this)
    //     (bool depositSuccess,) = address(tokenOut).call{value: 500000000 ether}(abi.encodeWithSignature("deposit()"));
    //     require(depositSuccess, "deposit failed");
    //     IUniswapV3Pool(lp).swap(
    //         address(this), false, 500 ether, TickMath.MAX_SQRT_RATIO - 1, abi.encode(false, tokenOut, address(this))
    //     );

    //     IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

    //     ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

    //     calls[0] = newUniV3Call(lp, conveyorRouterV1.CONVEYOR_MULTICALL(), address(this), true, amountIn, tokenIn);
    //     console.log(IERC20(tokenIn).balanceOf(address(this)));

    //     forkId = vm.activeFork();
    //     vm.rollFork(forkId, 16749139);
    //     console.log(IERC20(tokenIn).balanceOf(address(this)));
    //     ConveyorRouterV1.SwapAggregatorMulticall memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
    //         1, //zeroForOne
    //         1,
    //         0,
    //         300,
    //         conveyorRouterV1.CONVEYOR_MULTICALL(),
    //         calls
    //     );

    //     conveyorRouterV1.swapExactTokenForToken(tokenIn, amountIn, tokenOut, amountOutMin, multicall);
    // }

    /// TODO: Prank address(this) to be tx.origin for this test
    // function testWithdrawal() public {
    //     uint256 balanceBefore = address(this).balance;
    //     vm.deal(address(conveyorRouterV1), type(uint128).max);
    //     conveyorRouterV1.withdraw();
    //     assertGt(address(this).balance, balanceBefore);
    // }

    function testFailWithdrawal_MsgSenderIsNotOwner() public {
        vm.deal(address(conveyorRouterV1), type(uint128).max);
        vm.prank(address(1));
        conveyorRouterV1.withdraw();
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes memory data) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address tokenIn, address _sender) = abi.decode(data, (bool, address, address));

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);

        if (!(_sender == address(this))) {
            ///@notice Transfer the amountIn of tokenIn to the liquidity pool from the sender.
            IERC20(tokenIn).transferFrom(_sender, msg.sender, amountIn);
        } else {
            IERC20(tokenIn).transfer(msg.sender, amountIn);
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
        bytes memory data = abi.encode(_zeroForOne, _tokenIn, _sender);
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

contract ConveyorMulticallWrapper is ConveyorMulticall {
    constructor(address _conveyor) ConveyorMulticall(_conveyor) {}
}
