// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.16;

import "./utils/test.sol";
import "./utils/Console.sol";
import "./utils/Utils.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Router02.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
import "../../lib/interfaces/token/IERC20.sol";
import "./utils/Swap.sol";
import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "./utils/ScriptRunner.sol";
import "../lib/ConveyorTickMath.sol";
import "../../lib/interfaces/uniswap-v3/IQuoter.sol";
import "../SwapRouter.sol";

interface CheatCodes {
    function prank(address) external;

    function deal(address who, uint256 amount) external;

    function expectEmit(
        bool,
        bool,
        bool,
        bool
    ) external;
}

contract ConveyorTickMathTest is DSTest {
    ConveyorTickMathWrapper conveyorTickMath;
    LimitOrderExecutorWrapper limitOrderExecutor;

    IQuoter iQuoter;
    ScriptRunner scriptRunner;

    Swap swapHelper;
    Swap swapHelperUniV2;

    address uniV2Addr = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

    //Initialize cheatcodes
    CheatCodes cheatCodes;

    //Test Token Address's
    address WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address LINK = 0x218532a12a389a4a92fC0C5Fb22901D1c19198aA;
    address UNI = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
    address USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address TAXED_TOKEN = 0xE7eaec9Bca79d537539C00C58Ae93117fB7280b9; //
    address TAXED_TOKEN_1 = 0xe0a189C975e4928222978A74517442239a0b86ff; //
    address TAXED_TOKEN_2 = 0xd99793A840cB0606456916d1CF5eA199ED93Bf97; //6% tax CHAOS token 27
    address TAXED_TOKEN_3 = 0xcFEB09C3c5F0f78aD72166D55f9e6E9A60e96eEC;

    //MAX_UINT for testing
    uint256 constant MAX_UINT = 2**256 - 1;

    uint32 constant MAX_U32 = 2**32 - 1;

    //Factory and router address's
    address _sushiSwapRouterAddress =
        0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F;
    address _uniV2FactoryAddress = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    // address _sushiFactoryAddress = 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac;
    address _uniV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;

    //Chainlink ERC20 address
    address swapToken = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
    // bytes32 _sushiHexDem =
    //     hex"e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303";
    bytes32 _uniswapV2HexDem =
        hex"96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f";

    //Initialize array of Dex specifications
    bytes32[] _hexDems = [
        _uniswapV2HexDem,
        // _sushiHexDem,
        _uniswapV2HexDem
    ];
    address[] _dexFactories = [
        _uniV2FactoryAddress,
        // _sushiFactoryAddress,
        _uniV3FactoryAddress
    ];
    bool[] _isUniV2 = [
        true,
        //  true,
        false
    ];

    uint256 alphaXDivergenceThreshold = 3402823669209385000000000000000000; //0.00001
    address swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address aggregatorV3Address = 0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C;

    function setUp() public {
        scriptRunner = new ScriptRunner();
        cheatCodes = CheatCodes(HEVM_ADDRESS);
        swapHelper = new Swap(_sushiSwapRouterAddress, WETH);
        swapHelperUniV2 = new Swap(uniV2Addr, WETH);
        conveyorTickMath = new ConveyorTickMathWrapper();
        iQuoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
        limitOrderExecutor = new LimitOrderExecutorWrapper(
            _hexDems,
            _dexFactories,
            _isUniV2
        );
    }

    function testsimulateAmountOutOnSqrtPriceX96__ZeroForOneTrue(uint64 _alphaX)
        public
    {
        bool run = true;
        if (_alphaX == 0) {
            run = false;
        }

        if (run) {
            address poolAddress = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            address tokenIn = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress)
                .slot0();
            int24 tickSpacing = IUniswapV3Pool(poolAddress).tickSpacing();
            address token0 = IUniswapV3Pool(poolAddress).token0();

            uint128 liquidity = IUniswapV3Pool(poolAddress).liquidity();
            uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity,
                _alphaX,
                true
            );
            uint256 amountOut = iQuoter.quoteExactInputSingle(
                tokenIn,
                WETH,
                3000,
                _alphaX,
                sqrtPriceLimitX96
            );

            uint256 amountOutMin = uint256(
                -conveyorTickMath._simulateAmountOutOnSqrtPriceX96(
                    token0,
                    tokenIn,
                    poolAddress,
                    _alphaX,
                    tickSpacing,
                    liquidity,
                    3000
                )
            );

            assertEq(amountOutMin, amountOut);
        }
    }

    function testsimulateAmountOutOnSqrtPriceX96__ZeroForOneFalse(
        uint64 _alphaX
    ) public {
        bool run = true;
        if (_alphaX == 0) {
            run = false;
        }

        if (run) {
            address poolAddress = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;
            address tokenOut = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

            (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress)
                .slot0();
            int24 tickSpacing = IUniswapV3Pool(poolAddress).tickSpacing();
            address token0 = IUniswapV3Pool(poolAddress).token0();
            uint128 liquidity = IUniswapV3Pool(poolAddress).liquidity();
            uint160 sqrtPriceLimitX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                sqrtPriceX96,
                liquidity,
                _alphaX,
                false
            );
            uint256 amountOutMin = uint256(
                -conveyorTickMath._simulateAmountOutOnSqrtPriceX96(
                    token0,
                    WETH,
                    poolAddress,
                    _alphaX,
                    tickSpacing,
                    liquidity,
                    3000
                )
            );

            uint256 amountOut = iQuoter.quoteExactInputSingle(
                WETH,
                tokenOut,
                3000,
                _alphaX,
                sqrtPriceLimitX96
            );

            

            assertEq(amountOut, amountOutMin);
        }
    }

    function testsimulateAmountOutOnSqrtPriceX96CrossTick() public {
        uint256 _alphaX = 10000000000000000000;

        (uint160 sqrtPriceX96, int24 tickBefore, , , , , ) = IUniswapV3Pool(
            0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8
        ).slot0();

        int24 tickSpacing = IUniswapV3Pool(
            0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8
        ).tickSpacing();
        address token0 = IUniswapV3Pool(
            0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8
        ).token0();
        uint128 liquidity = IUniswapV3Pool(
            0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8
        ).liquidity();
        

        uint256 amountOutMin = uint256(
            -conveyorTickMath._simulateAmountOutOnSqrtPriceX96(
                token0,
                WETH,
                0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8,
                _alphaX,
                tickSpacing,
                liquidity,
                3000
            )
        );

        //get the token in
        cheatCodes.deal(address(this), 500000000000 ether);

        address(WETH).call{value: 500000000000 ether}(
            abi.encodeWithSignature("deposit()")
        );

        IERC20(WETH).transfer(address(limitOrderExecutor), _alphaX);

        //Perform the swap on the pool to recalculate if the current tick has been crossed
        uint256 amountReceived = limitOrderExecutor.swapV3(
            0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8,
            WETH,
            0x6B175474E89094C44Da98b954EedeAC495271d0F,
            3000,
            _alphaX,
            amountOutMin,
            address(this),
            address(limitOrderExecutor)
        );

        (, int24 tickAfter, , , , , ) = IUniswapV3Pool(
            0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8
        ).slot0();

        assertGt(tickAfter, tickBefore);
        assertEq(amountReceived, amountOutMin);
      
    }
    //Block: 15233771
    function testFromSqrtX96() public {
        address poolAddress = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;
        address tokenIn = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address tokenOut = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        
        //USDC spot price
        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(poolAddress)
                .slot0();

        uint256 priceUSDC=conveyorTickMath._fromSqrtX96(sqrtPriceX96, true, tokenIn, tokenOut);
        uint256 priceWETH=conveyorTickMath._fromSqrtX96(sqrtPriceX96, false, tokenIn, tokenOut);
        console.log(priceWETH);
        assertEq(194786572365129798010721349067079679, priceUSDC);
        assertEq(594456218574771757927683806232862281426471, priceWETH);
        
    }

    receive() external payable {}
}

contract ConveyorTickMathWrapper is ConveyorTickMath {
    function _fromSqrtX96(
        uint160 sqrtPriceX96,
        bool token0IsReserve0,
        address token0,
        address token1
    ) public view returns (uint256 priceX128) {
        return fromSqrtX96(sqrtPriceX96, token0IsReserve0, token0, token1);
    }

    function _simulateAmountOutOnSqrtPriceX96(
        address token0,
        address tokenIn,
        address lpAddressAToWeth,
        uint256 amountIn,
        int24 tickSpacing,
        uint128 liquidity,
        uint24 fee
    ) public returns (int256 amountOut) {
        return
            simulateAmountOutOnSqrtPriceX96(
                token0,
                tokenIn,
                lpAddressAToWeth,
                amountIn,
                tickSpacing,
                liquidity,
                fee
            );
    }
}

contract LimitOrderExecutorWrapper is SwapRouter {
    constructor(
        bytes32[] memory _initBytecodes,
        address[] memory _dexFactories,
        bool[] memory _isUniV2
    ) SwapRouter(_initBytecodes, _dexFactories, _isUniV2) {}

    function swapV3(
        address _lp,
        address _tokenIn,
        address _tokenOut,
        uint24 _fee,
        uint256 _amountIn,
        uint256 _amountOutMin,
        address _reciever,
        address _sender
    ) public returns (uint256) {
        return
            _swapV3(
                _lp,
                _tokenIn,
                _tokenOut,
                _fee,
                _amountIn,
                _amountOutMin,
                _reciever,
                _sender
            );
    }
}
