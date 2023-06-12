// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Swap.sol";
import "../src/interfaces/IConveyorRouterV1.sol";
import "../src/lib/ConveyorTickMath.sol";
import "../lib/create3-factory/src/ICREATE3Factory.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function createSelectFork(
        string calldata,
        uint256
    ) external returns (uint256);

    function rollFork(uint256 forkId, uint256 blockNumber) external;

    function activeFork() external returns (uint256);

    function makePersistent(address) external;
}

contract ConveyorRouterV1Test is DSTest {
    IConveyorRouterV1 conveyorRouterV1;

    Swap swapHelper;
    CheatCodes cheatCodes;
    uint256 forkId;

    function setUp() public {
        cheatCodes = CheatCodes(HEVM_ADDRESS);

        address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
        address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

        swapHelper = new Swap(uniV2Addr, WETH);
        cheatCodes.deal(address(swapHelper), type(uint256).max);

        forkId = cheatCodes.activeFork();
        conveyorRouterV1 = IConveyorRouterV1(
            address(
                new ConveyorRouterV1(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)
            )
        );
        cheatCodes.makePersistent(address(conveyorRouterV1));
        cheatCodes.makePersistent(address(this));

        cheatCodes.makePersistent(
            address(0xba5BDe662c17e2aDFF1075610382B9B691296350)
        );

        cheatCodes.makePersistent(
            address(conveyorRouterV1.CONVEYOR_MULTICALL())
        );
        cheatCodes.makePersistent(address(swapHelper));
    }

    function testSwapUniv2SingleLP() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );

        conveyorRouterV1.swapExactTokenForToken(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall
        );
    }

    function testSwapUniv2SingleLPQuote() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );

        ConveyorRouterV1.ReferralInfo memory referralInfo;
        uint256 gasConsumed = conveyorRouterV1.quoteSwapExactTokenForToken(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall,
            referralInfo,
            false
        );
        console.log(gasConsumed);
    }

    function testSwapUniv2SingleLPWithReferral() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );

        uint256 referralFee = 1e16;
        uint256 protocolFee = 5e16;

        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo({referrer: address(this), referralFee: referralFee});

        conveyorRouterV1.swapExactTokenForTokenWithReferral{value: protocolFee}(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall,
            referralInfo
        );
    }

    function testSwapUniv2SingleLPWithReferralQuote() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        swapHelper.swapEthForTokenWithUniV2(10 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = ConveyorRouterV1.Call({target: lp, callData: new bytes(0)});

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );

        uint256 referralFee = 1e16;
        uint256 protocolFee = 5e16;

        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo({referrer: address(this), referralFee: referralFee});

        uint256 gasQuote = conveyorRouterV1.quoteSwapExactTokenForToken{
            value: protocolFee
        }(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall,
            referralInfo,
            true
        );

        console.log(gasQuote);
    }

    function testSwapExactEthForTokens() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint128 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                0, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );

        conveyorRouterV1.swapExactEthForToken{value: amountIn}(
            tokenOut,
            amountOutMin,
            uint128(0),
            multicall
        );
    }

    function testSwapExactEthForTokensQuote() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint128 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                0, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );

        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo({referrer: address(this), referralFee: 0});

        uint256 gasQuote = conveyorRouterV1.quoteSwapExactEthForToken{
            value: amountIn
        }(tokenOut, amountOutMin, uint128(0), multicall, referralInfo, false);

        console.log(gasQuote);
    }

    function testSwapExactEthForTokensWithReferral() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint128 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                0, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );
        uint128 protocolFee = 5e16;
        uint128 referralFee = 1e16;

        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo(address(this), referralFee);

        conveyorRouterV1.swapExactEthForTokenWithReferral{
            value: amountIn + protocolFee
        }(tokenOut, amountOutMin, protocolFee, multicall, referralInfo);
    }

    function testSwapExactEthForTokensWithReferralQuote() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        uint256 amountIn = 1900000000000000000000;
        address tokenOut = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint128 amountOutMin = 54776144172760093;
        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, amountOutMin, 0, address(this));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                0, //zeroForOne
                1, //univ2
                1, //msg.sender
                300,
                lp,
                calls
            );
        uint128 protocolFee = 5e16;
        uint128 referralFee = 1e16;

        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo(address(this), referralFee);

        uint256 gasQuote = conveyorRouterV1.quoteSwapExactEthForToken{
            value: amountIn + protocolFee
        }(tokenOut, amountOutMin, protocolFee, multicall, referralInfo, true);

        console.log(gasQuote);
    }

    function testSwapExactTokenForETH() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        uint256 amountOutMin = 54776144172760093;

        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
        uint256 balanceBefore = address(this).balance;
        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                0, //SwapAggregator
                300,
                lp,
                calls
            );

        conveyorRouterV1.swapExactTokenForEth(
            tokenIn,
            amountIn,
            amountOutMin,
            multicall
        );
        console.log("balance before", balanceBefore);
        console.log("balance after", address(this).balance);
    }

    function testSwapExactTokenForETHQuote() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        uint256 amountOutMin = 54776144172760093;

        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
        uint256 balanceBefore = address(this).balance;
        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                0, //SwapAggregator
                300,
                lp,
                calls
            );
        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo(address(this), 0);

        uint256 gasQuote = conveyorRouterV1.quoteSwapExactTokenForEth{
            value: 6e17
        }(tokenIn, amountIn, amountOutMin, multicall, referralInfo, false);
        console.log(gasQuote);
        console.log("balance before", balanceBefore);
        console.log("balance after", address(this).balance);
    }

    function testSwapExactTokenForETHWithReferral() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        uint256 amountOutMin = 54776144172760093;

        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
        uint256 balanceBefore = address(this).balance;
        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                0, //SwapAggregator
                300,
                lp,
                calls
            );

        uint128 protocolFee = 5e16;

        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo(address(this), 1e16);

        conveyorRouterV1.swapExactTokenForEthWithReferral{value: protocolFee}(
            tokenIn,
            amountIn,
            amountOutMin,
            multicall,
            referralInfo
        );
        console.log("balance before", balanceBefore);
        console.log("balance after", address(this).balance);
    }

    function testSwapExactTokenForETHWithReferralQuote() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0x34Be5b8C30eE4fDe069DC878989686aBE9884470;
        uint256 amountIn = 1900000000000000000000;
        uint256 amountOutMin = 54776144172760093;

        address lp = 0x9572e4C0c7834F39b5B8dFF95F211d79F92d7F23;
        uint256 balanceBefore = address(this).balance;
        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV2Call(lp, 0, amountOutMin, address(conveyorRouterV1));

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                1, //univ2
                0, //SwapAggregator
                300,
                lp,
                calls
            );

        uint128 protocolFee = 5e16;

        ConveyorRouterV1.ReferralInfo memory referralInfo = ConveyorRouterV1
            .ReferralInfo(address(this), 1e16);

        uint256 gasUsed = conveyorRouterV1.quoteSwapExactTokenForEth{
            value: protocolFee
        }(tokenIn, amountIn, amountOutMin, multicall, referralInfo, true);
        console.log(gasUsed);
        console.log("balance before", balanceBefore);
        console.log("balance after", address(this).balance);
    }

    function testRouterDeployment() public {
        ICREATE3Factory create3Factory = ICREATE3Factory(
            address(0x93FEC2C00BfE902F733B57c5a6CeeD7CD1384AE1)
        );
        address deployed = create3Factory.getDeployed(
            address(this),
            bytes32("0xc86ff6f")
        );
        console.log(deployed);
    }

    receive() external payable {}

    function testSwapUniv2MultiLP() public {
        cheatCodes.rollFork(forkId, 16749139);

        cheatCodes.deal(address(this), type(uint128).max);
        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint256 amountIn = 825000000;
        address tokenOut = 0x2e85ae1C47602f7927bCabc2Ff99C40aA222aE15;
        uint256 amountOutMin = 1335082888253395999149663;
        address firstLP = 0x397FF1542f962076d0BFE58eA045FfA2d347ACa0;
        address secondLP = 0xdC1D67Bc953Bf67F007243c7DED42d67410a6De5;

        swapHelper.swapEthForTokenWithUniV2(1 ether, tokenIn);
        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](2);

        calls[0] = ConveyorRouterV1.Call({
            target: firstLP,
            callData: new bytes(0)
        });

        calls[1] = ConveyorRouterV1.Call({
            target: secondLP,
            callData: new bytes(0)
        });

        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                3, //univ2
                7, //lp, msg.sender
                307500, //300, 300
                firstLP,
                calls
            );

        conveyorRouterV1.swapExactTokenForToken(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall
        );
    }

    function testSwapUniv3SingleLP() public {
        cheatCodes.deal(address(this), type(uint256).max);
        address tokenIn = 0xba5BDe662c17e2aDFF1075610382B9B691296350;
        uint256 amountIn = 5678000000000000000000;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint256 amountOutMin = 453245423220749265;
        address lp = 0x7685cD3ddD862b8745B1082A6aCB19E14EAA74F3;

        //Deposit weth to address(this)
        (bool depositSuccess, ) = address(tokenOut).call{
            value: 500000000 ether
        }(abi.encodeWithSignature("deposit()"));
        require(depositSuccess, "deposit failed");
        IUniswapV3Pool(lp).swap(
            address(this),
            false,
            500 ether,
            TickMath.MAX_SQRT_RATIO - 1,
            abi.encode(false, tokenOut, address(this))
        );

        IERC20(tokenIn).approve(address(conveyorRouterV1), type(uint256).max);

        ConveyorRouterV1.Call[] memory calls = new ConveyorRouterV1.Call[](1);

        calls[0] = newUniV3Call(
            lp,
            conveyorRouterV1.CONVEYOR_MULTICALL(),
            address(this),
            true,
            amountIn,
            tokenIn
        );
        console.log(IERC20(tokenIn).balanceOf(address(this)));

        forkId = cheatCodes.activeFork();
        cheatCodes.rollFork(forkId, 16749139);
        console.log(IERC20(tokenIn).balanceOf(address(this)));
        ConveyorRouterV1.SwapAggregatorMulticall
            memory multicall = ConveyorRouterV1.SwapAggregatorMulticall(
                1, //zeroForOne
                0,
                0,
                300,
                conveyorRouterV1.CONVEYOR_MULTICALL(),
                calls
            );

        conveyorRouterV1.swapExactTokenForToken(
            tokenIn,
            amountIn,
            tokenOut,
            amountOutMin,
            multicall
        );
    }

    function testWithdrawal() public {
        uint256 balanceBefore = address(this).balance;
        cheatCodes.deal(address(conveyorRouterV1), type(uint128).max);
        conveyorRouterV1.withdraw();
        assertGt(address(this).balance, balanceBefore);
    }

    function testFailWithdrawal_MsgSenderIsNotOwner() public {
        cheatCodes.deal(address(conveyorRouterV1), type(uint128).max);
        cheatCodes.prank(address(1));
        conveyorRouterV1.withdraw();
    }

    function uniswapV3SwapCallback(
        int256 amount0Delta,
        int256 amount1Delta,
        bytes memory data
    ) external {
        ///@notice Decode all of the swap data.
        (bool _zeroForOne, address tokenIn, address _sender) = abi.decode(
            data,
            (bool, address, address)
        );

        ///@notice Set amountIn to the amountInDelta depending on boolean zeroForOne.
        uint256 amountIn = _zeroForOne
            ? uint256(amount0Delta)
            : uint256(amount1Delta);

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
            _zeroForOne
                ? TickMath.MIN_SQRT_RATIO + 1
                : TickMath.MAX_SQRT_RATIO - 1,
            data
        );
        ///@notice Return the call
        return ConveyorRouterV1.Call({target: _lp, callData: callData});
    }

    ///@notice Helper function to create a single mock call for a v2 swap.
    function newUniV2Call(
        address _lp,
        uint256 amount0Out,
        uint256 amount1Out,
        address _receiver
    ) public pure returns (ConveyorRouterV1.Call memory) {
        bytes memory callData = abi.encodeWithSignature(
            "swap(uint256,uint256,address,bytes)",
            amount0Out,
            amount1Out,
            _receiver,
            new bytes(0)
        );
        return ConveyorRouterV1.Call({target: _lp, callData: callData});
    }
}