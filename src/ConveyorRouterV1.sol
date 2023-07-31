// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "../lib/interfaces/token/IERC20.sol";
import "./ConveyorErrors.sol";
import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
import "../lib/libraries/token/SafeERC20.sol";
import "./lib/ConveyorMath.sol";
import {UniswapV3Callback} from "./UniswapV3Callback.sol";
import {UniswapV2Callback} from "./UniswapV2Callback.sol";

interface IConveyorMulticall {
    function executeGenericMulticall(ConveyorRouterV1.SwapAggregatorGenericMulticall calldata genericMulticall)
        external;
}

/// @title ConveyorRouterV1
/// @author 0xKitsune, 0xOsiris, Conveyor Labs
/// @notice Multicall contract for token Swaps.
contract ConveyorRouterV1 {
    using SafeERC20 for IERC20;
    using ConveyorMath for *;

    address public CONVEYOR_MULTICALL;
    address public immutable WETH;

    address owner;
    address tempOwner;

    uint128 internal constant AFFILIATE_PERCENT = 1844674407370955200;

    /**
     * @notice Event that is emitted when a token to token swap has filled successfully.
     *
     */
    event Swap(
        address indexed tokenIn, uint256 amountIn, address indexed tokenOut, uint256 amountOut, address indexed receiver
    );

    /**
     * @notice Event that is emitted when a token to ETH swap has filled successfully.
     *
     */
    event SwapExactTokenForEth(address indexed tokenIn, uint256 amountIn, uint256 amountOut, address indexed receiver);

    /**
     * @notice Event that is emitted when a ETH to token swap has filled successfully.
     *
     */
    event SwapExactEthForToken(uint256 amountIn, address indexed tokenOut, uint256 amountOut, address indexed receiver);

    /**
     * @notice Event that is emitted when a referral token swap has filled successfully
     *
     */
    event Referral(address indexed referrer, address indexed receiver, uint256 referralFee);

    /**
     * @notice Event that is emitted when ETH is withdrawn from the contract
     *
     */
    event Withdraw(address indexed receiver, uint256 amount);

    ///@notice Modifier function to only allow the owner of the contract to call specific functions
    ///@dev Functions with onlyOwner: withdraw
    modifier onlyOwner() {
        if (msg.sender != owner) {
            revert MsgSenderIsNotOwner();
        }

        _;
    }
    ///@notice Mapping from uint16 to affiliate address.

    mapping(uint16 => address) public affiliates;
    ///@notice Mapping from uint16 to referrer address.
    mapping(uint16 => address) public referrers;

    ///@notice Current Nonce for affiliate addresses.
    uint16 public affiliateNonce;
    ///@notice Current Nonce for referrer addresses.
    uint16 public referrerNonce;

    struct SwapData {
        uint120 amountIn;
        uint120 amountOutMin;
        uint16 affiliate;
    }

    struct ReferralSwapData {
        uint112 amountIn;
        uint112 amountOutMin;
        uint16 affiliate;
        uint16 referrer;
    }

    struct EthToTokenSwapData {
        uint120 amountOutMin;
        uint120 protocolFee;
        uint16 affiliate;
    }

    struct ReferralEthToTokenSwapData {
        uint112 amountOutMin;
        uint112 protocolFee;
        uint16 affiliate;
        uint16 referrer;
    }

    ///@dev Deploys the ConveyorSwapExecutor contract.
    ///@param _weth Address of Wrapped Native Asset.
    constructor(address _weth) {
        require(_weth != address(0), "WETH address is zero");
        CONVEYOR_MULTICALL = address(new ConveyorMulticall(address(this)));
        WETH = _weth;
        owner = tx.origin;
    }

    /// @notice Gas optimized Multicall struct
    struct SwapAggregatorGenericMulticall {
        address tokenInDestination;
        Call[] calls;
    }

    /// @notice Call struct for token Swaps.
    /// @param target Address to call.
    /// @param callData Data to call.
    struct Call {
        address target;
        bytes callData;
    }

    /// @notice Swap tokens for tokens.
    /// @param tokenIn Address of token to swap.
    /// @param tokenOut Address of token to receive.
    /// @param swapData The swap data for the transaction.
    /// @param genericMulticall Multicall to be executed.
    function swapExactTokenForToken(
        address tokenIn,
        address tokenOut,
        SwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata genericMulticall
    ) public payable {
        ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
        IERC20(tokenIn).transferFrom(msg.sender, genericMulticall.tokenInDestination, swapData.amountIn);

        ///@notice Get tokenOut balance of msg.sender.
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(msg.sender);
        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = balanceBefore + swapData.amountOutMin;

        ///@notice Execute Multicall.
        IConveyorMulticall(CONVEYOR_MULTICALL).executeGenericMulticall(genericMulticall);

        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Check if tokenOut balance of msg.sender is sufficient.
        if (balanceAfter < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(tokenOutAmountRequired - balanceAfter, swapData.amountOutMin);
        }

        address affiliate = affiliates[swapData.affiliate];

        _safeTransferETH(affiliate, ConveyorMath.mul64U(AFFILIATE_PERCENT, msg.value));

        ///@notice Emit Swap event.
        emit Swap(tokenIn, swapData.amountIn, tokenOut, balanceAfter - balanceBefore, msg.sender);
    }

    /// @notice Swap tokens for tokens with referral.
    function swapExactTokenForTokenViaReferral(
        address tokenIn,
        address tokenOut,
        ReferralSwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata genericMulticall
    ) external payable {
        ///TODO:
    }

    /// @notice Swap ETH for tokens.
    /// @param tokenOut Address of token to receive.
    /// @param swapData The swap data for the transaction.
    /// @param swapAggregatorMulticall Multicall to be executed.
    function swapExactEthForToken(
        address tokenOut,
        EthToTokenSwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) public payable {
        if (swapData.protocolFee > msg.value) {
            revert InsufficientMsgValue();
        }

        ///@notice Cache the amountIn to save gas.
        uint256 amountIn = msg.value - swapData.protocolFee;

        ///@notice Deposit the msg.value-protocolFee into WETH.
        _depositEth(amountIn, WETH);

        ///@notice Transfer WETH from WETH to tokenInDestination address.
        IERC20(WETH).transfer(swapAggregatorMulticall.tokenInDestination, amountIn);

        ///@notice Get tokenOut balance of msg.sender.
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Calculate tokenOut amount required.
        uint256 tokenOutAmountRequired = balanceBefore + swapData.amountOutMin;

        ///@notice Execute Multicall.
        IConveyorMulticall(CONVEYOR_MULTICALL).executeGenericMulticall(swapAggregatorMulticall);

        ///@notice Get tokenOut balance of msg.sender after multicall execution.
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(msg.sender);

        ///@notice Revert if tokenOut balance of msg.sender is insufficient.
        if (balanceAfter < tokenOutAmountRequired) {
            revert InsufficientOutputAmount(tokenOutAmountRequired - balanceAfter, swapData.amountOutMin);
        }
        address affiliate = affiliates[swapData.affiliate];

        _safeTransferETH(affiliate, ConveyorMath.mul64U(AFFILIATE_PERCENT, swapData.protocolFee));

        ///@notice Emit SwapExactEthForToken event.
        emit SwapExactEthForToken(msg.value, tokenOut, balanceAfter - balanceBefore, msg.sender);
    }

    /// @notice Swap ETH for tokens with referral.
    function swapExactEthForTokenViaReferral(
        address tokenOut,
        ReferralEthToTokenSwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable {
        ///TODO:
    }

    /// @notice Swap tokens for ETH.
    /// @param tokenIn Address of token to swap.
    /// @param swapData The swap data for the transaction.
    /// @param swapAggregatorMulticall Multicall to be executed.
    function swapExactTokenForEth(
        address tokenIn,
        SwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) public payable {
        ///@dev Ignore if the tokenInDestination is address(0).
        if (swapAggregatorMulticall.tokenInDestination != address(0)) {
            ///@notice Transfer tokenIn from msg.sender to tokenInDestination address.
            IERC20(tokenIn).transferFrom(msg.sender, swapAggregatorMulticall.tokenInDestination, swapData.amountIn);
        }
        ///@notice Get ETH balance of msg.sender.
        uint256 balanceBefore = msg.sender.balance;

        ///@notice Calculate amountOutRequired.
        uint256 amountOutRequired = balanceBefore + swapData.amountOutMin;

        ///@notice Execute Multicall.
        IConveyorMulticall(CONVEYOR_MULTICALL).executeGenericMulticall(swapAggregatorMulticall);

        ///@notice Get WETH balance of this contract.
        uint256 balanceWeth = IERC20(WETH).balanceOf(address(this));

        ///@notice Withdraw WETH from this contract.
        _withdrawEth(balanceWeth, WETH);

        ///@notice Transfer ETH to msg.sender.
        _safeTransferETH(msg.sender, balanceWeth);

        ///@notice Revert if Eth balance of the caller is insufficient.
        if (msg.sender.balance < amountOutRequired) {
            revert InsufficientOutputAmount(amountOutRequired - msg.sender.balance, swapData.amountOutMin);
        }

        address affiliate = affiliates[swapData.affiliate];

        _safeTransferETH(affiliate, ConveyorMath.mul64U(AFFILIATE_PERCENT, msg.value));

        ///@notice Emit SwapExactTokenForEth event.
        emit SwapExactTokenForEth(tokenIn, swapData.amountIn, msg.sender.balance - balanceBefore, msg.sender);
    }

    /// @notice Swap tokens for ETH with referral.
    function swapExactTokenForEthViaReferral(
        address tokenIn,
        ReferralSwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable {
        ///TODO:
    }

    /// @notice Quotes the amount of gas used for a optimized token to token swap.
    /// @dev This function should be used off chain through a static call.
    function quoteSwapExactTokenForToken(
        address tokenIn,
        address tokenOut,
        SwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed) {
        assembly {
            mstore(0x60, gas())
        }
        swapExactTokenForToken(tokenIn, tokenOut, swapData, swapAggregatorMulticall);
        assembly {
            gasConsumed := sub(mload(0x60), gas())
        }
    }

    /// @notice Quotes the amount of gas used for a ETH to token swap.
    /// @dev This function should be used off chain through a static call.
    function quoteSwapExactEthForToken(
        address tokenOut,
        EthToTokenSwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed) {
        assembly {
            mstore(0x60, gas())
        }
        swapExactEthForToken(tokenOut, swapData, swapAggregatorMulticall);
        assembly {
            gasConsumed := sub(mload(0x60), gas())
        }
    }

    /// @notice Quotes the amount of gas used for a token to ETH swap.
    /// @dev This function should be used off chain through a static call.
    function quoteSwapExactTokenForEth(
        address tokenIn,
        SwapData calldata swapData,
        SwapAggregatorGenericMulticall calldata swapAggregatorMulticall
    ) external payable returns (uint256 gasConsumed) {
        assembly {
            mstore(0x60, gas())
        }
        swapExactTokenForEth(tokenIn, swapData, swapAggregatorMulticall);
        assembly {
            gasConsumed := sub(mload(0x60), gas())
        }
    }

    ///@notice Helper function to transfer ETH.
    function _safeTransferETH(address to, uint256 amount) internal {
        bool success;
        /// @solidity memory-safe-assembly
        assembly {
            // Transfer the ETH and store if it succeeded or not.
            success := call(gas(), to, amount, 0, 0, 0, 0)
        }

        if (!success) {
            revert ETHTransferFailed();
        }
    }

    /// @notice Helper function to Withdraw ETH from WETH.
    function _withdrawEth(uint256 amount, address weth) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0, shl(224, 0x2e1a7d4d) /* keccak256("withdraw(uint256)") */ )
            mstore(4, amount)
            if iszero(
                call(
                    gas(), /* gas */
                    weth, /* to */
                    0, /* value */
                    0, /* in */
                    68, /* in size */
                    0, /* out */
                    0 /* out size */
                )
            ) { revert("Native Token Withdraw failed", amount) }
        }
    }

    /// @notice Helper function to Deposit ETH into WETH.
    function _depositEth(uint256 amount, address weth) internal {
        /// @solidity memory-safe-assembly
        assembly {
            mstore(0x0, shl(224, 0xd0e30db0)) /* keccak256("deposit()") */
            if iszero(
                call(
                    gas(), /* gas */
                    weth, /* to */
                    amount, /* value */
                    0, /* in */
                    0, /* in size */
                    0, /* out */
                    0 /* out size */
                )
            ) { revert("Native token deposit failed", amount) }
        }
    }

    /// @notice Withdraw ETH from this contract.
    function withdraw() external onlyOwner {
        _safeTransferETH(msg.sender, address(this).balance);
        emit Withdraw(msg.sender, address(this).balance);
    }

    ///@notice Function to confirm ownership transfer of the contract.
    function confirmTransferOwnership() external {
        if (msg.sender != tempOwner) {
            revert UnauthorizedCaller();
        }

        ///@notice Cleanup tempOwner storage.
        tempOwner = address(0);
        owner = msg.sender;
    }

    ///@notice Function to transfer ownership of the contract.
    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) {
            revert InvalidAddress();
        }

        tempOwner = newOwner;
    }

    ///@notice Function to upgrade the ConveyorMulticall contract.
    function upgradeMulticall(bytes memory bytecode, bytes32 salt) external payable onlyOwner returns (address) {
        assembly {
            let addr := create2(callvalue(), add(bytecode, 0x20), mload(bytecode), salt)

            if iszero(extcodesize(addr)) { revert(0, 0) }

            sstore(CONVEYOR_MULTICALL.slot, addr)
        }

        return CONVEYOR_MULTICALL;
    }

    ///@notice Function to set affiliate address.
    function setAffiliate(uint16 affiliateId, address affiliateAddress) external {
        affiliates[affiliateId] = affiliateAddress;
    }

    /// @notice Fallback receiver function.
    receive() external payable {}
}

/// @title ConveyorMulticall
/// @author 0xOsiris, 0xKitsune, Conveyor Labs
/// @notice Optimized multicall execution contract.
contract ConveyorMulticall is UniswapV3Callback, UniswapV2Callback {
    using SafeERC20 for IERC20;

    address immutable CONVEYOR_SWAP_AGGREGATOR;

    ///@param conveyorRouterV1 Address of the ConveyorRouterV1 contract.
    constructor(address conveyorRouterV1) {
        CONVEYOR_SWAP_AGGREGATOR = conveyorRouterV1;
    }

    function executeGenericMulticall(ConveyorRouterV1.SwapAggregatorGenericMulticall calldata multicall) external {
        for (uint256 i = 0; i < multicall.calls.length; i++) {
            (bool success,) = multicall.calls[i].target.call(multicall.calls[i].callData);
            if (!success) {
                revert CallFailed();
            }
        }
    }
}
