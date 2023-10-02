# Sstan Report 

 ()

TODO: add description

TODO: add date

0.1.0

0x00face, 0xOsiris



# Summary




# <h3>Vulnerabilities</h3> 

 | Classification | Title | Instances | 
 |:-------:|:---------:|:-------:| 
 | [[H-0]](#[H-0]) | <Strong>Uninitialized storage variables</Strong> | 2 |
 | [[L-1]](#[L-1]) | <Strong>Unsafe ERC20 Operation</Strong> | 27 |
# <h3>Optimizations</h3> 

 | Classification | Title | Instances | 
 |:-------:|:---------:|:-------:| 
 | [[G-0]](#[G-0]) | <Strong>Use assembly when getting a contract's balance of ETH</Strong> | 1 |
 | [[G-1]](#[G-1]) | <Strong>Use assembly to check for address(0)</Strong> | 7 |
 | [[G-2]](#[G-2]) | <Strong>Cache array length during for loop definition.</Strong> | 8 |
 | [[G-3]](#[G-3]) | <Strong>Cache Storage Variables in Memory</Strong> | 6 |
 | [[G-4]](#[G-4]) | <Strong>Event is not properly indexed.</Strong> | 4 |
 | [[G-5]](#[G-5]) | <Strong>Mark storage variables as `immutable` if they never change after contract initialization.</Strong> | 2 |
 | [[G-6]](#[G-6]) | <Strong>`unchecked{++i}` instead of `i++` (or use assembly when applicable)</Strong> | 4 |
 | [[G-7]](#[G-7]) | <Strong>Use `calldata` instead of `memory` for function arguments that do not get mutated.</Strong> | 5 |
 | [[G-8]](#[G-8]) | <Strong>Use multiple require() statments insted of require(expression && expression && ...)</Strong> | 2 |
 | [[G-9]](#[G-9]) | <Strong>Optimal Comparison</Strong> | 6 |
 | [[G-10]](#[G-10]) | <Strong>Tightly pack storage variables</Strong> | 4 |
 | [[G-11]](#[G-11]) | <Strong>Mark functions as payable (with discretion)</Strong> | 44 |
 | [[G-12]](#[G-12]) | <Strong>Consider marking constants as private</Strong> | 14 |
 | [[G-13]](#[G-13]) | <Strong>Avoid Reading From Storage in a for loop</Strong> | 3 |
 | [[G-14]](#[G-14]) | <Strong>Use assembly to hash instead of Solidity</Strong> | 2 |
 | [[G-15]](#[G-15]) | <Strong>Use assembly for math (add, sub, mul, div)</Strong> | 12 |
 | [[G-16]](#[G-16]) | <Strong>Use assembly to write storage values</Strong> | 6 |
 | [[G-17]](#[G-17]) | <Strong>Use custom errors instead of string error messages</Strong> | 10 |
# <h3>Quality Assurance</h3> 

 | Classification | Title | Instances | 
 |:-------:|:---------:|:-------:| 
 | [[NC-0]](#[NC-0]) | <Strong>Constructor should be listed before any other function</Strong> | 1 |
 | [[NC-1]](#[NC-1]) | <Strong>Private variables should contain a leading underscore</Strong> | 1 |
 | [[NC-2]](#[NC-2]) | <Strong>Constructor should initialize all variables</Strong> | 13 |
 | [[NC-3]](#[NC-3]) | <Strong>Consider importing specific identifiers instead of the whole file</Strong> | 156 |
 | [[NC-4]](#[NC-4]) | <Strong>Constants & Immutables should be named with screaming snake case</Strong> | 6 |
 | [[NC-5]](#[NC-5]) | <Strong>Consider using scientific notation for large multiples of 10</Strong> | 17 |
 | [[NC-6]](#[NC-6]) | <Strong>Remove any unused functions</Strong> | 28 |
 | [[NC-7]](#[NC-7]) | <Strong>Storage variables should be named with camel case</Strong> | 1 |
 | [[NC-8]](#[NC-8]) | <Strong>Remove any unused returns</Strong> | 11 |

 <details open> 
 <summary> 
 <h3>Vulnerabilities - Instances: 2 </h3> 
 </summary> 
  

 <details open> 
 <summary> 
 <a name=[H-0]></a> [H-0] 
 <h3> Uninitialized storage variables - Instances: 2 </h3> 
 </summary>
 
> A storage variable that is declared but not initialized will have a default value of zero (or the equivalent, such as an empty array for array types or zero-address for address types). Failing to initialize a storage variable can pose risks if the contract logic assumes that the variable has been explicitly set to a particular value. 

File:ConveyorTickMath.sol 
```solidity
24:    mapping(int24 => Tick.Info) public ticks;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
91:    mapping(address => uint256) dexToIndex;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[L-1]></a> [L-1] 
 <h3> Unsafe ERC20 Operation - Instances: 27 </h3> 
 </summary>
 
> ERC20 operations can be unsafe due to different implementations and vulnerabilities in the standard. To account for this, either use OpenZeppelin's SafeERC20 library or wrap each operation in a require statement.
> Additionally, ERC20's approve functions have a known race-condition vulnerability. To account for this, use OpenZeppelin's SafeERC20 library's `safeIncrease` or `safeDecrease` Allowance functions.
        
#### Unsafe Transfer

```js
IERC20(token).transfer(msg.sender, amount);
```

#### OpenZeppelin SafeTransfer

```js
import {SafeERC20} from "openzeppelin/token/utils/SafeERC20.sol";
//--snip--

IERC20(token).safeTransfer(msg.sender, address(this), amount);
```
        
#### Safe Transfer with require statement.

```js
bool success = IERC20(token).transfer(msg.sender, amount);
require(success, "ERC20 transfer failed");
```
        
#### Unsafe TransferFrom

```js
IERC20(token).transferFrom(msg.sender, address(this), amount);
```

#### OpenZeppelin SafeTransferFrom

```js
import {SafeERC20} from "openzeppelin/token/utils/SafeERC20.sol";
//--snip--

IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
```
        
#### Safe TransferFrom with require statement.

```js
bool success = IERC20(token).transferFrom(msg.sender, address(this), amount);
require(success, "ERC20 transfer failed");
```
        
         

File:DefiSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:KyberSwapV3Callback.sol 
```solidity
19:            IERC20(_tokenIn).transferFrom(_sender, msg.sender, amountIn);
``` 



File:KyberSwapV3Callback.sol 
```solidity
21:            IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:WaultSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:ApeSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:JetSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:BiswapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:TraderJoeCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:MdexSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:VerseCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:DystopiaCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:UniFiCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:BabyDogeCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:PancakeV2Callback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:ElkSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:SakeSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:UniswapV2Callback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:LinkSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:MeerkatCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:DXSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:CafeSwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:BabySwapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:ConveyorRouterV1.sol 
```solidity
119:        IERC20(swapData.tokenIn).transferFrom(msg.sender, genericMulticall.tokenInDestination, swapData.amountIn);
``` 



File:ConveyorRouterV1.sol 
```solidity
169:        IERC20(WETH).transfer(swapAggregatorMulticall.tokenInDestination, amountIn);
``` 



File:ConveyorRouterV1.sol 
```solidity
214:            IERC20(swapData.tokenIn).transferFrom(
``` 



File:NomiswapCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 



File:ConvergenceXCallback.sol 
```solidity
22:        IERC20(_tokenIn).transfer(msg.sender, amountIn);
``` 

 
 </details> 
 </details>

 <details open> 
 <summary> 
 <h3>Optimizations - Instances: 18 </h3> 
 </summary> 
  

 <details open> 
 <summary> 
 <a name=[G-0]></a> [G-0] 
 <h3> Use assembly when getting a contract's balance of ETH - Instances: 1 </h3> 
 </summary>
 
 
> You can use `selfbalance()` instead of `address(this).balance` when getting your contract's balance of ETH to save gas. Additionally, you can use `balance(address)` instead of `address.balance()` when getting an external contract's balance of ETH.
     
 
#### Gas Report  - Savings: ~15 
 <details>  
 <summary>  
  </summary> 
 
        
```solidity
contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    Contract2 c2;
    Contract3 c3;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        c2 = new Contract2();
        c3 = new Contract3();
    }

    function testGas() public {
        c0.addressInternalBalance();
        c1.assemblyInternalBalance();
        c2.addressExternalBalance(address(this));
        c3.assemblyExternalBalance(address(this));
    }
}

contract Contract0 {
    function addressInternalBalance() public returns (uint256) {
        return address(this).balance;
    }
}

contract Contract1 {
    function assemblyInternalBalance() public returns (uint256) {
        assembly {
            let c := selfbalance()
            mstore(0x00, c)
            return(0x00, 0x20)
        }
    }
}

contract Contract2 {
    function addressExternalBalance(address addr) public {
        uint256 bal = address(addr).balance;
        bal++;
    }
}

contract Contract3 {
    function assemblyExternalBalance(address addr) public {
        uint256 bal;
        assembly {
            bal := balance(addr)
        }
        bal++;
    }
}
```


```solidity
╭────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract0 contract     ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost        ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 23675                  ┆ 147             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name          ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addressInternalBalance ┆ 148             ┆ 148 ┆ 148    ┆ 148 ┆ 1       │
╰────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭─────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract      ┆                 ┆     ┆        ┆     ┆         │
╞═════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost         ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 27081                   ┆ 165             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name           ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ assemblyInternalBalance ┆ 133             ┆ 133 ┆ 133    ┆ 133 ┆ 1       │
╰─────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract2 contract     ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost        ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 61511                  ┆ 339             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name          ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addressExternalBalance ┆ 417             ┆ 417 ┆ 417    ┆ 417 ┆ 1       │
╰────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭─────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract3 contract      ┆                 ┆     ┆        ┆     ┆         │
╞═════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost         ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 57105                   ┆ 317             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name           ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ assemblyExternalBalance ┆ 411             ┆ 411 ┆ 411    ┆ 411 ┆ 1       │
╰─────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```
 
 </details> 
 

File:ConveyorRouterV1.sol 
```solidity
361:        _safeTransferETH(msg.sender, address(this).balance);
``` 



File:ConveyorRouterV1.sol 
```solidity
362:        emit Withdraw(msg.sender, address(this).balance);
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-1]></a> [G-1] 
 <h3> Use assembly to check for address(0) - Instances: 7 </h3> 
 </summary>
 
  
 
#### Gas Report - Savings: ~6 
 <details>  
 <summary>  
  </summary> 
 
```solidity


contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
    }

    function testGas() public view {
        c0.ownerNotZero(address(this));
        c1.assemblyOwnerNotZero(address(this));
    }
}

contract Contract0 {
    function ownerNotZero(address _addr) public pure {
        require(_addr != address(0), "zero address)");
    }
}

contract Contract1 {
    function assemblyOwnerNotZero(address _addr) public pure {
        assembly {
            if iszero(_addr) {
                mstore(0x00, "zero address")
                revert(0x00, 0x20)
            }
        }
    }
}


```

```solidity
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 61311              ┆ 338             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ ownerNotZero       ┆ 258             ┆ 258 ┆ 258    ┆ 258 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭──────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract   ┆                 ┆     ┆        ┆     ┆         │
╞══════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost      ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 44893                ┆ 255             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name        ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ assemblyOwnerNotZero ┆ 252             ┆ 252 ┆ 252    ┆ 252 ┆ 1       │
╰──────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
```
 
 </details> 
 

File:ConveyorRouterV1.sol 
```solidity
63:        require(_weth != address(0), "WETH address is zero");
``` 



File:ConveyorRouterV1.sol 
```solidity
136:            if (affiliate == address(0)) {
``` 



File:ConveyorRouterV1.sol 
```solidity
144:            if (referrer == address(0)) {
``` 



File:ConveyorRouterV1.sol 
```solidity
189:            if (affiliate == address(0)) {
``` 



File:ConveyorRouterV1.sol 
```solidity
197:            if (referrer == address(0)) {
``` 



File:ConveyorRouterV1.sol 
```solidity
212:        if (swapAggregatorMulticall.tokenInDestination != address(0)) {
``` 



File:ConveyorRouterV1.sol 
```solidity
242:            if (affiliate == address(0)) {
``` 



File:ConveyorRouterV1.sol 
```solidity
250:            if (referrer == address(0)) {
``` 



File:ConveyorRouterV1.sol 
```solidity
378:        if (newOwner == address(0)) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
93:        require(_limitOrderExecutor != address(0), "limitOrderExecutor address is address(0)");
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1267:        if (newOwner == address(0)) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
131:            require(_dexFactories[i] != address(0), "Zero values in constructor");
``` 



File:LimitOrderSwapRouter.sol 
```solidity
432:        if (address(0) == pairAddress) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
499:        if (pool == address(0)) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
540:        if (token0 == address(0)) {
``` 



File:LimitOrderRouter.sol 
```solidity
69:        require(_limitOrderExecutor != address(0), "Invalid ConveyorExecutor address");
``` 



File:LimitOrderRouter.sol 
```solidity
359:        if (newOwner == address(0)) {
``` 



File:ConveyorExecutor.sol 
```solidity
118:        require(_weth != address(0), "Invalid weth address");
``` 



File:ConveyorExecutor.sol 
```solidity
119:        require(_usdc != address(0), "Invalid usdc address");
``` 



File:ConveyorExecutor.sol 
```solidity
120:        require(_limitOrderQuoterAddress != address(0), "Invalid LimitOrderQuoter address");
``` 



File:ConveyorExecutor.sol 
```solidity
529:        if (newOwner == address(0)) {
``` 



File:LimitOrderBook.sol 
```solidity
42:        require(_limitOrderExecutor != address(0), "limitOrderExecutor address is address(0)");
``` 



File:LimitOrderQuoter.sol 
```solidity
16:        require(_weth != address(0), "Invalid weth address");
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-2]></a> [G-2] 
 <h3> Cache array length during for loop definition. - Instances: 8 </h3> 
 </summary>
 
 
> A typical for loop definition may look like: `for (uint256 i; i < arr.length; i++){}`. Instead of using `array.length`, cache the array length before the loop, and use the cached value to safe gas. This will avoid an `MLOAD` every loop for arrays stored in memory and an `SLOAD` for arrays stored in storage. This can have significant gas savings for arrays with a large length, especially if the array is stored in storage. 
 
#### Gas Report - Savings: ~22 
 <details>  
 <summary>  
  </summary> 
 
        
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    Contract2 c2;
    Contract3 c3;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        c2 = new Contract2();
        c3 = new Contract3();
    }

    function testGas() public view {
        uint256[] memory arr = new uint256[](10);
        c0.nonCachedMemoryListLength(arr);
        c1.cachedMemoryListLength(arr);
        c2.nonCachedStorageListLength();
        c3.cachedStorageListLength();
    }
}

contract Contract0 {
    function nonCachedMemoryListLength(uint256[] memory arr) public pure {
        uint256 j;
        for (uint256 i; i < arr.length; i++) {
            j = arr[i] + 10;
        }
    }
}

contract Contract1 {
    function cachedMemoryListLength(uint256[] memory arr) public pure {
        uint256 j;

        uint256 length = arr.length;
        for (uint256 i; i < length; i++) {
            j = arr[i] + 10;
        }
    }
}

contract Contract2 {
    uint256[] arr = new uint256[](10);

    function nonCachedStorageListLength() public view {
        uint256 j;
        for (uint256 i; i < arr.length; i++) {
            j = arr[i] + 10;
        }
    }
}

contract Contract3 {
    uint256[] arr = new uint256[](10);

    function cachedStorageListLength() public view {
        uint256 j;
        uint256 length = arr.length;

        for (uint256 i; i < length; i++) {
            j = arr[i] + 10;
        }
    }
}


```

```solidity
╭───────────────────────────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ src/test/GasTest.t.sol:Contract0 contract ┆                 ┆      ┆        ┆      ┆         │
╞═══════════════════════════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 128171                                    ┆ 672             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ nonCachedMemoryListLength                 ┆ 3755            ┆ 3755 ┆ 3755   ┆ 3755 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ src/test/GasTest.t.sol:Contract1 contract ┆                 ┆      ┆        ┆      ┆         │
╞═══════════════════════════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 128777                                    ┆ 675             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ cachedMemoryListLength                    ┆ 3733            ┆ 3733 ┆ 3733   ┆ 3733 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬───────┬────────┬───────┬─────────╮
│ src/test/GasTest.t.sol:Contract2 contract ┆                 ┆       ┆        ┆       ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═══════╪════════╪═══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 118474                                    ┆ 539             ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg   ┆ median ┆ max   ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ nonCachedStorageListLength                ┆ 27979           ┆ 27979 ┆ 27979  ┆ 27979 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴───────┴────────┴───────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬───────┬────────┬───────┬─────────╮
│ src/test/GasTest.t.sol:Contract3 contract ┆                 ┆       ┆        ┆       ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═══════╪════════╪═══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 118674                                    ┆ 540             ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg   ┆ median ┆ max   ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ cachedStorageListLength                   ┆ 26984           ┆ 26984 ┆ 26984  ┆ 26984 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴───────┴────────┴───────┴─────────╯

```
    
 
 </details> 
 

File:LimitOrderSwapRouter.sol 
```solidity
127:        for (uint256 i = 0; i < _dexFactories.length; ++i) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
588:            for (uint256 i = 0; i < dexes.length;) {
``` 



File:ConveyorExecutor.sol 
```solidity
182:        for (uint256 i = 0; i < orders.length;) {
``` 



File:ConveyorExecutor.sol 
```solidity
308:        for (uint256 i = 0; i < orders.length;) {
``` 



File:ConveyorExecutor.sol 
```solidity
431:            for (uint256 i = 0; i < orders.length;) {
``` 



File:ConveyorExecutor.sol 
```solidity
452:            for (uint256 i = 0; i < orders.length;) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
316:        for (uint256 i = 0; i < orderGroup.length;) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
330:                    for (uint256 k = 0; k < spRes.length;) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
512:        for (uint256 i = 0; i < orderIds.length;) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
633:        for (uint256 i = 0; i < orderIds.length;) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
749:            for (uint256 i = 0; i < orderIdBundles.length;) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
752:                for (uint256 j = 0; j < orderIdBundle.length;) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
814:        for (uint256 i = 0; i < orderIdBundles.length;) {
``` 



File:ConveyorRouterV1.sol 
```solidity
451:        for (uint256 i = 0; i < multicall.calls.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
58:            for (uint256 i = 0; i < executionPrices.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
74:            for (uint256 i = 0; i < executionPrices.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
102:            for (uint256 i = 0; i < executionPrices.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
116:            for (uint256 i = 0; i < executionPrices.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
147:            for (uint256 i = 0; i < spotReserveAToWeth.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
186:            for (uint256 i = 0; i < spotReserveWethToB.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
206:            for (uint256 i = 0; i < spotReserveAToWeth.length;) {
``` 



File:LimitOrderQuoter.sol 
```solidity
208:                for (uint256 j = 0; j < spotReserveWethToB.length;) {
``` 



File:LimitOrderRouter.sol 
```solidity
91:        for (uint256 i = 0; i < orderIds.length;) {
``` 



File:LimitOrderRouter.sol 
```solidity
210:        for (uint256 i = 0; i < orders.length - 1;) {
``` 



File:LimitOrderRouter.sol 
```solidity
283:        for (uint256 i = 0; i < orderIds.length;) {
``` 



File:LimitOrderRouter.sol 
```solidity
323:        for (uint256 i = 0; i < orderIds.length;) {
``` 



File:LimitOrderRouter.sol 
```solidity
338:        for (uint256 i = 0; i < orders.length;) {
``` 



File:LimitOrderBook.sol 
```solidity
280:        for (uint256 i = 0; i < orderGroup.length;) {
``` 



File:LimitOrderBook.sol 
```solidity
484:        for (uint256 i = 0; i < orderIds.length;) {
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
76:        for (uint256 i = 0; i < sandboxMulticall.calls.length;) {
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-3]></a> [G-3] 
 <h3> Cache Storage Variables in Memory - Instances: 6 </h3> 
 </summary>
 
  
 Cache Array Length - Gas Report - Savings: ~0 
 <details>  
 <summary>  
  </summary> 
  
 </details> 
 

File:LimitOrderRouter.sol 
```solidity
354:        tempOwner = address(0);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
65:        reentrancyStatus = true;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
67:        reentrancyStatus = false;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
252:                revert InsufficientExecutionCredit(executionCreditRemaining - amount, minExecutionCredit);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
256:        orderIdToSandboxLimitOrder[orderId].executionCreditRemaining = executionCreditRemaining - amount;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
275:            orderIdToSandboxLimitOrder[orderId].executionCreditRemaining + uint128(msg.value);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
277:        orderIdToSandboxLimitOrder[orderId].executionCreditRemaining = newExecutionCreditBalance;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
392:                orderNonce += 2;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
471:                orderIdToSandboxLimitOrder[order.orderId].executionCreditRemaining + uint128(msg.value);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
472:            orderIdToSandboxLimitOrder[order.orderId].executionCreditRemaining = newExecutionCredit;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
500:        orderIdToSandboxLimitOrder[order.orderId].amountInRemaining = amountInRemaining;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
501:        orderIdToSandboxLimitOrder[order.orderId].amountOutRemaining = amountOutRemaining;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
536:        delete orderIdToSandboxLimitOrder[orderId];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
548:        addressToOrderIds[order.owner][order.orderId] = OrderType.CanceledSandboxLimitOrder;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
607:            orderIdToSandboxLimitOrder[order.orderId].executionCreditRemaining = 0;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
684:        orderIdToSandboxLimitOrder[order.orderId].lastRefreshTimestamp = uint32(block.timestamp);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1054:        orderIdToSandboxLimitOrder[orderId].fillPercent += percentFilled;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1057:        orderIdToSandboxLimitOrder[orderId].amountInRemaining = order.amountInRemaining - amountInFilled;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1059:        orderIdToSandboxLimitOrder[orderId].amountOutRemaining = order.amountOutRemaining - amountOutFilled;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1068:        orderIdToSandboxLimitOrder[orderId].feeRemaining = updatedFeeRemaining;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1075:        orderIdToSandboxLimitOrder[order.orderId].executionCreditRemaining = updatedExecutionCreditRemaining;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1095:        delete orderIdToSandboxLimitOrder[order.orderId];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1117:        delete orderIdToSandboxLimitOrder[orderId];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1127:        addressToOrderIds[order.owner][order.orderId] = OrderType.FilledSandboxLimitOrder;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1252:        minExecutionCredit = newMinExecutionCredit;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1262:        tempOwner = address(0);
``` 



File:LimitOrderBook.sol 
```solidity
31:        reentrancyStatus = true;
``` 



File:LimitOrderBook.sol 
```solidity
33:        reentrancyStatus = false;
``` 



File:LimitOrderBook.sol 
```solidity
186:            revert InsufficientExecutionCredit(executionCredit - amount, minExecutionCredit);
``` 



File:LimitOrderBook.sol 
```solidity
189:        orderIdToLimitOrder[orderId].executionCredit = executionCredit - amount;
``` 



File:LimitOrderBook.sol 
```solidity
214:        uint128 newExecutionCreditBalance = orderIdToLimitOrder[orderId].executionCredit + uint128(msg.value);
``` 



File:LimitOrderBook.sol 
```solidity
216:        orderIdToLimitOrder[orderId].executionCredit = newExecutionCreditBalance;
``` 



File:LimitOrderBook.sol 
```solidity
318:                orderNonce += 2;
``` 



File:LimitOrderBook.sol 
```solidity
408:            uint128 newExecutionCredit = orderIdToLimitOrder[order.orderId].executionCredit + uint128(msg.value);
``` 



File:LimitOrderBook.sol 
```solidity
409:            orderIdToLimitOrder[order.orderId].executionCredit = newExecutionCredit;
``` 



File:LimitOrderBook.sol 
```solidity
437:        orderIdToLimitOrder[order.orderId].price = price;
``` 



File:LimitOrderBook.sol 
```solidity
438:        orderIdToLimitOrder[order.orderId].quantity = quantity;
``` 



File:LimitOrderBook.sol 
```solidity
461:        delete orderIdToLimitOrder[orderId];
``` 



File:LimitOrderBook.sol 
```solidity
473:        addressToOrderIds[order.owner][order.orderId] = OrderType.CanceledLimitOrder;
``` 



File:LimitOrderBook.sol 
```solidity
499:        delete orderIdToLimitOrder[orderId];
``` 



File:LimitOrderBook.sol 
```solidity
520:        delete orderIdToLimitOrder[orderId];
``` 



File:LimitOrderBook.sol 
```solidity
530:        addressToOrderIds[order.owner][order.orderId] = OrderType.FilledLimitOrder;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
354:        uniV3AmountOut = 0;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
382:            uniV3AmountOut = uint256(-amount0Delta);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
386:        if (uniV3AmountOut < amountOutMin) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
387:            revert InsufficientOutputAmount(uniV3AmountOut, amountOutMin);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
585:            address[] memory _lps = new address[](dexes.length);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
588:            for (uint256 i = 0; i < dexes.length;) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
589:                if (dexes[i].isUniV2) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
593:                            _calculateV2SpotPrice(token0, token1, dexes[i].factoryAddress);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
605:                                _calculateV3SpotPrice(token0, token1, FEE, dexes[i].factoryAddress);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
623:            SpotReserve[] memory _spotPrices = new SpotReserve[](dexes.length);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
624:            address[] memory _lps = new address[](dexes.length);
``` 



File:ConveyorRouterV1.sol 
```solidity
372:        tempOwner = address(0);
``` 



File:ConveyorRouterV1.sol 
```solidity
406:            affiliateNonce = tempAffiliateNonce;
``` 



File:ConveyorRouterV1.sol 
```solidity
417:        referrerIndex[msg.sender] = uint16(tempReferrerNonce);
``` 



File:ConveyorRouterV1.sol 
```solidity
422:            referrerNonce = tempReferrerNonce;
``` 



File:ConveyorRouterV1.sol 
```solidity
443:        locked = true;
``` 



File:ConveyorRouterV1.sol 
```solidity
445:        locked = false;
``` 



File:ConveyorExecutor.sol 
```solidity
68:        reentrancyStatus = true;
``` 



File:ConveyorExecutor.sol 
```solidity
70:        reentrancyStatus = false;
``` 



File:ConveyorExecutor.sol 
```solidity
510:        uint256 withdrawAmount = conveyorBalance;
``` 



File:ConveyorExecutor.sol 
```solidity
512:        conveyorBalance = 0;
``` 



File:ConveyorExecutor.sol 
```solidity
523:        tempOwner = address(0);
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-4]></a> [G-4] 
 <h3> Event is not properly indexed. - Instances: 4 </h3> 
 </summary>
 
 
> When possible, always include a minimum of 3 indexed event topics to save gas 
 
#### Gas Report - Savings: ~0 
 <details>  
 <summary>  
  </summary> 
  
 </details> 
 

File:ConveyorExecutor.sol 
```solidity
103:    event ExecutorCheckIn(address executor, uint256 timestamp);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
111:    event OrderPlaced(bytes32[] orderIds);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
117:    event OrderCanceled(bytes32[] orderIds);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
123:    event OrderUpdated(bytes32[] orderIds);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
129:    event OrderFilled(bytes32[] orderIds);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
151:    event OrderExecutionCreditUpdated(bytes32 orderId, uint256 newExecutionCredit);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
156:    event MinExecutionCreditUpdated(uint256 newMinExecutionCredit, uint256 oldMinExecutionCredit);
``` 



File:ConveyorRouterV1.sol 
```solidity
33:    event Withdraw(address indexed receiver, uint256 amount);
``` 



File:LimitOrderBook.sol 
```solidity
57:    event OrderPlaced(bytes32[] orderIds);
``` 



File:LimitOrderBook.sol 
```solidity
63:    event OrderCanceled(bytes32[] orderIds);
``` 



File:LimitOrderBook.sol 
```solidity
69:    event OrderUpdated(bytes32[] orderIds);
``` 



File:LimitOrderBook.sol 
```solidity
74:    event OrderExecutionCreditUpdated(bytes32 orderId, uint256 newExecutionCredit);
``` 



File:LimitOrderBook.sol 
```solidity
80:    event OrderFilled(bytes32[] orderIds);
``` 



File:LimitOrderBook.sol 
```solidity
90:    event MinExecutionCreditUpdated(uint256 newMinExecutionCredit, uint256 oldMinExecutionCredit);
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-5]></a> [G-5] 
 <h3> Mark storage variables as `immutable` if they never change after contract initialization. - Instances: 2 </h3> 
 </summary>
 
 
> State variables can be declared as constant or immutable. In both cases, the variables cannot be modified after the contract has been constructed. For constant variables, the value has to be fixed at compile-time, while for immutable, it can still be assigned at construction time. 
 The compiler does not reserve a storage slot for these variables, and every occurrence is inlined by the respective value. 
 Compared to regular state variables, the gas costs of constant and immutable variables are much lower. For a constant variable, the expression assigned to it is copied to all the places where it is accessed and also re-evaluated each time. This allows for local optimizations. Immutable variables are evaluated once at construction time and their value is copied to all the places in the code where they are accessed. For these values, 32 bytes are reserved, even if they would fit in fewer bytes. Due to this, constant values can sometimes be cheaper than immutable values. 
 
 
#### Gas Report - Savings: ~2103 
 <details>  
 <summary>  
  </summary> 
 

```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    Contract2  c2;
    
    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        c2 = new Contract2();
        
    }

    function testGas() public view {
        c0.addValue();
        c1.addImmutableValue();
        c2.addConstantValue();
    }
}

contract Contract0 {
    uint256 val;

    constructor() {
        val = 10000;
    }

    function addValue() public view {
        uint256 newVal = val + 1000;
    }
}

contract Contract1 {
    uint256 immutable val;

    constructor() {
        val = 10000;
    }

    function addImmutableValue() public view {
        uint256 newVal = val + 1000;
    }
}

contract Contract2 {
    uint256 constant val = 10;

    function addConstantValue() public view {
        uint256 newVal = val + 1000;
    }
}

```

```solidity
╭────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ Contract0 contract ┆                 ┆      ┆        ┆      ┆         │
╞════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 54593              ┆ 198             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addValue           ┆ 2302            ┆ 2302 ┆ 2302   ┆ 2302 ┆ 1       │
╰────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 38514              ┆ 239             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addImmutableValue  ┆ 199             ┆ 199 ┆ 199    ┆ 199 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract2 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 32287              ┆ 191             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addConstantValue   ┆ 199             ┆ 199 ┆ 199    ┆ 199 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
```

         
 </details> 
 

File:ConveyorRouterV1.sol 
```solidity
20:    address public CONVEYOR_MULTICALL;
``` 



File:LimitOrderBook.sol 
```solidity
21:    uint256 minExecutionCredit;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-6]></a> [G-6] 
 <h3> `unchecked{++i}` instead of `i++` (or use assembly when applicable) - Instances: 4 </h3> 
 </summary>
 
 
> Use `++i` instead of `i++`. This is especially useful in for loops but this optimization can be used anywhere in your code. You can also use `unchecked{++i;}` for even more gas savings but this will not check to see if `i` overflows. For extra safety if you are worried about this, you can add a require statement after the loop checking if `i` is equal to the final incremented value. For best gas savings, use inline assembly, however this limits the functionality you can achieve. For example you cant use Solidity syntax to internally call your own contract within an assembly block and external calls must be done with the `call()` or `delegatecall()` instruction. However when applicable, inline assembly will save much more gas. 
 
#### Gas Report - Savings: ~342 
 <details>  
 <summary>  
  </summary> 
 
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    Contract2 c2;
    Contract3 c3;
    Contract4 c4;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        c2 = new Contract2();
        c3 = new Contract3();
        c4 = new Contract4();
    }

    function testGas() public {
        c0.iPlusPlus();
        c1.plusPlusI();
        c2.uncheckedPlusPlusI();
        c3.safeUncheckedPlusPlusI();
        c4.inlineAssemblyLoop();
    }
}

contract Contract0 {
    //loop with i++
    function iPlusPlus() public pure {
        uint256 j = 0;
        for (uint256 i; i < 10; i++) {
            j++;
        }
    }
}

contract Contract1 {
    //loop with ++i
    function plusPlusI() public pure {
        uint256 j = 0;
        for (uint256 i; i < 10; ++i) {
            j++;
        }
    }
}

contract Contract2 {
    //loop with unchecked{++i}
    function uncheckedPlusPlusI() public pure {
        uint256 j = 0;
        for (uint256 i; i < 10; ) {
            j++;

            unchecked {
                ++i;
            }
        }
    }
}

contract Contract3 {
    //loop with unchecked{++i} with additional overflow check
    function safeUncheckedPlusPlusI() public pure {
        uint256 j = 0;
        uint256 i = 0;
        for (i; i < 10; ) {
            j++;

            unchecked {
                ++i;
            }
        }

        //check for overflow
        assembly {
            if lt(i, 10) {
                mstore(0x00, "loop overflow")
                revert(0x00, 0x20)
            }
        }
    }
}

contract Contract4 {
    //loop with inline assembly
    function inlineAssemblyLoop() public pure {
        assembly {
            let j := 0

            for {
                let i := 0
            } lt(i, 10) {
                i := add(i, 0x01)
            } {
                j := add(j, 0x01)
            }
        }
    }
}

```


```solidity

╭────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ Contract0 contract ┆                 ┆      ┆        ┆      ┆         │
╞════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37687              ┆ 219             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ iPlusPlus          ┆ 2039            ┆ 2039 ┆ 2039   ┆ 2039 ┆ 1       │
╰────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ Contract1 contract ┆                 ┆      ┆        ┆      ┆         │
╞════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37287              ┆ 217             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ plusPlusI          ┆ 1989            ┆ 1989 ┆ 1989   ┆ 1989 ┆ 1       │
╰────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭────────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ Contract3 contract     ┆                 ┆      ┆        ┆      ┆         │
╞════════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost        ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 42693                  ┆ 244             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name          ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ safeUncheckedPlusPlusI ┆ 1355            ┆ 1355 ┆ 1355   ┆ 1355 ┆ 1       │
╰────────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ Contract2 contract ┆                 ┆      ┆        ┆      ┆         │
╞════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 35887              ┆ 210             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ uncheckedPlusPlusI ┆ 1329            ┆ 1329 ┆ 1329   ┆ 1329 ┆ 1       │
╰────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract4 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 26881              ┆ 164             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ inlineAssemblyLoop ┆ 709             ┆ 709 ┆ 709    ┆ 709 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```
 
 </details> 
 

File:ConveyorRouterV1.sol 
```solidity
404:            tempAffiliateNonce++;
``` 



File:ConveyorRouterV1.sol 
```solidity
420:            tempReferrerNonce++;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1121:        --totalOrdersPerAddress[order.owner];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
542:        --totalOrdersPerAddress[msg.sender];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
415:            ++totalOrdersPerAddress[msg.sender];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
992:                ++offset;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
831:                ++orderIdIndex;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1234:                ++orderIdIndex;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1098:        --totalOrdersPerAddress[order.owner];
``` 



File:LimitOrderBook.sol 
```solidity
524:        --totalOrdersPerAddress[order.owner];
``` 



File:LimitOrderBook.sol 
```solidity
598:                ++orderIdIndex;
``` 



File:LimitOrderBook.sol 
```solidity
502:        --totalOrdersPerAddress[order.owner];
``` 



File:LimitOrderBook.sol 
```solidity
338:            ++totalOrdersPerAddress[msg.sender];
``` 



File:LimitOrderBook.sol 
```solidity
467:        --totalOrdersPerAddress[msg.sender];
``` 



File:LimitOrderSwapRouter.sol 
```solidity
127:        for (uint256 i = 0; i < _dexFactories.length; ++i) {
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-7]></a> [G-7] 
 <h3> Use `calldata` instead of `memory` for function arguments that do not get mutated. - Instances: 5 </h3> 
 </summary>
 
 
> Mark data types as `calldata` instead of `memory` where possible. This makes it so that the data is not automatically loaded into memory. If the data passed into the function does not need to be changed (like updating values in an array), it can be passed in as `calldata`. The one exception to this is if the argument must later be passed into another function that takes an argument that specifies `memory` storage. 
 
#### Gas Report - Savings: ~1716 
 <details>  
 <summary>  
  </summary> 
 

```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    Contract2 c2;
    Contract3 c3;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        c2 = new Contract2();
        c3 = new Contract3();
    }

    function testGas() public {
        uint256[] memory arr = new uint256[](10);
        c0.calldataArray(arr);
        c1.memoryArray(arr);

        bytes memory data = abi.encode("someText");
        c2.calldataBytes(data);
        c3.memoryBytes(data);
    }
}

contract Contract0 {
    function calldataArray(uint256[] calldata arr) public {
        uint256 j;
        for (uint256 i; i < arr.length; i++) {
            j = arr[i] + 10;
        }
    }
}

contract Contract1 {
    function memoryArray(uint256[] memory arr) public {
        uint256 j;
        for (uint256 i; i < arr.length; i++) {
            j = arr[i] + 10;
        }
    }
}

contract Contract2 {
    function calldataBytes(bytes calldata data) public {
        bytes32 val;
        for (uint256 i; i < 10; i++) {
            val = keccak256(abi.encode(data, i));
        }
    }
}

contract Contract3 {
    function memoryBytes(bytes memory data) public {
        bytes32 val;
        for (uint256 i; i < 10; i++) {
            val = keccak256(abi.encode(data, i));
        }
    }
}
```

### Gas Report
```solidity
╭───────────────────────────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ src/test/GasTest.t.sol:Contract0 contract ┆                 ┆      ┆        ┆      ┆         │
╞═══════════════════════════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 97947                                     ┆ 521             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ calldataArray                             ┆ 2824            ┆ 2824 ┆ 2824   ┆ 2824 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ src/test/GasTest.t.sol:Contract1 contract ┆                 ┆      ┆        ┆      ┆         │
╞═══════════════════════════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 128171                                    ┆ 672             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ memoryArray                               ┆ 3755            ┆ 3755 ┆ 3755   ┆ 3755 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ src/test/GasTest.t.sol:Contract2 contract ┆                 ┆      ┆        ┆      ┆         │
╞═══════════════════════════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 100547                                    ┆ 534             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ calldataBytes                             ┆ 4934            ┆ 4934 ┆ 4934   ┆ 4934 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ src/test/GasTest.t.sol:Contract3 contract ┆                 ┆      ┆        ┆      ┆         │
╞═══════════════════════════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 135183                                    ┆ 707             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ memoryBytes                               ┆ 7551            ┆ 7551 ┆ 7551   ┆ 7551 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯

```
         
 </details> 
 

File:ConveyorRouterV1.sol 
```solidity
386:    function upgradeMulticall(bytes memory bytecode, bytes32 salt) external payable onlyOwner returns (address) {
``` 



File:LimitOrderQuoter.sol 
```solidity
294:        LimitOrderSwapRouter.TokenToTokenExecutionPrice memory executionPrice
295:    ) internal returns (LimitOrderSwapRouter.TokenToTokenExecutionPrice memory) {
``` 



File:LimitOrderQuoter.sol 
```solidity
325:        LimitOrderSwapRouter.TokenToTokenExecutionPrice memory executionPrice
326:    ) internal returns (uint256 newSpotPriceA, uint128 newReserveAToken, uint128 newReserveAWeth, uint128 amountOut) {
``` 



File:LimitOrderQuoter.sol 
```solidity
342:        LimitOrderSwapRouter.TokenToTokenExecutionPrice memory executionPrice
343:    ) internal returns (LimitOrderSwapRouter.TokenToTokenExecutionPrice memory) {
``` 



File:LimitOrderQuoter.sol 
```solidity
370:        LimitOrderSwapRouter.TokenToTokenExecutionPrice memory executionPrice
371:    ) internal returns (uint256 newSpotPriceB, uint128 newReserveBWeth, uint128 newReserveBToken) {
``` 



File:LimitOrderQuoter.sol 
```solidity
466:        LimitOrderSwapRouter.TokenToWethExecutionPrice memory executionPrice
467:    ) external returns (LimitOrderSwapRouter.TokenToWethExecutionPrice memory) {
``` 



File:LimitOrderRouter.sol 
```solidity
110:    function _refreshLimitOrder(LimitOrder memory order) internal returns (uint256 executorFee) {
``` 



File:LimitOrderRouter.sol 
```solidity
177:    function _cancelLimitOrderViaExecutor(LimitOrder memory order) internal returns (uint256) {
``` 



File:LimitOrderRouter.sol 
```solidity
208:    function _validateOrderSequencing(LimitOrder[] memory orders) internal pure {
``` 



File:ConveyorExecutor.sol 
```solidity
219:        LimitOrderSwapRouter.TokenToWethExecutionPrice memory executionPrice
220:    ) internal returns (uint256, uint256) {
``` 



File:ConveyorExecutor.sol 
```solidity
343:        TokenToTokenExecutionPrice memory executionPrice
344:    ) internal returns (uint256, uint256) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
587:    function _cancelSandboxLimitOrderViaExecutor(SandboxLimitOrder memory order)
``` 



File:SandboxLimitOrderBook.sol 
```solidity
654:    function _refreshSandboxLimitOrder(SandboxLimitOrder memory order) internal returns (uint256) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
808:        PreSandboxExecutionState memory preSandboxExecutionState
809:    ) internal returns (uint256 cumulativeExecutionCreditCompensation) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
846:        SandboxLimitOrder memory currentOrder,
``` 



File:SandboxLimitOrderBook.sol 
```solidity
903:        PreSandboxExecutionState memory preSandboxExecutionState
904:    ) internal returns (uint256 cumulativeExecutionCompensation) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
902:        uint128[] memory fillAmounts,
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1005:        uint128[] memory fillAmounts,
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1003:        SandboxLimitOrder memory prevOrder,
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-8]></a> [G-8] 
 <h3> Use multiple require() statments insted of require(expression && expression && ...) - Instances: 2 </h3> 
 </summary>
 
 
> You can safe gas by breaking up a require statement with multiple conditions, into multiple require statements with a single condition. 
 
#### Gas Report - Savings: ~16 
 <details>  
 <summary>  
  </summary> 
 
        
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
    }

    function testGas() public {
        c0.singleRequire(3);
        c1.multipleRequire(3);
    }
}

contract Contract0 {
    function singleRequire(uint256 num) public {
        require(num > 1 && num < 10 && num == 3);
    }
}

contract Contract1 {
    function multipleRequire(uint256 num) public {
        require(num > 1);
        require(num < 10);
        require(num == 3);
    }
}

```


```solidity
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 35487              ┆ 208             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ singleRequire      ┆ 286             ┆ 286 ┆ 286    ┆ 286 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 35887              ┆ 210             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ multipleRequire    ┆ 270             ┆ 270 ┆ 270    ┆ 270 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```

 
 </details> 
 

File:ConveyorMath.sol 
```solidity
53:            require(answer >= 0x0 && answer <= MAX_64x64);
``` 



File:ConveyorMath.sol 
```solidity
86:            require(result >= MIN_64x64 && result <= type(int128).max);
``` 



File:OracleLibraryV2.sol 
```solidity
10:        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-9]></a> [G-9] 
 <h3> Optimal Comparison - Instances: 6 </h3> 
 </summary>
 
 
> When comparing integers, it is cheaper to use strict `>` & `<` operators over `>=` & `<=` operators, even if you must increment or decrement one of the operands. 
 Note: before using this technique, it's important to consider whether incrementing/decrementing one of the operators could result in an over/underflow. This optimization is applicable when the optimizer is turned off. 
 
#### Gas Report - Savings: ~3 
 <details>  
 <summary>  
  </summary> 
 
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    Contract2 c2;
    Contract3 c3;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        c2 = new Contract2();
        c3 = new Contract3();
    }

    function testGas() public view {
        c0.gte();
        c1.gtPlusMinusOne();
        c2.lte();
        c3.ltPlusOne();
    }
}

contract Contract0 {
    function gte() external pure returns (bool) {
        return 2 >= 2;
    }
}

contract Contract1 {
    function gtPlusMinusOne() external pure returns (bool) {
        return 2 > 2 - 1;
    }
}

contract Contract2 {
    function lte() external pure returns (bool) {
        return 2 <= 2;
    }
}

contract Contract3 {
    function ltPlusOne() external pure returns (bool) {
        return 2 < 2 + 1;
    }
}

```


```solidity
╭───────────────────────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ src/test/GasTest.t.sol:Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37487                                     ┆ 218             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ gte                                       ┆ 330             ┆ 330 ┆ 330    ┆ 330 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ src/test/GasTest.t.sol:Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37487                                     ┆ 218             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ gtPlusMinusOne                            ┆ 327             ┆ 327 ┆ 327    ┆ 327 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ src/test/GasTest.t.sol:Contract2 contract ┆                 ┆     ┆        ┆     ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37487                                     ┆ 218             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ lte                                       ┆ 330             ┆ 330 ┆ 330    ┆ 330 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ src/test/GasTest.t.sol:Contract3 contract ┆                 ┆     ┆        ┆     ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37487                                     ┆ 218             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ ltPlusOne                                 ┆ 327             ┆ 327 ┆ 327    ┆ 327 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```

 
 </details> 
 

File:ConveyorTickMath.sol 
```solidity
90:            require(priceX128 <= type(uint256).max, "Overflow");
``` 



File:ConveyorMath.sol 
```solidity
22:            require(x <= MAX_UINT64);
``` 



File:ConveyorMath.sol 
```solidity
41:            require(x <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
``` 



File:ConveyorMath.sol 
```solidity
53:            require(answer >= 0x0 && answer <= MAX_64x64);
``` 



File:ConveyorMath.sol 
```solidity
53:            require(answer >= 0x0 && answer <= MAX_64x64);
``` 



File:ConveyorMath.sol 
```solidity
74:            require(answer <= MAX_64x64);
``` 



File:ConveyorMath.sol 
```solidity
86:            require(result >= MIN_64x64 && result <= type(int128).max);
``` 



File:ConveyorMath.sol 
```solidity
86:            require(result >= MIN_64x64 && result <= type(int128).max);
``` 



File:ConveyorMath.sol 
```solidity
118:            require(answer <= MAX_64x64);
``` 



File:ConveyorMath.sol 
```solidity
149:            require(hi <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
``` 



File:ConveyorMath.sol 
```solidity
152:            require(hi <= MAX_128x128 - lo);
``` 



File:ConveyorMath.sol 
```solidity
188:            require(answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
``` 



File:ConveyorMath.sol 
```solidity
207:            require(hi <= MAX_128x128 - lo);
``` 



File:ConveyorMath.sol 
```solidity
220:            require(answer <= uint128(MAX_64x64), "overflow");
``` 



File:ConveyorMath.sol 
```solidity
235:            if (x <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF) {
``` 



File:ConveyorMath.sol 
```solidity
240:                if (xc >= 0x100000000) {
``` 



File:ConveyorMath.sol 
```solidity
244:                if (xc >= 0x10000) {
``` 



File:ConveyorMath.sol 
```solidity
248:                if (xc >= 0x100) {
``` 



File:ConveyorMath.sol 
```solidity
252:                if (xc >= 0x10) {
``` 



File:ConveyorMath.sol 
```solidity
256:                if (xc >= 0x4) {
``` 



File:ConveyorMath.sol 
```solidity
260:                if (xc >= 0x2) msb += 1; // No need to shift xc anymore
``` 



File:ConveyorMath.sol 
```solidity
263:                require(answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, "overflow in divuu");
``` 



File:ConveyorMath.sol 
```solidity
282:            require(answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, "overflow in divuu last");
``` 



File:ConveyorMath.sol 
```solidity
497:            require(answer <= uint256(MAX_64x64));
``` 



File:ConveyorMath.sol 
```solidity
524:                if (xx >= 0x100000000000000000000000000000000) {
``` 



File:ConveyorMath.sol 
```solidity
528:                if (xx >= 0x10000000000000000) {
``` 



File:ConveyorMath.sol 
```solidity
532:                if (xx >= 0x100000000) {
``` 



File:ConveyorMath.sol 
```solidity
536:                if (xx >= 0x10000) {
``` 



File:ConveyorMath.sol 
```solidity
540:                if (xx >= 0x100) {
``` 



File:ConveyorMath.sol 
```solidity
544:                if (xx >= 0x10) {
``` 



File:ConveyorMath.sol 
```solidity
548:                if (xx >= 0x8) {
``` 



File:LimitOrderQuoter.sol 
```solidity
275:            uint128 amountIn = tokenInDecimals <= 18
276:                ? uint128(alphaX * 10 ** (18 - tokenInDecimals))
``` 



File:LimitOrderQuoter.sol 
```solidity
479:        uint128 amountIn = tokenInDecimals <= 18
480:            ? uint128(alphaX * 10 ** (18 - tokenInDecimals))
``` 



File:SandboxLimitOrderBook.sol 
```solidity
348:                        relativeWethValue = tokenInDecimals <= 18
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
``` 



File:LimitOrderSwapRouter.sol 
```solidity
186:        if (amountInUSDCDollarValue >= 1000000) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
196:        if (exponent >= 0x400000000000000000) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
473:        uint128 commonReserve0 = token0Decimals <= 18
474:            ? uint128(reserve0 * (10 ** (18 - token0Decimals)))
``` 



File:LimitOrderSwapRouter.sol 
```solidity
476:        uint128 commonReserve1 = token1Decimals <= 18
477:            ? uint128(reserve1 * (10 ** (18 - token1Decimals)))
``` 



File:ConveyorFeeMath.sol 
```solidity
30:        if (percentFee <= ZERO_POINT_ZERO_ZERO_FIVE) {
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-10]></a> [G-10] 
 <h3> Tightly pack storage variables - Instances: 4 </h3> 
 </summary>
 
 
> When defining storage variables, make sure to declare them in ascending order, according to size. When multiple variables are able to fit into one 256 bit slot, this will save storage size and gas during runtime. For example, if you have a `bool`, `uint256` and a `bool`, instead of defining the variables in the previously mentioned order, defining the two boolean variables first will pack them both into one storage slot since they only take up one byte of storage. 
 
#### Gas Report - Savings: ~0 
 <details>  
 <summary>  
  </summary> 
 

```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
    }

    function testGas() public {
        bool bool0 = true;
        bool bool1 = false;
        uint256 num0 = 200;
        uint256 num1 = 100;
        c0.accessNonTightlyPacked(bool0, bool1, num0, num1);
        c1.accessTightlyPacked(bool0, bool1, num0, num1);
    }
}

contract Contract0 {
    uint256 num0 = 100;
    bool bool0 = false;
    uint256 num1 = 200;
    bool bool1 = true;

    function accessNonTightlyPacked(
        bool _bool0,
        bool _bool1,
        uint256 _num0,
        uint256 _num1
    ) public {
        bool0 = _bool0;
        bool1 = _bool1;
        num0 = _num0;
        num1 = _num1;
    }
}

contract Contract1 {
    bool bool0 = false;
    bool bool1 = true;
    uint256 num0 = 100;
    uint256 num1 = 200;

    function accessTightlyPacked(
        bool _bool0,
        bool _bool1,
        uint256 _num0,
        uint256 _num1
    ) public {
        bool0 = _bool0;
        bool1 = _bool1;
        num0 = _num0;
        num1 = _num1;
    }
}

```

```solidity
╭───────────────────────────────────────────┬─────────────────┬───────┬────────┬───────┬─────────╮
│ src/test/GasTest.t.sol:Contract0 contract ┆                 ┆       ┆        ┆       ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═══════╪════════╪═══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 122268                                    ┆ 334             ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg   ┆ median ┆ max   ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ accessNonTightlyPacked                    ┆ 32774           ┆ 32774 ┆ 32774  ┆ 32774 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴───────┴────────┴───────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬───────┬────────┬───────┬─────────╮
│ src/test/GasTest.t.sol:Contract1 contract ┆                 ┆       ┆        ┆       ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═══════╪════════╪═══════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 126247                                    ┆ 356             ┆       ┆        ┆       ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg   ┆ median ┆ max   ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ accessTightlyPacked                       ┆ 15476           ┆ 15476 ┆ 15476  ┆ 15476 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴───────┴────────┴───────┴─────────╯

```

 
 </details> 
 

File:ConveyorExecutor.sol 
```solidity
20:    address immutable WETH;
``` 



File:ConveyorMath.sol 
```solidity
7:    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
83:    uint256 uniV3AmountOut;
``` 



File:LimitOrderBook.sol 
```solidity
13:    address immutable LIMIT_ORDER_EXECUTOR;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-11]></a> [G-11] 
 <h3> Mark functions as payable (with discretion) - Instances: 44 </h3> 
 </summary>
 
 
> You can mark public or external functions as payable to save gas. Functions that are not payable have additional logic to check if there was a value sent with a call, however, making a function payable eliminates this check. This optimization should be carefully considered due to potentially unwanted behavior when a function does not need to accept ether. 
 
#### Gas Report - Savings: ~24 
 <details>  
 <summary>  
  </summary> 
 

```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
    }

    function testGas() public {
        c0.isNotPayable();
        c1.isPayable();
    }
}

contract Contract0 {
    function isNotPayable() public view {
        uint256 val = 0;
        val++;
    }
}

contract Contract1 {
    function isPayable() public payable {
        uint256 val = 0;
        val++;
    }
}
```

```solidity

╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 32081              ┆ 190             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ isNotPayable       ┆ 198             ┆ 198 ┆ 198    ┆ 198 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 29681              ┆ 178             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ isPayable          ┆ 174             ┆ 174 ┆ 174    ┆ 174 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```

 
 </details> 
 

File:DeployMainnetAggregator.s.sol 
```solidity
11:    function run() public returns (address conveyorRouterV1) {
``` 



File:PancakeV2Callback.sol 
```solidity
12:    function pancakeCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:UniFiCallback.sol 
```solidity
12:    function unifiCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:ConveyorFeeMath.sol 
```solidity
18:    function calculateReward(uint128 percentFee, uint128 wethValue)
19:        public
20:        pure
21:        returns (uint128 conveyorReward, uint128 beaconReward)
22:    {
``` 



File:BabyDogeCallback.sol 
```solidity
12:    function BabyDogeCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:PancakeV3Callback.sol 
```solidity
10:    function pancakeV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
``` 



File:DeployBaseAggregator.s.sol 
```solidity
11:    function run() public returns (address conveyorRouterV1) {
``` 



File:MeerkatCallback.sol 
```solidity
12:    function MeerkatCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:LimitOrderRouter.sol 
```solidity
77:    function refreshOrder(bytes32[] calldata orderIds) external nonReentrant {
``` 



File:LimitOrderRouter.sol 
```solidity
152:    function validateAndCancelOrder(bytes32 orderId) external nonReentrant returns (bool success) {
``` 



File:LimitOrderRouter.sol 
```solidity
265:    function executeLimitOrders(bytes32[] calldata orderIds) external nonReentrant onlyEOA {
``` 



File:LimitOrderRouter.sol 
```solidity
349:    function confirmTransferOwnership() external {
``` 



File:LimitOrderRouter.sol 
```solidity
358:    function transferOwnership(address newOwner) external onlyOwner {
``` 



File:LimitOrderRouter.sol 
```solidity
365:    function setMinExecutionCredit(uint256 newMinExecutionCredit) external onlyOwner {
``` 



File:DeployPolygonAggregator.s.sol 
```solidity
11:    function run() public returns (address conveyorRouterV1) {
``` 



File:ConveyorRouterV1.sol 
```solidity
360:    function withdraw() external onlyOwner {
``` 



File:ConveyorRouterV1.sol 
```solidity
366:    function confirmTransferOwnership() external {
``` 



File:ConveyorRouterV1.sol 
```solidity
377:    function transferOwnership(address newOwner) external onlyOwner {
``` 



File:ConveyorRouterV1.sol 
```solidity
399:    function initializeAffiliate(address affiliateAddress) external onlyOwner {
``` 



File:ConveyorRouterV1.sol 
```solidity
450:    function executeMulticall(ConveyorRouterV1.SwapAggregatorMulticall calldata multicall) external lock {
``` 



File:DeployBSCAggregator.s.sol 
```solidity
13:    function run() public returns (address conveyorRouterV1) {
``` 



File:TraderJoeCallback.sol 
```solidity
12:    function joeCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:LinkSwapCallback.sol 
```solidity
12:    function linkswapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:DeployAvalancheAggregator.s.sol 
```solidity
10:    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
60:    function executeSandboxMulticall(SandboxMulticall calldata sandboxMultiCall) external {
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
74:    function sandboxRouterCallback(SandboxMulticall calldata sandboxMulticall) external onlyLimitOrderExecutor {
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
95:    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
``` 



File:BiswapCallback.sol 
```solidity
12:    function BiswapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:ElkSwapCallback.sol 
```solidity
12:    function elkCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:KyberSwapV3Callback.sol 
```solidity
10:    function swapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
``` 



File:DeployTest.s.sol 
```solidity
13:    function run() public {
``` 



File:DeployFantomAggregator.s.sol 
```solidity
10:    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
``` 



File:ConvergenceXCallback.sol 
```solidity
12:    function swapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:UniswapV3Callback.sol 
```solidity
10:    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
``` 



File:VerseCallback.sol 
```solidity
12:    function swapsCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:CafeSwapCallback.sol 
```solidity
12:    function cafeCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:DXSwapCallback.sol 
```solidity
12:    function DXswapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:LimitOrderBook.sol 
```solidity
167:    function decreaseExecutionCredit(bytes32 orderId, uint128 amount) external nonReentrant {
``` 



File:LimitOrderBook.sol 
```solidity
223:    function getLimitOrderById(bytes32 orderId) public view returns (LimitOrder memory) {
``` 



File:LimitOrderBook.sol 
```solidity
448:    function cancelOrder(bytes32 orderId) public {
``` 



File:LimitOrderBook.sol 
```solidity
482:    function cancelOrders(bytes32[] calldata orderIds) public {
``` 



File:LimitOrderBook.sol 
```solidity
536:    function getTotalOrdersValue(address token) public view returns (uint256 totalOrderValue) {
``` 



File:LimitOrderBook.sol 
```solidity
559:    function getAllOrderIdsLength(address _owner) public view returns (uint256) {
``` 



File:LimitOrderBook.sol 
```solidity
569:    function getOrderIds(address _owner, OrderType targetOrderType, uint256 orderOffset, uint256 length)
570:        public
571:        view
572:        returns (bytes32[] memory)
573:    {
``` 



File:DeployArbitrumAggregator.s.sol 
```solidity
10:    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
``` 



File:LimitOrderQuoter.sol 
```solidity
49:    function findBestTokenToWethExecutionPrice(
50:        LimitOrderSwapRouter.TokenToWethExecutionPrice[] calldata executionPrices,
51:        bool buyOrder
52:    ) external pure returns (uint256 bestPriceIndex) {
``` 



File:LimitOrderQuoter.sol 
```solidity
94:    function findBestTokenToTokenExecutionPrice(
95:        LimitOrderSwapRouter.TokenToTokenExecutionPrice[] calldata executionPrices,
96:        bool buyOrder
97:    ) external pure returns (uint256 bestPriceIndex) {
``` 



File:LimitOrderQuoter.sol 
```solidity
134:    function initializeTokenToWethExecutionPrices(
135:        LimitOrderSwapRouter.SpotReserve[] calldata spotReserveAToWeth,
136:        address[] calldata lpAddressesAToWeth
137:    ) external pure returns (LimitOrderSwapRouter.TokenToWethExecutionPrice[] memory) {
``` 



File:LimitOrderQuoter.sol 
```solidity
170:    function initializeTokenToTokenExecutionPrices(
171:        address tokenIn,
172:        LimitOrderSwapRouter.SpotReserve[] calldata spotReserveAToWeth,
173:        address[] calldata lpAddressesAToWeth,
174:        LimitOrderSwapRouter.SpotReserve[] calldata spotReserveWethToB,
175:        address[] calldata lpAddressesWethToB
176:    ) external view returns (LimitOrderSwapRouter.TokenToTokenExecutionPrice[] memory) {
``` 



File:LimitOrderQuoter.sol 
```solidity
248:    function simulateTokenToTokenPriceChange(
249:        uint128 alphaX,
250:        LimitOrderSwapRouter.TokenToTokenExecutionPrice memory executionPrice
251:    ) external returns (LimitOrderSwapRouter.TokenToTokenExecutionPrice memory) {
``` 



File:LimitOrderQuoter.sol 
```solidity
464:    function simulateTokenToWethPriceChange(
465:        uint128 alphaX,
466:        LimitOrderSwapRouter.TokenToWethExecutionPrice memory executionPrice
467:    ) external returns (LimitOrderSwapRouter.TokenToWethExecutionPrice memory) {
``` 



File:LimitOrderQuoter.sol 
```solidity
548:    function calculateAmountOutMinAToWeth(
549:        address lpAddressAToWeth,
550:        uint256 amountInOrder,
551:        uint16 taxIn,
552:        uint24 feeIn,
553:        address tokenIn
554:    ) external returns (uint256 amountOutMinAToWeth) {
``` 



File:SakeSwapCallback.sol 
```solidity
12:    function SakeSwapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
171:    function calculateFee(uint128 amountIn, address usdc, address weth) public view returns (uint128) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
363:    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
576:    function getAllPrices(address token0, address token1, uint24 FEE)
577:        public
578:        view
579:        returns (SpotReserve[] memory prices, address[] memory lps)
580:    {
``` 



File:JetSwapCallback.sol 
```solidity
12:    function jetswapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:AlgebraCallback.sol 
```solidity
10:    function algebraSwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external {
``` 



File:ApeSwapCallback.sol 
```solidity
12:    function apeCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:DystopiaCallback.sol 
```solidity
12:    function hook(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
237:    function decreaseExecutionCredit(bytes32 orderId, uint128 amount) external nonReentrant {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
510:    function cancelOrders(bytes32[] calldata orderIds) public {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
523:    function cancelOrder(bytes32 orderId) public {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
559:    function validateAndCancelOrder(bytes32 orderId) external nonReentrant returns (bool success) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
619:    function refreshOrder(bytes32[] calldata orderIds) external nonReentrant {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
702:    function executeOrdersViaSandboxMulticall(SandboxLimitOrderRouter.SandboxMulticall calldata sandboxMulticall)
703:        external
704:        onlySandboxLimitOrderRouter
705:        nonReentrant
706:    {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1177:    function getTotalOrdersValue(address token) public view returns (uint256 totalOrderValue) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1182:    function getAllOrderIdsLength(address orderOwner) public view returns (uint256) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1186:    function getSandboxLimitOrderRouterAddress() public view returns (address) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1190:    function getSandboxLimitOrderById(bytes32 orderId) public view returns (SandboxLimitOrder memory) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1205:    function getOrderIds(address orderOwner, OrderType targetOrderType, uint256 orderOffset, uint256 length)
1206:        public
1207:        view
1208:        returns (bytes32[] memory)
1209:    {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1250:    function setMinExecutionCredit(uint256 newMinExecutionCredit) external onlyOwner {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1257:    function confirmTransferOwnership() external {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1266:    function transferOwnership(address newOwner) external onlyOwner {
``` 



File:DefiSwapCallback.sol 
```solidity
12:    function croDefiSwapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:BabySwapCallback.sol 
```solidity
12:    function babyCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:DeployOptimismAggregator.s.sol 
```solidity
10:    function run() public returns (ConveyorRouterV1 conveyorRouterV1) {
``` 



File:ConveyorExecutor.sol 
```solidity
153:    function checkIn() external {
``` 



File:ConveyorExecutor.sol 
```solidity
161:    function executeTokenToWethOrders(LimitOrderBook.LimitOrder[] calldata orders)
162:        external
163:        onlyLimitOrderRouter
164:        returns (uint256, uint256)
165:    {
``` 



File:ConveyorExecutor.sol 
```solidity
276:    function executeTokenToTokenOrders(LimitOrderBook.LimitOrder[] calldata orders)
277:        external
278:        onlyLimitOrderRouter
279:        returns (uint256, uint256)
280:    {
``` 



File:ConveyorExecutor.sol 
```solidity
418:    function executeSandboxLimitOrders(
419:        SandboxLimitOrderBook.SandboxLimitOrder[] calldata orders,
420:        SandboxLimitOrderRouter.SandboxMulticall calldata sandboxMulticall
421:    ) external onlySandboxLimitOrderBook nonReentrant {
``` 



File:ConveyorExecutor.sol 
```solidity
506:    function withdrawConveyorFees() external nonReentrant onlyOwner {
``` 



File:ConveyorExecutor.sol 
```solidity
517:    function confirmTransferOwnership() external {
``` 



File:ConveyorExecutor.sol 
```solidity
528:    function transferOwnership(address newOwner) external onlyOwner {
``` 



File:MdexSwapCallback.sol 
```solidity
12:    function swapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:UniswapV2Callback.sol 
```solidity
12:    function uniswapV2Call(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:WaultSwapCallback.sol 
```solidity
12:    function waultSwapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 



File:NomiswapCallback.sol 
```solidity
12:    function nomiswapCall(address, uint256 amount0, uint256 amount1, bytes calldata data) external {
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-12]></a> [G-12] 
 <h3> Consider marking constants as private - Instances: 14 </h3> 
 </summary>
 
 
> Consider marking constant variables in storage as private to save gas (unless a constant variable should be easily accessible by another protocol or offchain logic). 
 #### Gas Report - Savings: ~22 
 <details>  
 <summary>  
  </summary> 
 
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    
    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        
    }
    function testGas() public view {
        uint256 a = 100;
        c0.addPublicConstant(a);
        c1.addPrivateConstant(a);
        
    }
}
contract Contract0 {

    uint256 constant public x = 100;

    function addPublicConstant(uint256 a) external pure returns (uint256) {
        return a + x;
    }
}

contract Contract1 {

        uint256 constant private x = 100;

    function addPrivateConstant(uint256 a) external pure returns (uint256) {
        return a +x;
    }
}
```


```solidity

╭───────────────────────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ src/test/GasTest.t.sol:Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 92741                                     ┆ 495             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addPublicConstant                         ┆ 790             ┆ 790 ┆ 790    ┆ 790 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭───────────────────────────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ src/test/GasTest.t.sol:Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞═══════════════════════════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost                           ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 83535                                     ┆ 449             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name                             ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addPrivateConstant                        ┆ 768             ┆ 768 ┆ 768    ┆ 768 ┆ 1       │
╰───────────────────────────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```
             
 </details> 
 

File:SandboxLimitOrderBook.sol 
```solidity
41:    uint256 public constant CHECK_IN_INTERVAL = 1 days;
``` 



File:DeployArbitrumAggregator.s.sol 
```solidity
8:    address constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
``` 



File:LimitOrderBook.sol 
```solidity
19:    uint256 public constant CHECK_IN_INTERVAL = 1 days;
``` 



File:DeployFantomAggregator.s.sol 
```solidity
8:    address constant WFTM = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83;
``` 



File:DeployPolygonAggregator.s.sol 
```solidity
9:    address constant WMATIC = 0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270;
``` 



File:DeployOptimismAggregator.s.sol 
```solidity
8:    address constant WETH = 0x4200000000000000000000000000000000000006;
``` 



File:DeployBSCAggregator.s.sol 
```solidity
11:    address constant WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
``` 



File:ConveyorFeeMath.sol 
```solidity
8:    uint128 constant ZERO_POINT_ZERO_ZERO_FIVE = 92233720368547760;
``` 



File:ConveyorFeeMath.sol 
```solidity
9:    uint128 constant ZERO_POINT_ZERO_ZERO_ONE = 18446744073709550;
``` 



File:ConveyorFeeMath.sol 
```solidity
10:    uint128 constant MAX_CONVEYOR_PERCENT = 110680464442257300 * 10 ** 2;
``` 



File:ConveyorFeeMath.sol 
```solidity
11:    uint128 constant MIN_CONVEYOR_PERCENT = 7378697629483821000;
``` 



File:DeployTest.s.sol 
```solidity
11:    address constant GOERLI_WETH = 0xdD69DB25F6D620A7baD3023c5d32761D353D3De9;
``` 



File:ConveyorTickMath.sol 
```solidity
28:    uint256 internal constant Q96 = 0x1000000000000000000000000;
``` 



File:DeployAvalancheAggregator.s.sol 
```solidity
8:    address constant WAVAX = 0xB31f66AA3C1e785363F0875A1B74E27b85FD66c7;
``` 



File:DeployMainnetAggregator.s.sol 
```solidity
9:    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
21:    uint256 public constant CHECK_IN_INTERVAL = 1 days;
``` 



File:DeployBaseAggregator.s.sol 
```solidity
9:    address constant WETH = 0x4200000000000000000000000000000000000006;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-13]></a> [G-13] 
 <h3> Avoid Reading From Storage in a for loop - Instances: 3 </h3> 
 </summary>
 
  
  - Savings: ~0 
 <details>  
 <summary>  
  </summary> 
  
 </details> 
 

File:LimitOrderBook.sol 
```solidity
280:        for (uint256 i = 0; i < orderGroup.length;) {
281:            ///@notice Get the order details from the orderGroup.
282:            LimitOrder memory newOrder = orderGroup[i];
283:
284:            if (newOrder.quantity == 0) {
285:                revert OrderQuantityIsZero();
286:            }
287:
288:            ///@notice Increment the total value of orders by the quantity of the new order
289:            updatedTotalOrdersValue += newOrder.quantity;
290:
291:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
292:            if (!(orderToken == newOrder.tokenIn)) {
293:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
294:            }
295:
296:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
297:            if (newOrder.tokenOut == newOrder.tokenIn) {
298:                revert TokenInIsTokenOut();
299:            }
300:
301:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
302:            if (tokenBalance < updatedTotalOrdersValue) {
303:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
304:            }
305:
306:            ///@notice Create a new orderId from the orderNonce and current block timestamp
307:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
308:
309:            ///@notice Increment the cumulative execution credit by the current orders execution.
310:            cumulativeExecutionCredit += newOrder.executionCredit;
311:
312:            ///@notice increment the orderNonce
313:            /**
314:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
315:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
316:             */
317:            unchecked {
318:                orderNonce += 2;
319:            }
320:
321:            ///@notice Set the new order's owner to the msg.sender
322:            newOrder.owner = msg.sender;
323:
324:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
325:            newOrder.orderId = orderId;
326:
327:            ///@notice update the newOrder's last refresh timestamp
328:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
329:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
330:
331:            ///@notice Add the newly created order to the orderIdToOrder mapping
332:            orderIdToLimitOrder[orderId] = newOrder;
333:
334:            ///@notice Add the orderId to the addressToOrderIds mapping
335:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingLimitOrder;
336:
337:            ///@notice Increment the total orders per address for the msg.sender
338:            ++totalOrdersPerAddress[msg.sender];
339:
340:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
341:            orderIds[i] = orderId;
342:
343:            ///@notice Add the orderId to the addressToAllOrderIds structure
344:            addressToAllOrderIds[msg.sender].push(orderId);
345:
346:            unchecked {
347:                ++i;
348:            }
349:        }
350:
``` 



File:LimitOrderBook.sol 
```solidity
280:        for (uint256 i = 0; i < orderGroup.length;) {
281:            ///@notice Get the order details from the orderGroup.
282:            LimitOrder memory newOrder = orderGroup[i];
283:
284:            if (newOrder.quantity == 0) {
285:                revert OrderQuantityIsZero();
286:            }
287:
288:            ///@notice Increment the total value of orders by the quantity of the new order
289:            updatedTotalOrdersValue += newOrder.quantity;
290:
291:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
292:            if (!(orderToken == newOrder.tokenIn)) {
293:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
294:            }
295:
296:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
297:            if (newOrder.tokenOut == newOrder.tokenIn) {
298:                revert TokenInIsTokenOut();
299:            }
300:
301:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
302:            if (tokenBalance < updatedTotalOrdersValue) {
303:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
304:            }
305:
306:            ///@notice Create a new orderId from the orderNonce and current block timestamp
307:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
308:
309:            ///@notice Increment the cumulative execution credit by the current orders execution.
310:            cumulativeExecutionCredit += newOrder.executionCredit;
311:
312:            ///@notice increment the orderNonce
313:            /**
314:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
315:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
316:             */
317:            unchecked {
318:                orderNonce += 2;
319:            }
320:
321:            ///@notice Set the new order's owner to the msg.sender
322:            newOrder.owner = msg.sender;
323:
324:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
325:            newOrder.orderId = orderId;
326:
327:            ///@notice update the newOrder's last refresh timestamp
328:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
329:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
330:
331:            ///@notice Add the newly created order to the orderIdToOrder mapping
332:            orderIdToLimitOrder[orderId] = newOrder;
333:
334:            ///@notice Add the orderId to the addressToOrderIds mapping
335:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingLimitOrder;
336:
337:            ///@notice Increment the total orders per address for the msg.sender
338:            ++totalOrdersPerAddress[msg.sender];
339:
340:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
341:            orderIds[i] = orderId;
342:
343:            ///@notice Add the orderId to the addressToAllOrderIds structure
344:            addressToAllOrderIds[msg.sender].push(orderId);
345:
346:            unchecked {
347:                ++i;
348:            }
349:        }
350:
``` 



File:LimitOrderBook.sol 
```solidity
280:        for (uint256 i = 0; i < orderGroup.length;) {
281:            ///@notice Get the order details from the orderGroup.
282:            LimitOrder memory newOrder = orderGroup[i];
283:
284:            if (newOrder.quantity == 0) {
285:                revert OrderQuantityIsZero();
286:            }
287:
288:            ///@notice Increment the total value of orders by the quantity of the new order
289:            updatedTotalOrdersValue += newOrder.quantity;
290:
291:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
292:            if (!(orderToken == newOrder.tokenIn)) {
293:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
294:            }
295:
296:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
297:            if (newOrder.tokenOut == newOrder.tokenIn) {
298:                revert TokenInIsTokenOut();
299:            }
300:
301:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
302:            if (tokenBalance < updatedTotalOrdersValue) {
303:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
304:            }
305:
306:            ///@notice Create a new orderId from the orderNonce and current block timestamp
307:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
308:
309:            ///@notice Increment the cumulative execution credit by the current orders execution.
310:            cumulativeExecutionCredit += newOrder.executionCredit;
311:
312:            ///@notice increment the orderNonce
313:            /**
314:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
315:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
316:             */
317:            unchecked {
318:                orderNonce += 2;
319:            }
320:
321:            ///@notice Set the new order's owner to the msg.sender
322:            newOrder.owner = msg.sender;
323:
324:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
325:            newOrder.orderId = orderId;
326:
327:            ///@notice update the newOrder's last refresh timestamp
328:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
329:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
330:
331:            ///@notice Add the newly created order to the orderIdToOrder mapping
332:            orderIdToLimitOrder[orderId] = newOrder;
333:
334:            ///@notice Add the orderId to the addressToOrderIds mapping
335:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingLimitOrder;
336:
337:            ///@notice Increment the total orders per address for the msg.sender
338:            ++totalOrdersPerAddress[msg.sender];
339:
340:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
341:            orderIds[i] = orderId;
342:
343:            ///@notice Add the orderId to the addressToAllOrderIds structure
344:            addressToAllOrderIds[msg.sender].push(orderId);
345:
346:            unchecked {
347:                ++i;
348:            }
349:        }
350:
``` 



File:LimitOrderBook.sol 
```solidity
280:        for (uint256 i = 0; i < orderGroup.length;) {
281:            ///@notice Get the order details from the orderGroup.
282:            LimitOrder memory newOrder = orderGroup[i];
283:
284:            if (newOrder.quantity == 0) {
285:                revert OrderQuantityIsZero();
286:            }
287:
288:            ///@notice Increment the total value of orders by the quantity of the new order
289:            updatedTotalOrdersValue += newOrder.quantity;
290:
291:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
292:            if (!(orderToken == newOrder.tokenIn)) {
293:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
294:            }
295:
296:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
297:            if (newOrder.tokenOut == newOrder.tokenIn) {
298:                revert TokenInIsTokenOut();
299:            }
300:
301:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
302:            if (tokenBalance < updatedTotalOrdersValue) {
303:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
304:            }
305:
306:            ///@notice Create a new orderId from the orderNonce and current block timestamp
307:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
308:
309:            ///@notice Increment the cumulative execution credit by the current orders execution.
310:            cumulativeExecutionCredit += newOrder.executionCredit;
311:
312:            ///@notice increment the orderNonce
313:            /**
314:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
315:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
316:             */
317:            unchecked {
318:                orderNonce += 2;
319:            }
320:
321:            ///@notice Set the new order's owner to the msg.sender
322:            newOrder.owner = msg.sender;
323:
324:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
325:            newOrder.orderId = orderId;
326:
327:            ///@notice update the newOrder's last refresh timestamp
328:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
329:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
330:
331:            ///@notice Add the newly created order to the orderIdToOrder mapping
332:            orderIdToLimitOrder[orderId] = newOrder;
333:
334:            ///@notice Add the orderId to the addressToOrderIds mapping
335:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingLimitOrder;
336:
337:            ///@notice Increment the total orders per address for the msg.sender
338:            ++totalOrdersPerAddress[msg.sender];
339:
340:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
341:            orderIds[i] = orderId;
342:
343:            ///@notice Add the orderId to the addressToAllOrderIds structure
344:            addressToAllOrderIds[msg.sender].push(orderId);
345:
346:            unchecked {
347:                ++i;
348:            }
349:        }
350:
``` 



File:LimitOrderBook.sol 
```solidity
280:        for (uint256 i = 0; i < orderGroup.length;) {
281:            ///@notice Get the order details from the orderGroup.
282:            LimitOrder memory newOrder = orderGroup[i];
283:
284:            if (newOrder.quantity == 0) {
285:                revert OrderQuantityIsZero();
286:            }
287:
288:            ///@notice Increment the total value of orders by the quantity of the new order
289:            updatedTotalOrdersValue += newOrder.quantity;
290:
291:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
292:            if (!(orderToken == newOrder.tokenIn)) {
293:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
294:            }
295:
296:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
297:            if (newOrder.tokenOut == newOrder.tokenIn) {
298:                revert TokenInIsTokenOut();
299:            }
300:
301:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
302:            if (tokenBalance < updatedTotalOrdersValue) {
303:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
304:            }
305:
306:            ///@notice Create a new orderId from the orderNonce and current block timestamp
307:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
308:
309:            ///@notice Increment the cumulative execution credit by the current orders execution.
310:            cumulativeExecutionCredit += newOrder.executionCredit;
311:
312:            ///@notice increment the orderNonce
313:            /**
314:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
315:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
316:             */
317:            unchecked {
318:                orderNonce += 2;
319:            }
320:
321:            ///@notice Set the new order's owner to the msg.sender
322:            newOrder.owner = msg.sender;
323:
324:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
325:            newOrder.orderId = orderId;
326:
327:            ///@notice update the newOrder's last refresh timestamp
328:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
329:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
330:
331:            ///@notice Add the newly created order to the orderIdToOrder mapping
332:            orderIdToLimitOrder[orderId] = newOrder;
333:
334:            ///@notice Add the orderId to the addressToOrderIds mapping
335:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingLimitOrder;
336:
337:            ///@notice Increment the total orders per address for the msg.sender
338:            ++totalOrdersPerAddress[msg.sender];
339:
340:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
341:            orderIds[i] = orderId;
342:
343:            ///@notice Add the orderId to the addressToAllOrderIds structure
344:            addressToAllOrderIds[msg.sender].push(orderId);
345:
346:            unchecked {
347:                ++i;
348:            }
349:        }
350:
``` 



File:LimitOrderBook.sol 
```solidity
280:        for (uint256 i = 0; i < orderGroup.length;) {
281:            ///@notice Get the order details from the orderGroup.
282:            LimitOrder memory newOrder = orderGroup[i];
283:
284:            if (newOrder.quantity == 0) {
285:                revert OrderQuantityIsZero();
286:            }
287:
288:            ///@notice Increment the total value of orders by the quantity of the new order
289:            updatedTotalOrdersValue += newOrder.quantity;
290:
291:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
292:            if (!(orderToken == newOrder.tokenIn)) {
293:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
294:            }
295:
296:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
297:            if (newOrder.tokenOut == newOrder.tokenIn) {
298:                revert TokenInIsTokenOut();
299:            }
300:
301:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
302:            if (tokenBalance < updatedTotalOrdersValue) {
303:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
304:            }
305:
306:            ///@notice Create a new orderId from the orderNonce and current block timestamp
307:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
308:
309:            ///@notice Increment the cumulative execution credit by the current orders execution.
310:            cumulativeExecutionCredit += newOrder.executionCredit;
311:
312:            ///@notice increment the orderNonce
313:            /**
314:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
315:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
316:             */
317:            unchecked {
318:                orderNonce += 2;
319:            }
320:
321:            ///@notice Set the new order's owner to the msg.sender
322:            newOrder.owner = msg.sender;
323:
324:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
325:            newOrder.orderId = orderId;
326:
327:            ///@notice update the newOrder's last refresh timestamp
328:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
329:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
330:
331:            ///@notice Add the newly created order to the orderIdToOrder mapping
332:            orderIdToLimitOrder[orderId] = newOrder;
333:
334:            ///@notice Add the orderId to the addressToOrderIds mapping
335:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingLimitOrder;
336:
337:            ///@notice Increment the total orders per address for the msg.sender
338:            ++totalOrdersPerAddress[msg.sender];
339:
340:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
341:            orderIds[i] = orderId;
342:
343:            ///@notice Add the orderId to the addressToAllOrderIds structure
344:            addressToAllOrderIds[msg.sender].push(orderId);
345:
346:            unchecked {
347:                ++i;
348:            }
349:        }
350:
``` 



File:LimitOrderBook.sol 
```solidity
585:        for (uint256 i = 0; i < length;) {
586:            bytes32 orderId;
587:            assembly {
588:                //Get the orderId at the orderOffsetSlot.
589:                orderId := mload(orderOffsetSlot)
590:                //Update the orderOffsetSlot.
591:                orderOffsetSlot := add(orderOffsetSlot, 0x20)
592:            }
593:
594:            OrderType orderType = addressToOrderIds[_owner][orderId];
595:
596:            if (orderType == targetOrderType) {
597:                orderIds[orderIdIndex] = orderId;
598:                ++orderIdIndex;
599:            }
600:
601:            unchecked {
602:                ++i;
603:            }
604:        }
605:
``` 



File:LimitOrderSwapRouter.sol 
```solidity
127:        for (uint256 i = 0; i < _dexFactories.length; ++i) {
128:            if (i == 0) {
129:                require(_isUniV2[i], "First Dex must be uniswap v2");
130:            }
131:            require(_dexFactories[i] != address(0), "Zero values in constructor");
132:            dexes.push(Dex({factoryAddress: _dexFactories[i], isUniV2: _isUniV2[i]}));
133:
134:            address uniswapV3Factory;
135:            ///@notice If the dex is a univ3 variant, then set the uniswapV3Factory storage address.
136:            if (!_isUniV2[i]) {
137:                uniswapV3Factory = _dexFactories[i];
138:            }
139:
140:            UNISWAP_V3_FACTORY = uniswapV3Factory;
141:        }
142:    }
``` 



File:LimitOrderSwapRouter.sol 
```solidity
588:            for (uint256 i = 0; i < dexes.length;) {
589:                if (dexes[i].isUniV2) {
590:                    {
591:                        ///@notice Get the Uniswap v2 spot price and lp address.
592:                        (SpotReserve memory spotPrice, address poolAddress) =
593:                            _calculateV2SpotPrice(token0, token1, dexes[i].factoryAddress);
594:                        ///@notice Set SpotReserve and lp values if the returned values are not null.
595:                        if (spotPrice.spotPrice != 0) {
596:                            _spotPrices[i] = spotPrice;
597:                            _lps[i] = poolAddress;
598:                        }
599:                    }
600:                } else {
601:                    {
602:                        {
603:                            ///@notice Get the Uniswap v2 spot price and lp address.
604:                            (SpotReserve memory spotPrice, address poolAddress) =
605:                                _calculateV3SpotPrice(token0, token1, FEE, dexes[i].factoryAddress);
606:
607:                            ///@notice Set SpotReserve and lp values if the returned values are not null.
608:                            if (spotPrice.spotPrice != 0) {
609:                                _lps[i] = poolAddress;
610:                                _spotPrices[i] = spotPrice;
611:                            }
612:                        }
613:                    }
614:                }
615:
616:                unchecked {
617:                    ++i;
618:                }
619:            }
620:
``` 



File:LimitOrderSwapRouter.sol 
```solidity
588:            for (uint256 i = 0; i < dexes.length;) {
589:                if (dexes[i].isUniV2) {
590:                    {
591:                        ///@notice Get the Uniswap v2 spot price and lp address.
592:                        (SpotReserve memory spotPrice, address poolAddress) =
593:                            _calculateV2SpotPrice(token0, token1, dexes[i].factoryAddress);
594:                        ///@notice Set SpotReserve and lp values if the returned values are not null.
595:                        if (spotPrice.spotPrice != 0) {
596:                            _spotPrices[i] = spotPrice;
597:                            _lps[i] = poolAddress;
598:                        }
599:                    }
600:                } else {
601:                    {
602:                        {
603:                            ///@notice Get the Uniswap v2 spot price and lp address.
604:                            (SpotReserve memory spotPrice, address poolAddress) =
605:                                _calculateV3SpotPrice(token0, token1, FEE, dexes[i].factoryAddress);
606:
607:                            ///@notice Set SpotReserve and lp values if the returned values are not null.
608:                            if (spotPrice.spotPrice != 0) {
609:                                _lps[i] = poolAddress;
610:                                _spotPrices[i] = spotPrice;
611:                            }
612:                        }
613:                    }
614:                }
615:
616:                unchecked {
617:                    ++i;
618:                }
619:            }
620:
``` 



File:LimitOrderSwapRouter.sol 
```solidity
588:            for (uint256 i = 0; i < dexes.length;) {
589:                if (dexes[i].isUniV2) {
590:                    {
591:                        ///@notice Get the Uniswap v2 spot price and lp address.
592:                        (SpotReserve memory spotPrice, address poolAddress) =
593:                            _calculateV2SpotPrice(token0, token1, dexes[i].factoryAddress);
594:                        ///@notice Set SpotReserve and lp values if the returned values are not null.
595:                        if (spotPrice.spotPrice != 0) {
596:                            _spotPrices[i] = spotPrice;
597:                            _lps[i] = poolAddress;
598:                        }
599:                    }
600:                } else {
601:                    {
602:                        {
603:                            ///@notice Get the Uniswap v2 spot price and lp address.
604:                            (SpotReserve memory spotPrice, address poolAddress) =
605:                                _calculateV3SpotPrice(token0, token1, FEE, dexes[i].factoryAddress);
606:
607:                            ///@notice Set SpotReserve and lp values if the returned values are not null.
608:                            if (spotPrice.spotPrice != 0) {
609:                                _lps[i] = poolAddress;
610:                                _spotPrices[i] = spotPrice;
611:                            }
612:                        }
613:                    }
614:                }
615:
616:                unchecked {
617:                    ++i;
618:                }
619:            }
620:
``` 



File:LimitOrderSwapRouter.sol 
```solidity
588:            for (uint256 i = 0; i < dexes.length;) {
589:                if (dexes[i].isUniV2) {
590:                    {
591:                        ///@notice Get the Uniswap v2 spot price and lp address.
592:                        (SpotReserve memory spotPrice, address poolAddress) =
593:                            _calculateV2SpotPrice(token0, token1, dexes[i].factoryAddress);
594:                        ///@notice Set SpotReserve and lp values if the returned values are not null.
595:                        if (spotPrice.spotPrice != 0) {
596:                            _spotPrices[i] = spotPrice;
597:                            _lps[i] = poolAddress;
598:                        }
599:                    }
600:                } else {
601:                    {
602:                        {
603:                            ///@notice Get the Uniswap v2 spot price and lp address.
604:                            (SpotReserve memory spotPrice, address poolAddress) =
605:                                _calculateV3SpotPrice(token0, token1, FEE, dexes[i].factoryAddress);
606:
607:                            ///@notice Set SpotReserve and lp values if the returned values are not null.
608:                            if (spotPrice.spotPrice != 0) {
609:                                _lps[i] = poolAddress;
610:                                _spotPrices[i] = spotPrice;
611:                            }
612:                        }
613:                    }
614:                }
615:
616:                unchecked {
617:                    ++i;
618:                }
619:            }
620:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
316:        for (uint256 i = 0; i < orderGroup.length;) {
317:            ///@notice Get the order details from the orderGroup.
318:            SandboxLimitOrder memory newOrder = orderGroup[i];
319:
320:            ///@notice Increment the total value of orders by the quantity of the new order
321:            updatedTotalOrdersValue += newOrder.amountInRemaining;
322:            uint256 relativeWethValue;
323:            {
324:                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
325:                if (!(newOrder.tokenIn == WETH)) {
326:                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
327:                    (LimitOrderSwapRouter.SpotReserve[] memory spRes,) =
328:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).getAllPrices(newOrder.tokenIn, WETH, 500);
329:                    uint256 tokenAWethSpotPrice;
330:                    for (uint256 k = 0; k < spRes.length;) {
331:                        if (spRes[k].spotPrice != 0) {
332:                            tokenAWethSpotPrice = spRes[k].spotPrice;
333:                            break;
334:                        }
335:
336:                        unchecked {
337:                            ++k;
338:                        }
339:                    }
340:                    if (tokenAWethSpotPrice == 0) {
341:                        revert InvalidInputTokenForOrderPlacement();
342:                    }
343:
344:                    if (!(tokenAWethSpotPrice == 0)) {
345:                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
346:                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn).decimals();
347:                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
348:                        relativeWethValue = tokenInDecimals <= 18
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
350:                                * 10 ** (18 - tokenInDecimals)
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
352:                                / 10 ** (tokenInDecimals - 18);
353:                    }
354:                } else {
355:                    relativeWethValue = newOrder.amountInRemaining;
356:                }
357:
358:                if (relativeWethValue < MIN_ORDER_VALUE_IN_WETH) {
359:                    revert InsufficientOrderInputValue();
360:                }
361:
362:                ///@notice Set the minimum fee to the fee*wethValue*subsidy.
363:                uint128 minFeeReceived = uint128(
364:                    ConveyorMath.mul64U(
365:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).calculateFee(uint128(relativeWethValue), USDC, WETH),
366:                        relativeWethValue
367:                    )
368:                );
369:                ///@notice Set the Orders min fee to be received during execution.
370:                newOrder.feeRemaining = minFeeReceived;
371:            }
372:
373:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
374:            if ((orderToken != newOrder.tokenIn)) {
375:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
376:            }
377:
378:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
379:            if (tokenBalance < updatedTotalOrdersValue) {
380:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
381:            }
382:
383:            ///@notice Create a new orderId from the orderNonce and current block timestamp
384:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
385:
386:            ///@notice increment the orderNonce
387:            /**
388:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
389:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
390:             */
391:            unchecked {
392:                orderNonce += 2;
393:            }
394:
395:            ///@notice Set the new order's owner to the msg.sender
396:            newOrder.owner = msg.sender;
397:
398:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
399:            newOrder.orderId = orderId;
400:
401:            ///@notice update the newOrder's last refresh timestamp
402:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
403:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
404:
405:            ///@notice Increment the cumulative execution credit by the current orders execution.
406:            cumulativeExecutionCredit += newOrder.executionCreditRemaining;
407:
408:            ///@notice Add the newly created order to the orderIdToOrder mapping
409:            orderIdToSandboxLimitOrder[orderId] = newOrder;
410:
411:            ///@notice Add the orderId to the addressToOrderIds mapping
412:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingSandboxLimitOrder;
413:
414:            ///@notice Increment the total orders per address for the msg.sender
415:            ++totalOrdersPerAddress[msg.sender];
416:
417:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
418:            orderIds[i] = orderId;
419:
420:            ///@notice Add the orderId to the addressToAllOrderIds structure
421:            addressToAllOrderIds[msg.sender].push(orderId);
422:
423:            unchecked {
424:                ++i;
425:            }
426:        }
427:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
316:        for (uint256 i = 0; i < orderGroup.length;) {
317:            ///@notice Get the order details from the orderGroup.
318:            SandboxLimitOrder memory newOrder = orderGroup[i];
319:
320:            ///@notice Increment the total value of orders by the quantity of the new order
321:            updatedTotalOrdersValue += newOrder.amountInRemaining;
322:            uint256 relativeWethValue;
323:            {
324:                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
325:                if (!(newOrder.tokenIn == WETH)) {
326:                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
327:                    (LimitOrderSwapRouter.SpotReserve[] memory spRes,) =
328:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).getAllPrices(newOrder.tokenIn, WETH, 500);
329:                    uint256 tokenAWethSpotPrice;
330:                    for (uint256 k = 0; k < spRes.length;) {
331:                        if (spRes[k].spotPrice != 0) {
332:                            tokenAWethSpotPrice = spRes[k].spotPrice;
333:                            break;
334:                        }
335:
336:                        unchecked {
337:                            ++k;
338:                        }
339:                    }
340:                    if (tokenAWethSpotPrice == 0) {
341:                        revert InvalidInputTokenForOrderPlacement();
342:                    }
343:
344:                    if (!(tokenAWethSpotPrice == 0)) {
345:                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
346:                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn).decimals();
347:                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
348:                        relativeWethValue = tokenInDecimals <= 18
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
350:                                * 10 ** (18 - tokenInDecimals)
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
352:                                / 10 ** (tokenInDecimals - 18);
353:                    }
354:                } else {
355:                    relativeWethValue = newOrder.amountInRemaining;
356:                }
357:
358:                if (relativeWethValue < MIN_ORDER_VALUE_IN_WETH) {
359:                    revert InsufficientOrderInputValue();
360:                }
361:
362:                ///@notice Set the minimum fee to the fee*wethValue*subsidy.
363:                uint128 minFeeReceived = uint128(
364:                    ConveyorMath.mul64U(
365:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).calculateFee(uint128(relativeWethValue), USDC, WETH),
366:                        relativeWethValue
367:                    )
368:                );
369:                ///@notice Set the Orders min fee to be received during execution.
370:                newOrder.feeRemaining = minFeeReceived;
371:            }
372:
373:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
374:            if ((orderToken != newOrder.tokenIn)) {
375:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
376:            }
377:
378:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
379:            if (tokenBalance < updatedTotalOrdersValue) {
380:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
381:            }
382:
383:            ///@notice Create a new orderId from the orderNonce and current block timestamp
384:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
385:
386:            ///@notice increment the orderNonce
387:            /**
388:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
389:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
390:             */
391:            unchecked {
392:                orderNonce += 2;
393:            }
394:
395:            ///@notice Set the new order's owner to the msg.sender
396:            newOrder.owner = msg.sender;
397:
398:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
399:            newOrder.orderId = orderId;
400:
401:            ///@notice update the newOrder's last refresh timestamp
402:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
403:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
404:
405:            ///@notice Increment the cumulative execution credit by the current orders execution.
406:            cumulativeExecutionCredit += newOrder.executionCreditRemaining;
407:
408:            ///@notice Add the newly created order to the orderIdToOrder mapping
409:            orderIdToSandboxLimitOrder[orderId] = newOrder;
410:
411:            ///@notice Add the orderId to the addressToOrderIds mapping
412:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingSandboxLimitOrder;
413:
414:            ///@notice Increment the total orders per address for the msg.sender
415:            ++totalOrdersPerAddress[msg.sender];
416:
417:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
418:            orderIds[i] = orderId;
419:
420:            ///@notice Add the orderId to the addressToAllOrderIds structure
421:            addressToAllOrderIds[msg.sender].push(orderId);
422:
423:            unchecked {
424:                ++i;
425:            }
426:        }
427:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
316:        for (uint256 i = 0; i < orderGroup.length;) {
317:            ///@notice Get the order details from the orderGroup.
318:            SandboxLimitOrder memory newOrder = orderGroup[i];
319:
320:            ///@notice Increment the total value of orders by the quantity of the new order
321:            updatedTotalOrdersValue += newOrder.amountInRemaining;
322:            uint256 relativeWethValue;
323:            {
324:                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
325:                if (!(newOrder.tokenIn == WETH)) {
326:                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
327:                    (LimitOrderSwapRouter.SpotReserve[] memory spRes,) =
328:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).getAllPrices(newOrder.tokenIn, WETH, 500);
329:                    uint256 tokenAWethSpotPrice;
330:                    for (uint256 k = 0; k < spRes.length;) {
331:                        if (spRes[k].spotPrice != 0) {
332:                            tokenAWethSpotPrice = spRes[k].spotPrice;
333:                            break;
334:                        }
335:
336:                        unchecked {
337:                            ++k;
338:                        }
339:                    }
340:                    if (tokenAWethSpotPrice == 0) {
341:                        revert InvalidInputTokenForOrderPlacement();
342:                    }
343:
344:                    if (!(tokenAWethSpotPrice == 0)) {
345:                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
346:                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn).decimals();
347:                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
348:                        relativeWethValue = tokenInDecimals <= 18
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
350:                                * 10 ** (18 - tokenInDecimals)
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
352:                                / 10 ** (tokenInDecimals - 18);
353:                    }
354:                } else {
355:                    relativeWethValue = newOrder.amountInRemaining;
356:                }
357:
358:                if (relativeWethValue < MIN_ORDER_VALUE_IN_WETH) {
359:                    revert InsufficientOrderInputValue();
360:                }
361:
362:                ///@notice Set the minimum fee to the fee*wethValue*subsidy.
363:                uint128 minFeeReceived = uint128(
364:                    ConveyorMath.mul64U(
365:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).calculateFee(uint128(relativeWethValue), USDC, WETH),
366:                        relativeWethValue
367:                    )
368:                );
369:                ///@notice Set the Orders min fee to be received during execution.
370:                newOrder.feeRemaining = minFeeReceived;
371:            }
372:
373:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
374:            if ((orderToken != newOrder.tokenIn)) {
375:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
376:            }
377:
378:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
379:            if (tokenBalance < updatedTotalOrdersValue) {
380:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
381:            }
382:
383:            ///@notice Create a new orderId from the orderNonce and current block timestamp
384:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
385:
386:            ///@notice increment the orderNonce
387:            /**
388:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
389:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
390:             */
391:            unchecked {
392:                orderNonce += 2;
393:            }
394:
395:            ///@notice Set the new order's owner to the msg.sender
396:            newOrder.owner = msg.sender;
397:
398:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
399:            newOrder.orderId = orderId;
400:
401:            ///@notice update the newOrder's last refresh timestamp
402:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
403:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
404:
405:            ///@notice Increment the cumulative execution credit by the current orders execution.
406:            cumulativeExecutionCredit += newOrder.executionCreditRemaining;
407:
408:            ///@notice Add the newly created order to the orderIdToOrder mapping
409:            orderIdToSandboxLimitOrder[orderId] = newOrder;
410:
411:            ///@notice Add the orderId to the addressToOrderIds mapping
412:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingSandboxLimitOrder;
413:
414:            ///@notice Increment the total orders per address for the msg.sender
415:            ++totalOrdersPerAddress[msg.sender];
416:
417:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
418:            orderIds[i] = orderId;
419:
420:            ///@notice Add the orderId to the addressToAllOrderIds structure
421:            addressToAllOrderIds[msg.sender].push(orderId);
422:
423:            unchecked {
424:                ++i;
425:            }
426:        }
427:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
316:        for (uint256 i = 0; i < orderGroup.length;) {
317:            ///@notice Get the order details from the orderGroup.
318:            SandboxLimitOrder memory newOrder = orderGroup[i];
319:
320:            ///@notice Increment the total value of orders by the quantity of the new order
321:            updatedTotalOrdersValue += newOrder.amountInRemaining;
322:            uint256 relativeWethValue;
323:            {
324:                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
325:                if (!(newOrder.tokenIn == WETH)) {
326:                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
327:                    (LimitOrderSwapRouter.SpotReserve[] memory spRes,) =
328:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).getAllPrices(newOrder.tokenIn, WETH, 500);
329:                    uint256 tokenAWethSpotPrice;
330:                    for (uint256 k = 0; k < spRes.length;) {
331:                        if (spRes[k].spotPrice != 0) {
332:                            tokenAWethSpotPrice = spRes[k].spotPrice;
333:                            break;
334:                        }
335:
336:                        unchecked {
337:                            ++k;
338:                        }
339:                    }
340:                    if (tokenAWethSpotPrice == 0) {
341:                        revert InvalidInputTokenForOrderPlacement();
342:                    }
343:
344:                    if (!(tokenAWethSpotPrice == 0)) {
345:                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
346:                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn).decimals();
347:                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
348:                        relativeWethValue = tokenInDecimals <= 18
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
350:                                * 10 ** (18 - tokenInDecimals)
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
352:                                / 10 ** (tokenInDecimals - 18);
353:                    }
354:                } else {
355:                    relativeWethValue = newOrder.amountInRemaining;
356:                }
357:
358:                if (relativeWethValue < MIN_ORDER_VALUE_IN_WETH) {
359:                    revert InsufficientOrderInputValue();
360:                }
361:
362:                ///@notice Set the minimum fee to the fee*wethValue*subsidy.
363:                uint128 minFeeReceived = uint128(
364:                    ConveyorMath.mul64U(
365:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).calculateFee(uint128(relativeWethValue), USDC, WETH),
366:                        relativeWethValue
367:                    )
368:                );
369:                ///@notice Set the Orders min fee to be received during execution.
370:                newOrder.feeRemaining = minFeeReceived;
371:            }
372:
373:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
374:            if ((orderToken != newOrder.tokenIn)) {
375:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
376:            }
377:
378:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
379:            if (tokenBalance < updatedTotalOrdersValue) {
380:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
381:            }
382:
383:            ///@notice Create a new orderId from the orderNonce and current block timestamp
384:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
385:
386:            ///@notice increment the orderNonce
387:            /**
388:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
389:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
390:             */
391:            unchecked {
392:                orderNonce += 2;
393:            }
394:
395:            ///@notice Set the new order's owner to the msg.sender
396:            newOrder.owner = msg.sender;
397:
398:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
399:            newOrder.orderId = orderId;
400:
401:            ///@notice update the newOrder's last refresh timestamp
402:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
403:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
404:
405:            ///@notice Increment the cumulative execution credit by the current orders execution.
406:            cumulativeExecutionCredit += newOrder.executionCreditRemaining;
407:
408:            ///@notice Add the newly created order to the orderIdToOrder mapping
409:            orderIdToSandboxLimitOrder[orderId] = newOrder;
410:
411:            ///@notice Add the orderId to the addressToOrderIds mapping
412:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingSandboxLimitOrder;
413:
414:            ///@notice Increment the total orders per address for the msg.sender
415:            ++totalOrdersPerAddress[msg.sender];
416:
417:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
418:            orderIds[i] = orderId;
419:
420:            ///@notice Add the orderId to the addressToAllOrderIds structure
421:            addressToAllOrderIds[msg.sender].push(orderId);
422:
423:            unchecked {
424:                ++i;
425:            }
426:        }
427:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
316:        for (uint256 i = 0; i < orderGroup.length;) {
317:            ///@notice Get the order details from the orderGroup.
318:            SandboxLimitOrder memory newOrder = orderGroup[i];
319:
320:            ///@notice Increment the total value of orders by the quantity of the new order
321:            updatedTotalOrdersValue += newOrder.amountInRemaining;
322:            uint256 relativeWethValue;
323:            {
324:                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
325:                if (!(newOrder.tokenIn == WETH)) {
326:                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
327:                    (LimitOrderSwapRouter.SpotReserve[] memory spRes,) =
328:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).getAllPrices(newOrder.tokenIn, WETH, 500);
329:                    uint256 tokenAWethSpotPrice;
330:                    for (uint256 k = 0; k < spRes.length;) {
331:                        if (spRes[k].spotPrice != 0) {
332:                            tokenAWethSpotPrice = spRes[k].spotPrice;
333:                            break;
334:                        }
335:
336:                        unchecked {
337:                            ++k;
338:                        }
339:                    }
340:                    if (tokenAWethSpotPrice == 0) {
341:                        revert InvalidInputTokenForOrderPlacement();
342:                    }
343:
344:                    if (!(tokenAWethSpotPrice == 0)) {
345:                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
346:                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn).decimals();
347:                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
348:                        relativeWethValue = tokenInDecimals <= 18
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
350:                                * 10 ** (18 - tokenInDecimals)
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
352:                                / 10 ** (tokenInDecimals - 18);
353:                    }
354:                } else {
355:                    relativeWethValue = newOrder.amountInRemaining;
356:                }
357:
358:                if (relativeWethValue < MIN_ORDER_VALUE_IN_WETH) {
359:                    revert InsufficientOrderInputValue();
360:                }
361:
362:                ///@notice Set the minimum fee to the fee*wethValue*subsidy.
363:                uint128 minFeeReceived = uint128(
364:                    ConveyorMath.mul64U(
365:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).calculateFee(uint128(relativeWethValue), USDC, WETH),
366:                        relativeWethValue
367:                    )
368:                );
369:                ///@notice Set the Orders min fee to be received during execution.
370:                newOrder.feeRemaining = minFeeReceived;
371:            }
372:
373:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
374:            if ((orderToken != newOrder.tokenIn)) {
375:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
376:            }
377:
378:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
379:            if (tokenBalance < updatedTotalOrdersValue) {
380:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
381:            }
382:
383:            ///@notice Create a new orderId from the orderNonce and current block timestamp
384:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
385:
386:            ///@notice increment the orderNonce
387:            /**
388:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
389:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
390:             */
391:            unchecked {
392:                orderNonce += 2;
393:            }
394:
395:            ///@notice Set the new order's owner to the msg.sender
396:            newOrder.owner = msg.sender;
397:
398:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
399:            newOrder.orderId = orderId;
400:
401:            ///@notice update the newOrder's last refresh timestamp
402:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
403:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
404:
405:            ///@notice Increment the cumulative execution credit by the current orders execution.
406:            cumulativeExecutionCredit += newOrder.executionCreditRemaining;
407:
408:            ///@notice Add the newly created order to the orderIdToOrder mapping
409:            orderIdToSandboxLimitOrder[orderId] = newOrder;
410:
411:            ///@notice Add the orderId to the addressToOrderIds mapping
412:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingSandboxLimitOrder;
413:
414:            ///@notice Increment the total orders per address for the msg.sender
415:            ++totalOrdersPerAddress[msg.sender];
416:
417:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
418:            orderIds[i] = orderId;
419:
420:            ///@notice Add the orderId to the addressToAllOrderIds structure
421:            addressToAllOrderIds[msg.sender].push(orderId);
422:
423:            unchecked {
424:                ++i;
425:            }
426:        }
427:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
316:        for (uint256 i = 0; i < orderGroup.length;) {
317:            ///@notice Get the order details from the orderGroup.
318:            SandboxLimitOrder memory newOrder = orderGroup[i];
319:
320:            ///@notice Increment the total value of orders by the quantity of the new order
321:            updatedTotalOrdersValue += newOrder.amountInRemaining;
322:            uint256 relativeWethValue;
323:            {
324:                ///@notice Boolean indicating if user wants to cover the fee from the fee credit balance, or by calling placeOrder with payment.
325:                if (!(newOrder.tokenIn == WETH)) {
326:                    ///@notice Calculate the spot price of the input token to WETH on Uni v2.
327:                    (LimitOrderSwapRouter.SpotReserve[] memory spRes,) =
328:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).getAllPrices(newOrder.tokenIn, WETH, 500);
329:                    uint256 tokenAWethSpotPrice;
330:                    for (uint256 k = 0; k < spRes.length;) {
331:                        if (spRes[k].spotPrice != 0) {
332:                            tokenAWethSpotPrice = spRes[k].spotPrice;
333:                            break;
334:                        }
335:
336:                        unchecked {
337:                            ++k;
338:                        }
339:                    }
340:                    if (tokenAWethSpotPrice == 0) {
341:                        revert InvalidInputTokenForOrderPlacement();
342:                    }
343:
344:                    if (!(tokenAWethSpotPrice == 0)) {
345:                        ///@notice Get the tokenIn decimals to normalize the relativeWethValue.
346:                        uint8 tokenInDecimals = IERC20(newOrder.tokenIn).decimals();
347:                        ///@notice Multiply the amountIn*spotPrice to get the value of the input amount in weth.
348:                        relativeWethValue = tokenInDecimals <= 18
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
350:                                * 10 ** (18 - tokenInDecimals)
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
352:                                / 10 ** (tokenInDecimals - 18);
353:                    }
354:                } else {
355:                    relativeWethValue = newOrder.amountInRemaining;
356:                }
357:
358:                if (relativeWethValue < MIN_ORDER_VALUE_IN_WETH) {
359:                    revert InsufficientOrderInputValue();
360:                }
361:
362:                ///@notice Set the minimum fee to the fee*wethValue*subsidy.
363:                uint128 minFeeReceived = uint128(
364:                    ConveyorMath.mul64U(
365:                        ILimitOrderSwapRouter(LIMIT_ORDER_EXECUTOR).calculateFee(uint128(relativeWethValue), USDC, WETH),
366:                        relativeWethValue
367:                    )
368:                );
369:                ///@notice Set the Orders min fee to be received during execution.
370:                newOrder.feeRemaining = minFeeReceived;
371:            }
372:
373:            ///@notice If the newOrder's tokenIn does not match the orderToken, revert.
374:            if ((orderToken != newOrder.tokenIn)) {
375:                revert IncongruentInputTokenInOrderGroup(newOrder.tokenIn, orderToken);
376:            }
377:
378:            ///@notice If the msg.sender does not have a sufficent balance to cover the order, revert.
379:            if (tokenBalance < updatedTotalOrdersValue) {
380:                revert InsufficientWalletBalance(msg.sender, tokenBalance, updatedTotalOrdersValue);
381:            }
382:
383:            ///@notice Create a new orderId from the orderNonce and current block timestamp
384:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
385:
386:            ///@notice increment the orderNonce
387:            /**
388:             * @dev This is unchecked because the orderNonce and block.timestamp will never be the same, so even if the
389:             *         orderNonce overflows, it will still produce unique orderIds because the timestamp will be different.
390:             */
391:            unchecked {
392:                orderNonce += 2;
393:            }
394:
395:            ///@notice Set the new order's owner to the msg.sender
396:            newOrder.owner = msg.sender;
397:
398:            ///@notice update the newOrder's Id to the orderId generated from the orderNonce
399:            newOrder.orderId = orderId;
400:
401:            ///@notice update the newOrder's last refresh timestamp
402:            ///@dev uint32(block.timestamp % (2**32 - 1)) is used to future proof the contract.
403:            newOrder.lastRefreshTimestamp = uint32(block.timestamp);
404:
405:            ///@notice Increment the cumulative execution credit by the current orders execution.
406:            cumulativeExecutionCredit += newOrder.executionCreditRemaining;
407:
408:            ///@notice Add the newly created order to the orderIdToOrder mapping
409:            orderIdToSandboxLimitOrder[orderId] = newOrder;
410:
411:            ///@notice Add the orderId to the addressToOrderIds mapping
412:            addressToOrderIds[msg.sender][orderId] = OrderType.PendingSandboxLimitOrder;
413:
414:            ///@notice Increment the total orders per address for the msg.sender
415:            ++totalOrdersPerAddress[msg.sender];
416:
417:            ///@notice Add the orderId to the orderIds array for the PlaceOrder event emission and increment the orderIdIndex
418:            orderIds[i] = orderId;
419:
420:            ///@notice Add the orderId to the addressToAllOrderIds structure
421:            addressToAllOrderIds[msg.sender].push(orderId);
422:
423:            unchecked {
424:                ++i;
425:            }
426:        }
427:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
749:            for (uint256 i = 0; i < orderIdBundles.length;) {
750:                bytes32[] memory orderIdBundle = orderIdBundles[i];
751:
752:                for (uint256 j = 0; j < orderIdBundle.length;) {
753:                    bytes32 orderId = orderIdBundle[j];
754:
755:                    ///@notice Transfer the tokens from the order owners to the sandbox router contract.
756:                    ///@dev This function is executed in the context of ConveyorExecutor as a delegatecall.
757:
758:                    ///@notice Get the current order
759:                    SandboxLimitOrder memory currentOrder = orderIdToSandboxLimitOrder[orderId];
760:
761:                    if (currentOrder.orderId == bytes32(0)) {
762:                        revert OrderDoesNotExist(orderId);
763:                    }
764:
765:                    preSandboxExecutionState.orderOwners[arrayIndex] = currentOrder.owner;
766:
767:                    preSandboxExecutionState.sandboxLimitOrders[arrayIndex] = currentOrder;
768:
769:                    ///@notice Cache amountSpecifiedToFill for intermediate calculations
770:                    uint128 amountSpecifiedToFill = fillAmounts[arrayIndex];
771:                    ///@notice Require the amountSpecifiedToFill is less than or equal to the amountInRemaining of the order.
772:                    if (amountSpecifiedToFill > currentOrder.amountInRemaining) {
773:                        revert FillAmountSpecifiedGreaterThanAmountRemaining(
774:                            amountSpecifiedToFill, currentOrder.amountInRemaining, currentOrder.orderId
775:                        );
776:                    }
777:
778:                    ///@notice Cache the the pre execution state of the order details
779:                    preSandboxExecutionState.initialTokenInBalances[arrayIndex] =
780:                        IERC20(currentOrder.tokenIn).balanceOf(currentOrder.owner);
781:
782:                    preSandboxExecutionState.initialTokenOutBalances[arrayIndex] =
783:                        IERC20(currentOrder.tokenOut).balanceOf(currentOrder.owner);
784:
785:                    unchecked {
786:                        ++arrayIndex;
787:                    }
788:
789:                    unchecked {
790:                        ++j;
791:                    }
792:                }
793:
794:                unchecked {
795:                    ++i;
796:                }
797:            }
798:        }
``` 



File:SandboxLimitOrderBook.sol 
```solidity
752:                for (uint256 j = 0; j < orderIdBundle.length;) {
753:                    bytes32 orderId = orderIdBundle[j];
754:
755:                    ///@notice Transfer the tokens from the order owners to the sandbox router contract.
756:                    ///@dev This function is executed in the context of ConveyorExecutor as a delegatecall.
757:
758:                    ///@notice Get the current order
759:                    SandboxLimitOrder memory currentOrder = orderIdToSandboxLimitOrder[orderId];
760:
761:                    if (currentOrder.orderId == bytes32(0)) {
762:                        revert OrderDoesNotExist(orderId);
763:                    }
764:
765:                    preSandboxExecutionState.orderOwners[arrayIndex] = currentOrder.owner;
766:
767:                    preSandboxExecutionState.sandboxLimitOrders[arrayIndex] = currentOrder;
768:
769:                    ///@notice Cache amountSpecifiedToFill for intermediate calculations
770:                    uint128 amountSpecifiedToFill = fillAmounts[arrayIndex];
771:                    ///@notice Require the amountSpecifiedToFill is less than or equal to the amountInRemaining of the order.
772:                    if (amountSpecifiedToFill > currentOrder.amountInRemaining) {
773:                        revert FillAmountSpecifiedGreaterThanAmountRemaining(
774:                            amountSpecifiedToFill, currentOrder.amountInRemaining, currentOrder.orderId
775:                        );
776:                    }
777:
778:                    ///@notice Cache the the pre execution state of the order details
779:                    preSandboxExecutionState.initialTokenInBalances[arrayIndex] =
780:                        IERC20(currentOrder.tokenIn).balanceOf(currentOrder.owner);
781:
782:                    preSandboxExecutionState.initialTokenOutBalances[arrayIndex] =
783:                        IERC20(currentOrder.tokenOut).balanceOf(currentOrder.owner);
784:
785:                    unchecked {
786:                        ++arrayIndex;
787:                    }
788:
789:                    unchecked {
790:                        ++j;
791:                    }
792:                }
793:
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1221:        for (uint256 i = 0; i < length;) {
1222:            bytes32 orderId;
1223:            assembly {
1224:                //Get the orderId at the orderOffsetSlot
1225:                orderId := mload(orderOffsetSlot)
1226:                //Update the orderOffsetSlot
1227:                orderOffsetSlot := add(orderOffsetSlot, 0x20)
1228:            }
1229:
1230:            OrderType orderType = addressToOrderIds[orderOwner][orderId];
1231:
1232:            if (orderType == targetOrderType) {
1233:                orderIds[orderIdIndex] = orderId;
1234:                ++orderIdIndex;
1235:            }
1236:
1237:            unchecked {
1238:                ++i;
1239:            }
1240:        }
1241:
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-14]></a> [G-14] 
 <h3> Use assembly to hash instead of Solidity - Instances: 2 </h3> 
 </summary>
 
 
> Hashing is a safe operation to perform in assembly, and it is cheaper than Solidity's `keccak256` function.
         
 
#### Gas Report - Savings: ~82 
 <details>  
 <summary>  
  </summary> 
 
        
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
    }

    function testGas() public view {
        c0.solidityHash(2309349, 2304923409);
        c1.assemblyHash(2309349, 2304923409);
    }
}

contract Contract0 {
    function solidityHash(uint256 a, uint256 b) public view {
        //unoptimized
        keccak256(abi.encodePacked(a, b));
    }
}

contract Contract1 {
    function assemblyHash(uint256 a, uint256 b) public view {
        //optimized
        assembly {
            mstore(0x00, a)
            mstore(0x20, b)
            let hashedVal := keccak256(0x00, 0x40)
        }
    }
}

```

```solidity

╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 36687              ┆ 214             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ solidityHash       ┆ 313             ┆ 313 ┆ 313    ┆ 313 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 31281              ┆ 186             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ assemblyHash       ┆ 231             ┆ 231 ┆ 231    ┆ 231 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```
         
 </details> 
 

File:SandboxLimitOrderBook.sol 
```solidity
384:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1141:        bytes32 totalOrdersValueKey = keccak256(abi.encode(orderOwner, token));
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1150:        bytes32 totalOrdersValueKey = keccak256(abi.encode(orderOwner, token));
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1178:        bytes32 totalOrdersValueKey = keccak256(abi.encode(msg.sender, token));
``` 



File:LimitOrderBook.sol 
```solidity
307:            bytes32 orderId = keccak256(abi.encode(orderNonce, block.timestamp));
``` 



File:LimitOrderBook.sol 
```solidity
537:        bytes32 totalOrdersValueKey = keccak256(abi.encode(msg.sender, token));
``` 



File:LimitOrderBook.sol 
```solidity
546:        bytes32 totalOrdersValueKey = keccak256(abi.encode(_owner, token));
``` 



File:LimitOrderBook.sol 
```solidity
555:        bytes32 totalOrdersValueKey = keccak256(abi.encode(_owner, token));
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-15]></a> [G-15] 
 <h3> Use assembly for math (add, sub, mul, div) - Instances: 12 </h3> 
 </summary>
 
 
> Use assembly for math instead of Solidity. You can check for overflow/underflow in assembly to ensure safety. If using Solidity versions < 0.8.0 and you are using Safemath, you can gain significant gas savings by using assembly to calculate values and checking for overflow/underflow. 
 
#### Gas Report - Savings: ~60 
 <details>  
 <summary>  
  </summary> 
 
        
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;
    Contract2 c2;
    Contract3 c3;
    Contract4 c4;
    Contract5 c5;
    Contract6 c6;
    Contract7 c7;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
        c2 = new Contract2();
        c3 = new Contract3();
        c4 = new Contract4();
        c5 = new Contract5();
        c6 = new Contract6();
        c7 = new Contract7();
    }

    function testGas() public {
        c0.addTest(34598345, 100);
        c1.addAssemblyTest(34598345, 100);
        c2.subTest(34598345, 100);
        c3.subAssemblyTest(34598345, 100);
        c4.mulTest(34598345, 100);
        c5.mulAssemblyTest(34598345, 100);
        c6.divTest(34598345, 100);
        c7.divAssemblyTest(34598345, 100);
    }
}

contract Contract0 {
    //addition in Solidity
    function addTest(uint256 a, uint256 b) public pure {
        uint256 c = a + b;
    }
}

contract Contract1 {
    //addition in assembly
    function addAssemblyTest(uint256 a, uint256 b) public pure {
        assembly {
            let c := add(a, b)

            if lt(c, a) {
                mstore(0x00, "overflow")
                revert(0x00, 0x20)
            }
        }
    }
}

contract Contract2 {
    //subtraction in Solidity
    function subTest(uint256 a, uint256 b) public pure {
        uint256 c = a - b;
    }
}

contract Contract3 {
    //subtraction in assembly
    function subAssemblyTest(uint256 a, uint256 b) public pure {
        assembly {
            let c := sub(a, b)

            if gt(c, a) {
                mstore(0x00, "underflow")
                revert(0x00, 0x20)
            }
        }
    }
}

contract Contract4 {
    //multiplication in Solidity
    function mulTest(uint256 a, uint256 b) public pure {
        uint256 c = a * b;
    }
}

contract Contract5 {
    //multiplication in assembly
    function mulAssemblyTest(uint256 a, uint256 b) public pure {
        assembly {
            let c := mul(a, b)

            if lt(c, a) {
                mstore(0x00, "overflow")
                revert(0x00, 0x20)
            }
        }
    }
}

contract Contract6 {
    //division in Solidity
    function divTest(uint256 a, uint256 b) public pure {
        uint256 c = a * b;
    }
}

contract Contract7 {
    //division in assembly
    function divAssemblyTest(uint256 a, uint256 b) public pure {
        assembly {
            let c := div(a, b)

            if gt(c, a) {
                mstore(0x00, "underflow")
                revert(0x00, 0x20)
            }
        }
    }
}


```


```solidity

╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 40493              ┆ 233             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addTest            ┆ 303             ┆ 303 ┆ 303    ┆ 303 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37087              ┆ 216             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ addAssemblyTest    ┆ 263             ┆ 263 ┆ 263    ┆ 263 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract2 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 40293              ┆ 232             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ subTest            ┆ 300             ┆ 300 ┆ 300    ┆ 300 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract3 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37287              ┆ 217             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ subAssemblyTest    ┆ 263             ┆ 263 ┆ 263    ┆ 263 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract4 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 41893              ┆ 240             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ mulTest            ┆ 325             ┆ 325 ┆ 325    ┆ 325 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract5 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37087              ┆ 216             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ mulAssemblyTest    ┆ 265             ┆ 265 ┆ 265    ┆ 265 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract6 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 41893              ┆ 240             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ divTest            ┆ 325             ┆ 325 ┆ 325    ┆ 325 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract7 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 37287              ┆ 217             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ divAssemblyTest    ┆ 265             ┆ 265 ┆ 265    ┆ 265 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯

```
         
 </details> 
 

File:LimitOrderSwapRouter.sol 
```solidity
183:        uint256 amountInUSDCDollarValue = ConveyorMath.mul128U(spotPrice, amountIn) / uint256(10 ** 18);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
206:        return ConveyorMath.add64x64(rationalFraction, 461168601842738800) / 10 ** 2;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
271:        amountReceived = IERC20(_tokenOut).balanceOf(_receiver) - balanceBefore;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
347:            _zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
``` 



File:LimitOrderSwapRouter.sol 
```solidity
347:            _zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1,
``` 



File:LimitOrderSwapRouter.sol 
```solidity
474:            ? uint128(reserve0 * (10 ** (18 - token0Decimals)))
``` 



File:LimitOrderSwapRouter.sol 
```solidity
474:            ? uint128(reserve0 * (10 ** (18 - token0Decimals)))
``` 



File:LimitOrderSwapRouter.sol 
```solidity
475:            : uint128(reserve0 * (10 ** (token0Decimals - 18)));
``` 



File:LimitOrderSwapRouter.sol 
```solidity
475:            : uint128(reserve0 * (10 ** (token0Decimals - 18)));
``` 



File:LimitOrderSwapRouter.sol 
```solidity
477:            ? uint128(reserve1 * (10 ** (18 - token1Decimals)))
``` 



File:LimitOrderSwapRouter.sol 
```solidity
477:            ? uint128(reserve1 * (10 ** (18 - token1Decimals)))
``` 



File:LimitOrderSwapRouter.sol 
```solidity
478:            : uint128(reserve1 * (10 ** (token1Decimals - 18)));
``` 



File:LimitOrderSwapRouter.sol 
```solidity
478:            : uint128(reserve1 * (10 ** (token1Decimals - 18)));
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
64:        if (block.timestamp - lastCheckInTime > CHECK_IN_INTERVAL) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
251:            if (executionCreditRemaining - amount < minExecutionCredit) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
252:                revert InsufficientExecutionCredit(executionCreditRemaining - amount, minExecutionCredit);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
256:        orderIdToSandboxLimitOrder[orderId].executionCreditRemaining = executionCreditRemaining - amount;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
259:        emit OrderExecutionCreditUpdated(orderId, executionCreditRemaining - amount);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
275:            orderIdToSandboxLimitOrder[orderId].executionCreditRemaining + uint128(msg.value);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
291:        uint256 minimumExecutionCreditForOrderGroup = minExecutionCredit * orderGroup.length;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
349:                            ? ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
350:                                * 10 ** (18 - tokenInDecimals)
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
``` 



File:SandboxLimitOrderBook.sol 
```solidity
350:                                * 10 ** (18 - tokenInDecimals)
``` 



File:SandboxLimitOrderBook.sol 
```solidity
351:                            : ConveyorMath.mul128U(tokenAWethSpotPrice, newOrder.amountInRemaining)
352:                                / 10 ** (tokenInDecimals - 18);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
352:                                / 10 ** (tokenInDecimals - 18);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
471:                orderIdToSandboxLimitOrder[order.orderId].executionCreditRemaining + uint128(msg.value);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
564:        if (block.timestamp - lastCheckInTime > CHECK_IN_INTERVAL) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
602:                executionCreditRemaining - uint128(REFRESH_FEE);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
604:            _safeTransferETH(order.owner, executionCreditRemaining - REFRESH_FEE);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
624:        if (block.timestamp - lastCheckInTime > CHECK_IN_INTERVAL) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
665:            if (executionCreditBalance - REFRESH_FEE < minExecutionCredit) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
675:        if (block.timestamp - order.lastRefreshTimestamp < REFRESH_INTERVAL) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
680:            executionCreditBalance - uint128(REFRESH_FEE);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
681:        emit OrderExecutionCreditUpdated(order.orderId, executionCreditBalance - REFRESH_FEE);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
821:                orderIdIndex += orderIdBundle.length - 1;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
867:        if (initialTokenInBalance - currentTokenInBalance > fillAmount) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
869:                currentOrder.orderId, initialTokenInBalance - currentTokenInBalance, fillAmount
``` 



File:SandboxLimitOrderBook.sol 
```solidity
874:        if (currentTokenOutBalance - initialTokenOutBalance != amountOutRequired) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
876:                currentOrder.orderId, currentTokenOutBalance - initialTokenOutBalance, amountOutRequired
``` 



File:SandboxLimitOrderBook.sol 
```solidity
887:                uint128(initialTokenInBalance - currentTokenInBalance),
``` 



File:SandboxLimitOrderBook.sol 
```solidity
888:                uint128(currentTokenOutBalance - initialTokenOutBalance),
``` 



File:SandboxLimitOrderBook.sol 
```solidity
932:                SandboxLimitOrder memory currentOrder = preSandboxExecutionState.sandboxLimitOrders[offset + 1];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
943:                        fillAmounts[offset + 1]
``` 



File:SandboxLimitOrderBook.sol 
```solidity
955:                        preSandboxExecutionState.initialTokenInBalances[offset] - currentTokenInBalance
956:                            > cumulativeFillAmount
``` 



File:SandboxLimitOrderBook.sol 
```solidity
960:                            preSandboxExecutionState.initialTokenInBalances[offset] - currentTokenInBalance,
``` 



File:SandboxLimitOrderBook.sol 
```solidity
965:                    cumulativeFillAmount = fillAmounts[offset + 1];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
968:                    cumulativeFillAmount += fillAmounts[offset + 1];
``` 



File:SandboxLimitOrderBook.sol 
```solidity
974:                        currentTokenOutBalance - preSandboxExecutionState.initialTokenOutBalances[offset]
975:                            != cumulativeAmountOutRequired
``` 



File:SandboxLimitOrderBook.sol 
```solidity
979:                            currentTokenOutBalance - preSandboxExecutionState.initialTokenOutBalances[offset],
``` 



File:SandboxLimitOrderBook.sol 
```solidity
998:            _resolveOrPartialFillOrder(prevOrder, offset - 1, fillAmounts, cumulativeExecutionCompensation);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1057:        orderIdToSandboxLimitOrder[orderId].amountInRemaining = order.amountInRemaining - amountInFilled;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1059:        orderIdToSandboxLimitOrder[orderId].amountOutRemaining = order.amountOutRemaining - amountOutFilled;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1064:        uint128 updatedFeeRemaining = feeRemaining
1065:            - uint128(ConveyorMath.mul64U(ConveyorMath.divUU(amountInFilled, amountInRemaining), feeRemaining));
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1072:        uint128 updatedExecutionCreditRemaining = executionCreditRemaining - executionCreditCompensation;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1079:            order.amountInRemaining - amountInFilled,
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1080:            order.amountOutRemaining - amountOutFilled,
``` 



File:ConveyorExecutor.sol 
```solidity
271:        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
``` 



File:ConveyorExecutor.sol 
```solidity
271:        amountOutWeth = amountOutWeth - (beaconReward + conveyorReward);
``` 



File:ConveyorExecutor.sol 
```solidity
383:                amountInWethToB = amountIn - (beaconReward + conveyorReward);
``` 



File:ConveyorExecutor.sol 
```solidity
383:                amountInWethToB = amountIn - (beaconReward + conveyorReward);
``` 



File:ConveyorExecutor.sol 
```solidity
499:                contractBalancePostExecution - contractBalancePreExecution,
``` 



File:ConveyorExecutor.sol 
```solidity
500:                expectedAccumulatedFees - (contractBalancePostExecution - contractBalancePreExecution)
501:            );
``` 



File:ConveyorExecutor.sol 
```solidity
500:                expectedAccumulatedFees - (contractBalancePostExecution - contractBalancePreExecution)
``` 



File:ConveyorTickMath.sol 
```solidity
75:            int8 decimalShift = int8(IERC20(token0).decimals()) - int8(IERC20(token1).decimals());
``` 



File:ConveyorTickMath.sol 
```solidity
78:                ? uint256(sqrtPriceX96) ** 2 / uint256(10) ** (uint8(-decimalShift))
79:                : uint256(sqrtPriceX96) ** 2 * 10 ** uint8(decimalShift);
``` 



File:ConveyorTickMath.sol 
```solidity
79:                : uint256(sqrtPriceX96) ** 2 * 10 ** uint8(decimalShift);
``` 



File:ConveyorTickMath.sol 
```solidity
83:                ? priceSquaredX96 / Q96
84:                : (Q96 * 0xffffffffffffffffffffffffffffffff) / (priceSquaredX96 / Q96);
``` 



File:ConveyorTickMath.sol 
```solidity
84:                : (Q96 * 0xffffffffffffffffffffffffffffffff) / (priceSquaredX96 / Q96);
``` 



File:ConveyorTickMath.sol 
```solidity
84:                : (Q96 * 0xffffffffffffffffffffffffffffffff) / (priceSquaredX96 / Q96);
``` 



File:ConveyorTickMath.sol 
```solidity
84:                : (Q96 * 0xffffffffffffffffffffffffffffffff) / (priceSquaredX96 / Q96);
``` 



File:ConveyorTickMath.sol 
```solidity
88:                ? (uint256(priceSquaredShiftQ96) * 0xffffffffffffffffffffffffffffffff) / Q96
89:                : priceSquaredShiftQ96;
``` 



File:ConveyorTickMath.sol 
```solidity
88:                ? (uint256(priceSquaredShiftQ96) * 0xffffffffffffffffffffffffffffffff) / Q96
``` 



File:ConveyorTickMath.sol 
```solidity
119:        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
``` 



File:ConveyorTickMath.sol 
```solidity
119:        uint160 sqrtPriceLimitX96 = zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1;
``` 



File:ConveyorTickMath.sol 
```solidity
162:            currentState.amountSpecifiedRemaining -= (step.amountIn + step.feeAmount).toInt256();
``` 



File:ConveyorTickMath.sol 
```solidity
176:                    currentState.tick = zeroForOne ? step.tickNext - 1 : step.tickNext;
``` 



File:ConveyorRouterV1.sol 
```solidity
124:        uint256 tokenOutAmountRequired = balanceBefore + swapData.amountOutMin;
``` 



File:ConveyorRouterV1.sol 
```solidity
132:            revert InsufficientOutputAmount(tokenOutAmountRequired - balanceAfter, swapData.amountOutMin);
``` 



File:ConveyorRouterV1.sol 
```solidity
163:        uint256 amountIn = msg.value - swapData.protocolFee;
``` 



File:ConveyorRouterV1.sol 
```solidity
175:        uint256 tokenOutAmountRequired = balanceBefore + swapData.amountOutMin;
``` 



File:ConveyorRouterV1.sol 
```solidity
185:            revert InsufficientOutputAmount(tokenOutAmountRequired - balanceAfter, swapData.amountOutMin);
``` 



File:ConveyorRouterV1.sol 
```solidity
222:        uint256 amountOutRequired = balanceBefore + swapData.amountOutMin;
``` 



File:ConveyorRouterV1.sol 
```solidity
238:            revert InsufficientOutputAmount(amountOutRequired - msg.sender.balance, swapData.amountOutMin);
``` 



File:LimitOrderRouter.sol 
```solidity
82:        if (block.timestamp - lastCheckInTime > CHECK_IN_INTERVAL) {
``` 



File:LimitOrderRouter.sol 
```solidity
122:            if (executionCreditBalance - REFRESH_FEE < minExecutionCredit) {
``` 



File:LimitOrderRouter.sol 
```solidity
132:        if (block.timestamp - order.lastRefreshTimestamp < REFRESH_INTERVAL) {
``` 



File:LimitOrderRouter.sol 
```solidity
136:        orderIdToLimitOrder[order.orderId].executionCredit = executionCreditBalance - uint128(REFRESH_FEE);
``` 



File:LimitOrderRouter.sol 
```solidity
137:        emit OrderExecutionCreditUpdated(order.orderId, executionCreditBalance - REFRESH_FEE);
``` 



File:LimitOrderRouter.sol 
```solidity
140:        orderIdToLimitOrder[order.orderId].lastRefreshTimestamp = uint32(block.timestamp % (2 ** 32 - 1));
``` 



File:LimitOrderRouter.sol 
```solidity
157:        if (block.timestamp - lastCheckInTime > CHECK_IN_INTERVAL) {
``` 



File:LimitOrderRouter.sol 
```solidity
189:            orderIdToLimitOrder[order.orderId].executionCredit = executionCredit - uint128(REFRESH_FEE);
``` 



File:LimitOrderRouter.sol 
```solidity
191:            _safeTransferETH(order.owner, executionCredit - REFRESH_FEE);
``` 



File:LimitOrderRouter.sol 
```solidity
210:        for (uint256 i = 0; i < orders.length - 1;) {
``` 



File:LimitOrderRouter.sol 
```solidity
213:            LimitOrder memory nextOrder = orders[i + 1];
``` 



File:LimitOrderRouter.sol 
```solidity
270:        if (block.timestamp - lastCheckInTime > CHECK_IN_INTERVAL) {
``` 



File:LimitOrderBook.sol 
```solidity
185:        if (executionCredit - amount < minExecutionCredit) {
``` 



File:LimitOrderBook.sol 
```solidity
186:            revert InsufficientExecutionCredit(executionCredit - amount, minExecutionCredit);
``` 



File:LimitOrderBook.sol 
```solidity
189:        orderIdToLimitOrder[orderId].executionCredit = executionCredit - amount;
``` 



File:LimitOrderBook.sol 
```solidity
193:        emit OrderExecutionCreditUpdated(orderId, executionCredit - amount);
``` 



File:LimitOrderBook.sol 
```solidity
214:        uint128 newExecutionCreditBalance = orderIdToLimitOrder[orderId].executionCredit + uint128(msg.value);
``` 



File:LimitOrderBook.sol 
```solidity
254:        uint256 minimumExecutionCreditForOrderGroup = minExecutionCredit * orderGroup.length;
``` 



File:LimitOrderBook.sol 
```solidity
408:            uint128 newExecutionCredit = orderIdToLimitOrder[order.orderId].executionCredit + uint128(msg.value);
``` 



File:LimitOrderQuoter.sol 
```solidity
180:                spotReserveAToWeth.length * spotReserveWethToB.length
181:            );
``` 



File:LimitOrderQuoter.sol 
```solidity
276:                ? uint128(alphaX * 10 ** (18 - tokenInDecimals))
``` 



File:LimitOrderQuoter.sol 
```solidity
276:                ? uint128(alphaX * 10 ** (18 - tokenInDecimals))
``` 



File:LimitOrderQuoter.sol 
```solidity
277:                : uint128(alphaX / (10 ** (tokenInDecimals - 18)));
``` 



File:LimitOrderQuoter.sol 
```solidity
277:                : uint128(alphaX / (10 ** (tokenInDecimals - 18)));
``` 



File:LimitOrderQuoter.sol 
```solidity
400:                uint256 denominator = reserveA + alphaX;
``` 



File:LimitOrderQuoter.sol 
```solidity
455:        uint256 amountInWithFee = amountIn * 997;
``` 



File:LimitOrderQuoter.sol 
```solidity
456:        uint256 numerator = amountInWithFee * reserveOut;
``` 



File:LimitOrderQuoter.sol 
```solidity
457:        uint256 denominator = reserveIn * 1000 + (amountInWithFee);
``` 



File:LimitOrderQuoter.sol 
```solidity
457:        uint256 denominator = reserveIn * 1000 + (amountInWithFee);
``` 



File:LimitOrderQuoter.sol 
```solidity
458:        amountOut = numerator / denominator;
``` 



File:LimitOrderQuoter.sol 
```solidity
480:            ? uint128(alphaX * 10 ** (18 - tokenInDecimals))
``` 



File:LimitOrderQuoter.sol 
```solidity
480:            ? uint128(alphaX * 10 ** (18 - tokenInDecimals))
``` 



File:LimitOrderQuoter.sol 
```solidity
481:            : uint128(alphaX / (10 ** (tokenInDecimals - 18)));
``` 



File:LimitOrderQuoter.sol 
```solidity
481:            : uint128(alphaX / (10 ** (tokenInDecimals - 18)));
``` 



File:LimitOrderQuoter.sol 
```solidity
559:            uint256 amountInBuffer = (amountInOrder * taxIn) / 10 ** 5;
``` 



File:LimitOrderQuoter.sol 
```solidity
559:            uint256 amountInBuffer = (amountInOrder * taxIn) / 10 ** 5;
``` 



File:LimitOrderQuoter.sol 
```solidity
560:            uint256 amountIn = amountInOrder - amountInBuffer;
``` 



File:LimitOrderQuoter.sol 
```solidity
580:                uint256 amountInBuffer = (amountInOrder * taxIn) / 10 ** 5;
``` 



File:LimitOrderQuoter.sol 
```solidity
580:                uint256 amountInBuffer = (amountInOrder * taxIn) / 10 ** 5;
``` 



File:LimitOrderQuoter.sol 
```solidity
582:                uint256 amountIn = amountInOrder - amountInBuffer;
``` 



File:LimitOrderQuoter.sol 
```solidity
585:                uint256 amountInBuffer = (amountInOrder * taxIn) / 10 ** 5;
``` 



File:LimitOrderQuoter.sol 
```solidity
585:                uint256 amountInBuffer = (amountInOrder * taxIn) / 10 ** 5;
``` 



File:LimitOrderQuoter.sol 
```solidity
587:                uint256 amountIn = amountInOrder - amountInBuffer;
``` 



File:ConveyorFeeMath.sol 
```solidity
10:    uint128 constant MAX_CONVEYOR_PERCENT = 110680464442257300 * 10 ** 2;
``` 



File:ConveyorFeeMath.sol 
```solidity
31:            int256 innerPartial = int256(uint256(ZERO_POINT_ZERO_ZERO_FIVE)) - int128(percentFee);
``` 



File:ConveyorFeeMath.sol 
```solidity
33:            conveyorPercent = (
34:                percentFee + ConveyorMath.div64x64(uint128(uint256(innerPartial)), uint128(2) << 64)
35:                    + uint128(ZERO_POINT_ZERO_ZERO_ONE)
36:            ) * 10 ** 2;
``` 



File:ConveyorFeeMath.sol 
```solidity
34:                percentFee + ConveyorMath.div64x64(uint128(uint256(innerPartial)), uint128(2) << 64)
35:                    + uint128(ZERO_POINT_ZERO_ZERO_ONE)
36:            ) * 10 ** 2;
``` 



File:ConveyorFeeMath.sol 
```solidity
34:                percentFee + ConveyorMath.div64x64(uint128(uint256(innerPartial)), uint128(2) << 64)
35:                    + uint128(ZERO_POINT_ZERO_ZERO_ONE)
``` 



File:ConveyorFeeMath.sol 
```solidity
48:        beaconReward = uint128(totalWethReward) - conveyorReward;
``` 



File:OracleLibraryV2.sol 
```solidity
11:        uint256 numerator = reserveIn * amountOut * 100000;
``` 



File:OracleLibraryV2.sol 
```solidity
11:        uint256 numerator = reserveIn * amountOut * 100000;
``` 



File:OracleLibraryV2.sol 
```solidity
12:        uint256 denominator = (reserveOut - amountOut) * (100000 - swapFee);
``` 



File:OracleLibraryV2.sol 
```solidity
12:        uint256 denominator = (reserveOut - amountOut) * (100000 - swapFee);
``` 



File:OracleLibraryV2.sol 
```solidity
12:        uint256 denominator = (reserveOut - amountOut) * (100000 - swapFee);
``` 



File:OracleLibraryV2.sol 
```solidity
13:        amountIn = (numerator / denominator) + 1;
``` 



File:OracleLibraryV2.sol 
```solidity
13:        amountIn = (numerator / denominator) + 1;
``` 



File:ConveyorMath.sol 
```solidity
73:            uint256 answer = uint256(x) + y;
``` 



File:ConveyorMath.sol 
```solidity
85:            int256 result = int256(x) - y;
``` 



File:ConveyorMath.sol 
```solidity
96:        uint256 answer = x + y;
``` 



File:ConveyorMath.sol 
```solidity
106:        uint256 answer = x + (uint256(y) << 64);
``` 



File:ConveyorMath.sol 
```solidity
117:            uint256 answer = (uint256(x) * y) >> 64;
``` 



File:ConveyorMath.sol 
```solidity
131:        uint256 answer = (uint256(y) * x) >> 64;
``` 



File:ConveyorMath.sol 
```solidity
146:            uint256 lo = (uint256(x) * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF)) >> 64;
``` 



File:ConveyorMath.sol 
```solidity
147:            uint256 hi = uint256(x) * (y >> 128);
``` 



File:ConveyorMath.sol 
```solidity
152:            require(hi <= MAX_128x128 - lo);
``` 



File:ConveyorMath.sol 
```solidity
153:            return hi + lo;
``` 



File:ConveyorMath.sol 
```solidity
166:        return (x * y) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
186:            uint256 answer = (uint256(x) << 64) / y;
``` 



File:ConveyorMath.sol 
```solidity
204:            uint256 hi = xInt * (MAX_128x128 / y);
``` 



File:ConveyorMath.sol 
```solidity
204:            uint256 hi = xInt * (MAX_128x128 / y);
``` 



File:ConveyorMath.sol 
```solidity
205:            uint256 lo = (xDec * (MAX_128x128 / y)) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
205:            uint256 lo = (xDec * (MAX_128x128 / y)) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
207:            require(hi <= MAX_128x128 - lo);
``` 



File:ConveyorMath.sol 
```solidity
208:            return hi + lo;
``` 



File:ConveyorMath.sol 
```solidity
236:                answer = (x << 64) / y;
``` 



File:ConveyorMath.sol 
```solidity
262:                answer = (x << (255 - msb)) / (((y - 1) >> (msb - 191)) + 1);
``` 



File:ConveyorMath.sol 
```solidity
262:                answer = (x << (255 - msb)) / (((y - 1) >> (msb - 191)) + 1);
``` 



File:ConveyorMath.sol 
```solidity
262:                answer = (x << (255 - msb)) / (((y - 1) >> (msb - 191)) + 1);
``` 



File:ConveyorMath.sol 
```solidity
262:                answer = (x << (255 - msb)) / (((y - 1) >> (msb - 191)) + 1);
``` 



File:ConveyorMath.sol 
```solidity
262:                answer = (x << (255 - msb)) / (((y - 1) >> (msb - 191)) + 1);
``` 



File:ConveyorMath.sol 
```solidity
265:                uint256 hi = answer * (y >> 128);
``` 



File:ConveyorMath.sol 
```solidity
266:                uint256 lo = answer * (y & 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF);
``` 



File:ConveyorMath.sol 
```solidity
279:                answer += xl / y;
``` 



File:ConveyorMath.sol 
```solidity
290:        uint32 result = (uint32(integers) << 16) + decimals;
``` 



File:ConveyorMath.sol 
```solidity
304:                answer = (answer * 0x16A09E667F3BCC908B2FB1366EA957D3E) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
307:                answer = (answer * 0x1306FE0A31B7152DE8D5A46305C85EDEC) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
310:                answer = (answer * 0x1172B83C7D517ADCDF7C8C50EB14A791F) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
313:                answer = (answer * 0x10B5586CF9890F6298B92B71842A98363) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
316:                answer = (answer * 0x1059B0D31585743AE7C548EB68CA417FD) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
319:                answer = (answer * 0x102C9A3E778060EE6F7CACA4F7A29BDE8) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
322:                answer = (answer * 0x10163DA9FB33356D84A66AE336DCDFA3F) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
325:                answer = (answer * 0x100B1AFA5ABCBED6129AB13EC11DC9543) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
328:                answer = (answer * 0x10058C86DA1C09EA1FF19D294CF2F679B) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
331:                answer = (answer * 0x1002C605E2E8CEC506D21BFC89A23A00F) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
334:                answer = (answer * 0x100162F3904051FA128BCA9C55C31E5DF) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
337:                answer = (answer * 0x1000B175EFFDC76BA38E31671CA939725) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
340:                answer = (answer * 0x100058BA01FB9F96D6CACD4B180917C3D) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
343:                answer = (answer * 0x10002C5CC37DA9491D0985C348C68E7B3) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
346:                answer = (answer * 0x1000162E525EE054754457D5995292026) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
349:                answer = (answer * 0x10000B17255775C040618BF4A4ADE83FC) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
352:                answer = (answer * 0x1000058B91B5BC9AE2EED81E9B7D4CFAB) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
355:                answer = (answer * 0x100002C5C89D5EC6CA4D7C8ACC017B7C9) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
358:                answer = (answer * 0x10000162E43F4F831060E02D839A9D16D) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
361:                answer = (answer * 0x100000B1721BCFC99D9F890EA06911763) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
364:                answer = (answer * 0x10000058B90CF1E6D97F9CA14DBCC1628) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
367:                answer = (answer * 0x1000002C5C863B73F016468F6BAC5CA2B) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
370:                answer = (answer * 0x100000162E430E5A18F6119E3C02282A5) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
373:                answer = (answer * 0x1000000B1721835514B86E6D96EFD1BFE) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
376:                answer = (answer * 0x100000058B90C0B48C6BE5DF846C5B2EF) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
379:                answer = (answer * 0x10000002C5C8601CC6B9E94213C72737A) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
382:                answer = (answer * 0x1000000162E42FFF037DF38AA2B219F06) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
385:                answer = (answer * 0x10000000B17217FBA9C739AA5819F44F9) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
388:                answer = (answer * 0x1000000058B90BFCDEE5ACD3C1CEDC823) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
391:                answer = (answer * 0x100000002C5C85FE31F35A6A30DA1BE50) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
394:                answer = (answer * 0x10000000162E42FF0999CE3541B9FFFCF) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
397:                answer = (answer * 0x100000000B17217F80F4EF5AADDA45554) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
400:                answer = (answer * 0x10000000058B90BFBF8479BD5A81B51AD) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
403:                answer = (answer * 0x1000000002C5C85FDF84BD62AE30A74CC) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
406:                answer = (answer * 0x100000000162E42FEFB2FED257559BDAA) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
409:                answer = (answer * 0x1000000000B17217F7D5A7716BBA4A9AE) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
412:                answer = (answer * 0x100000000058B90BFBE9DDBAC5E109CCE) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
415:                answer = (answer * 0x10000000002C5C85FDF4B15DE6F17EB0D) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
418:                answer = (answer * 0x1000000000162E42FEFA494F1478FDE05) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
421:                answer = (answer * 0x10000000000B17217F7D20CF927C8E94C) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
424:                answer = (answer * 0x1000000000058B90BFBE8F71CB4E4B33D) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
427:                answer = (answer * 0x100000000002C5C85FDF477B662B26945) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
430:                answer = (answer * 0x10000000000162E42FEFA3AE53369388C) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
433:                answer = (answer * 0x100000000000B17217F7D1D351A389D40) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
436:                answer = (answer * 0x10000000000058B90BFBE8E8B2D3D4EDE) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
439:                answer = (answer * 0x1000000000002C5C85FDF4741BEA6E77E) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
442:                answer = (answer * 0x100000000000162E42FEFA39FE95583C2) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
445:                answer = (answer * 0x1000000000000B17217F7D1CFB72B45E1) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
448:                answer = (answer * 0x100000000000058B90BFBE8E7CC35C3F0) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
451:                answer = (answer * 0x10000000000002C5C85FDF473E242EA38) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
454:                answer = (answer * 0x1000000000000162E42FEFA39F02B772C) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
457:                answer = (answer * 0x10000000000000B17217F7D1CF7D83C1A) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
460:                answer = (answer * 0x1000000000000058B90BFBE8E7BDCBE2E) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
463:                answer = (answer * 0x100000000000002C5C85FDF473DEA871F) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
466:                answer = (answer * 0x10000000000000162E42FEFA39EF44D91) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
469:                answer = (answer * 0x100000000000000B17217F7D1CF79E949) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
472:                answer = (answer * 0x10000000000000058B90BFBE8E7BCE544) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
475:                answer = (answer * 0x1000000000000002C5C85FDF473DE6ECA) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
478:                answer = (answer * 0x100000000000000162E42FEFA39EF366F) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
481:                answer = (answer * 0x1000000000000000B17217F7D1CF79AFA) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
484:                answer = (answer * 0x100000000000000058B90BFBE8E7BCD6D) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
487:                answer = (answer * 0x10000000000000002C5C85FDF473DE6B2) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
490:                answer = (answer * 0x1000000000000000162E42FEFA39EF358) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
493:                answer = (answer * 0x10000000000000000B17217F7D1CF79AB) >> 128;
``` 



File:ConveyorMath.sol 
```solidity
496:            answer >>= uint256(63 - (x >> 64));
``` 



File:ConveyorMath.sol 
```solidity
510:            return exp_2(uint128((uint256(x) * 0x171547652B82FE1777D0FFDA0D23A7D12) >> 128));
``` 



File:ConveyorMath.sol 
```solidity
551:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
551:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
552:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
552:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
553:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
553:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
554:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
554:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
555:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
555:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
556:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
556:                r = (r + x / r) >> 1;
``` 



File:ConveyorMath.sol 
```solidity
557:                r = (r + x / r) >> 1; // Seven iterations should be enough
``` 



File:ConveyorMath.sol 
```solidity
557:                r = (r + x / r) >> 1; // Seven iterations should be enough
``` 



File:ConveyorMath.sol 
```solidity
558:                uint256 r1 = x / r;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-16]></a> [G-16] 
 <h3> Use assembly to write storage values - Instances: 6 </h3> 
 </summary>
 
 
> You can save a fair amount of gas by using assembly to write storage values.
     
 
#### Gas Report - Savings: ~66 
 <details>  
 <summary>  
  </summary> 
 
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
    }

    function testGas() public {
        c0.updateOwner(0x158B28A1b1CB1BE12C6bD8f5a646a0e3B2024734);
        c1.assemblyUpdateOwner(0x158B28A1b1CB1BE12C6bD8f5a646a0e3B2024734);
    }
}

contract Contract0 {
    address owner = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

    function updateOwner(address newOwner) public {
        owner = newOwner;
    }
}

contract Contract1 {
    address owner = 0xb4c79daB8f259C7Aee6E5b2Aa729821864227e84;

    function assemblyUpdateOwner(address newOwner) public {
        assembly {
            sstore(owner.slot, newOwner)
        }
    }
}

```

```solidity

╭────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ Contract0 contract ┆                 ┆      ┆        ┆      ┆         │
╞════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 60623              ┆ 261             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ updateOwner        ┆ 5302            ┆ 5302 ┆ 5302   ┆ 5302 ┆ 1       │
╰────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯
╭────────────────────┬─────────────────┬──────┬────────┬──────┬─────────╮
│ Contract1 contract ┆                 ┆      ┆        ┆      ┆         │
╞════════════════════╪═════════════════╪══════╪════════╪══════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 54823              ┆ 232             ┆      ┆        ┆      ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg  ┆ median ┆ max  ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ assemblyUpdateOwner┆ 5236            ┆ 5236 ┆ 5236   ┆ 5236 ┆ 1       │
╰────────────────────┴─────────────────┴──────┴────────┴──────┴─────────╯

```
         
 </details> 
 

File:LimitOrderBook.sol 
```solidity
31:        reentrancyStatus = true;
``` 



File:LimitOrderBook.sol 
```solidity
33:        reentrancyStatus = false;
``` 



File:LimitOrderBook.sol 
```solidity
46:        minExecutionCredit = _minExecutionCredit;
``` 



File:ConveyorRouterV1.sol 
```solidity
64:        CONVEYOR_MULTICALL = address(new ConveyorMulticall());
``` 



File:ConveyorRouterV1.sol 
```solidity
66:        owner = tx.origin;
``` 



File:ConveyorRouterV1.sol 
```solidity
372:        tempOwner = address(0);
``` 



File:ConveyorRouterV1.sol 
```solidity
373:        owner = msg.sender;
``` 



File:ConveyorRouterV1.sol 
```solidity
382:        tempOwner = newOwner;
``` 



File:ConveyorRouterV1.sol 
```solidity
406:            affiliateNonce = tempAffiliateNonce;
``` 



File:ConveyorRouterV1.sol 
```solidity
422:            referrerNonce = tempReferrerNonce;
``` 



File:ConveyorRouterV1.sol 
```solidity
443:        locked = true;
``` 



File:ConveyorRouterV1.sol 
```solidity
445:        locked = false;
``` 



File:LimitOrderRouter.sol 
```solidity
72:        owner = tx.origin;
``` 



File:LimitOrderRouter.sol 
```solidity
353:        owner = msg.sender;
``` 



File:LimitOrderRouter.sol 
```solidity
354:        tempOwner = address(0);
``` 



File:LimitOrderRouter.sol 
```solidity
362:        tempOwner = newOwner;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
65:        reentrancyStatus = true;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
67:        reentrancyStatus = false;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
95:        minExecutionCredit = _minExecutionCredit;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
102:        owner = tx.origin;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1252:        minExecutionCredit = newMinExecutionCredit;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1261:        owner = msg.sender;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1262:        tempOwner = address(0);
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1270:        tempOwner = newOwner;
``` 



File:ConveyorExecutor.sol 
```solidity
68:        reentrancyStatus = true;
``` 



File:ConveyorExecutor.sol 
```solidity
70:        reentrancyStatus = false;
``` 



File:ConveyorExecutor.sol 
```solidity
149:        owner = msg.sender;
``` 



File:ConveyorExecutor.sol 
```solidity
512:        conveyorBalance = 0;
``` 



File:ConveyorExecutor.sol 
```solidity
523:        tempOwner = address(0);
``` 



File:ConveyorExecutor.sol 
```solidity
524:        owner = msg.sender;
``` 



File:ConveyorExecutor.sol 
```solidity
533:        tempOwner = newOwner;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
354:        uniV3AmountOut = 0;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
377:            uniV3AmountOut = uint256(-amount1Delta);
``` 



File:LimitOrderSwapRouter.sol 
```solidity
382:            uniV3AmountOut = uint256(-amount0Delta);
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[G-17]></a> [G-17] 
 <h3> Use custom errors instead of string error messages - Instances: 10 </h3> 
 </summary>
 
 
> Using custom errors will save you gas, and can be used to provide more information about the error.
        
         
 
#### Gas Report - Savings: ~57 
 <details>  
 <summary>  
  </summary> 
 
        
```solidity

contract GasTest is DSTest {
    Contract0 c0;
    Contract1 c1;

    function setUp() public {
        c0 = new Contract0();
        c1 = new Contract1();
    }

    function testFailGas() public {
        c0.stringErrorMessage();
        c1.customErrorMessage();
    }
}

contract Contract0 {
    function stringErrorMessage() public {
        bool check = false;
        require(check, "error message");
    }
}

contract Contract1 {
    error CustomError();

    function customErrorMessage() public {
        bool check = false;
        if (!check) {
            revert CustomError();
        }
    }
}

```


```solidity
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract0 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 34087              ┆ 200             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ stringErrorMessage ┆ 218             ┆ 218 ┆ 218    ┆ 218 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
╭────────────────────┬─────────────────┬─────┬────────┬─────┬─────────╮
│ Contract1 contract ┆                 ┆     ┆        ┆     ┆         │
╞════════════════════╪═════════════════╪═════╪════════╪═════╪═════════╡
│ Deployment Cost    ┆ Deployment Size ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ 26881              ┆ 164             ┆     ┆        ┆     ┆         │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ Function Name      ┆ min             ┆ avg ┆ median ┆ max ┆ # calls │
├╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌┼╌╌╌╌╌┼╌╌╌╌╌╌╌╌╌┤
│ customErrorMessage ┆ 161             ┆ 161 ┆ 161    ┆ 161 ┆ 1       │
╰────────────────────┴─────────────────┴─────┴────────┴─────┴─────────╯
```

 
 </details> 
 

File:LimitOrderRouter.sol 
```solidity
69:        require(_limitOrderExecutor != address(0), "Invalid ConveyorExecutor address");
``` 



File:LimitOrderQuoter.sol 
```solidity
16:        require(_weth != address(0), "Invalid weth address");
``` 



File:ConveyorMath.sol 
```solidity
220:            require(answer <= uint128(MAX_64x64), "overflow");
``` 



File:ConveyorMath.sol 
```solidity
263:                require(answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, "overflow in divuu");
``` 



File:ConveyorMath.sol 
```solidity
282:            require(answer <= 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF, "overflow in divuu last");
``` 



File:ConveyorMath.sol 
```solidity
508:            require(x < 0x400000000000000000, "Exponential overflow"); // Overflow
``` 



File:ConveyorTickMath.sol 
```solidity
90:            require(priceX128 <= type(uint256).max, "Overflow");
``` 



File:ConveyorRouterV1.sol 
```solidity
63:        require(_weth != address(0), "WETH address is zero");
``` 



File:ConveyorRouterV1.sol 
```solidity
405:            require(tempAffiliateNonce < type(uint16).max >> 0x1, "Affiliate nonce overflow");
``` 



File:ConveyorRouterV1.sol 
```solidity
421:            require(tempReferrerNonce < type(uint16).max >> 0x1, "Referrer nonce overflow");
``` 



File:LimitOrderBook.sol 
```solidity
42:        require(_limitOrderExecutor != address(0), "limitOrderExecutor address is address(0)");
``` 



File:LimitOrderBook.sol 
```solidity
44:        require(_minExecutionCredit != 0, "Minimum Execution Credit is 0");
``` 



File:ConveyorExecutor.sol 
```solidity
118:        require(_weth != address(0), "Invalid weth address");
``` 



File:ConveyorExecutor.sol 
```solidity
119:        require(_usdc != address(0), "Invalid usdc address");
``` 



File:ConveyorExecutor.sol 
```solidity
120:        require(_limitOrderQuoterAddress != address(0), "Invalid LimitOrderQuoter address");
``` 



File:OracleLibraryV2.sol 
```solidity
9:        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
``` 



File:OracleLibraryV2.sol 
```solidity
10:        require(reserveIn > 0 && reserveOut > 0, "UniswapV2Library: INSUFFICIENT_LIQUIDITY");
``` 



File:LimitOrderSwapRouter.sol 
```solidity
129:                require(_isUniV2[i], "First Dex must be uniswap v2");
``` 



File:LimitOrderSwapRouter.sol 
```solidity
131:            require(_dexFactories[i] != address(0), "Zero values in constructor");
``` 



File:SandboxLimitOrderBook.sol 
```solidity
93:        require(_limitOrderExecutor != address(0), "limitOrderExecutor address is address(0)");
``` 



File:SandboxLimitOrderBook.sol 
```solidity
94:        require(_minExecutionCredit != 0, "Minimum Execution Credit is 0");
``` 

 
 </details> 
 </details>

 <details open> 
 <summary> 
 <h3>Quality Assurance - Instances: 9 </h3> 
 </summary> 
  

 <details open> 
 <summary> 
 <a name=[NC-0]></a> [NC-0] 
 <h3> Constructor should be listed before any other function - Instances: 1 </h3> 
 </summary>
 Description of the qa pattern goes here 

File:ConveyorRouterV1.sol 
```solidity
62:    constructor(address _weth) payable {
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-1]></a> [NC-1] 
 <h3> Private variables should contain a leading underscore - Instances: 1 </h3> 
 </summary>
 Description of the qa pattern goes here 

File:ConveyorRouterV1.sol 
```solidity
436:    bool private locked;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-2]></a> [NC-2] 
 <h3> Constructor should initialize all variables - Instances: 13 </h3> 
 </summary>
 Description of the qa pattern goes here 

File:SandboxLimitOrderBook.sol 
```solidity
92:    constructor(address _limitOrderExecutor, address _weth, address _usdc, uint256 _minExecutionCredit) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
92:    constructor(address _limitOrderExecutor, address _weth, address _usdc, uint256 _minExecutionCredit) {
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
53:    constructor(address _limitOrderExecutor, address _sandboxLimitOrderBook) {
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
53:    constructor(address _limitOrderExecutor, address _sandboxLimitOrderBook) {
``` 



File:LimitOrderBook.sol 
```solidity
41:    constructor(address _limitOrderExecutor, address _weth, address _usdc, uint256 _minExecutionCredit) {
``` 



File:LimitOrderBook.sol 
```solidity
41:    constructor(address _limitOrderExecutor, address _weth, address _usdc, uint256 _minExecutionCredit) {
``` 



File:LimitOrderRouter.sol 
```solidity
64:    constructor(address _weth, address _usdc, address _limitOrderExecutor, uint256 _minExecutionCredit)
65:        LimitOrderBook(_limitOrderExecutor, _weth, _usdc, _minExecutionCredit)
66:    {
``` 



File:LimitOrderRouter.sol 
```solidity
64:    constructor(address _weth, address _usdc, address _limitOrderExecutor, uint256 _minExecutionCredit)
65:        LimitOrderBook(_limitOrderExecutor, _weth, _usdc, _minExecutionCredit)
66:    {
``` 



File:LimitOrderRouter.sol 
```solidity
64:    constructor(address _weth, address _usdc, address _limitOrderExecutor, uint256 _minExecutionCredit)
65:        LimitOrderBook(_limitOrderExecutor, _weth, _usdc, _minExecutionCredit)
66:    {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
125:    constructor(address[] memory _dexFactories, bool[] memory _isUniV2) {
``` 



File:ConveyorExecutor.sol 
```solidity
110:    constructor(
111:        address _weth,
112:        address _usdc,
113:        address _limitOrderQuoterAddress,
114:        address[] memory _dexFactories,
115:        bool[] memory _isUniV2,
116:        uint256 _minExecutionCredit
117:    ) LimitOrderSwapRouter(_dexFactories, _isUniV2) {
``` 



File:ConveyorExecutor.sol 
```solidity
110:    constructor(
111:        address _weth,
112:        address _usdc,
113:        address _limitOrderQuoterAddress,
114:        address[] memory _dexFactories,
115:        bool[] memory _isUniV2,
116:        uint256 _minExecutionCredit
117:    ) LimitOrderSwapRouter(_dexFactories, _isUniV2) {
``` 



File:ConveyorExecutor.sol 
```solidity
110:    constructor(
111:        address _weth,
112:        address _usdc,
113:        address _limitOrderQuoterAddress,
114:        address[] memory _dexFactories,
115:        bool[] memory _isUniV2,
116:        uint256 _minExecutionCredit
117:    ) LimitOrderSwapRouter(_dexFactories, _isUniV2) {
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-3]></a> [NC-3] 
 <h3> Consider importing specific identifiers instead of the whole file - Instances: 156 </h3> 
 </summary>
 This will minimize compiled code size and help with readability 

File:UniswapV2Callback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:UniswapV2Callback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:UniswapV2Callback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:ILimitOrderQuoter.sol 
```solidity
3:import "../LimitOrderSwapRouter.sol";
``` 



File:DeployBSCAggregator.s.sol 
```solidity
6:import "../../test/utils/Console.sol";
``` 



File:ElkSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:ElkSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:ElkSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:VerseCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:VerseCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:VerseCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:LimitOrderBook.sol 
```solidity
3:import "../lib/interfaces/token/IERC20.sol";
``` 



File:LimitOrderBook.sol 
```solidity
4:import "./ConveyorErrors.sol";
``` 



File:LimitOrderBook.sol 
```solidity
5:import "./interfaces/ILimitOrderSwapRouter.sol";
``` 



File:LimitOrderBook.sol 
```solidity
6:import "./lib/ConveyorMath.sol";
``` 



File:LimitOrderBook.sol 
```solidity
7:import "./interfaces/IConveyorExecutor.sol";
``` 



File:MdexSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:MdexSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:MdexSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:ILimitOrderBook.sol 
```solidity
3:import "../LimitOrderBook.sol";
``` 



File:ConvergenceXCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:ConvergenceXCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:ConvergenceXCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:DystopiaCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:DystopiaCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:DystopiaCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:BabySwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:BabySwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:BabySwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:MeerkatCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:MeerkatCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:MeerkatCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:IConveyorRouterV1.sol 
```solidity
3:import "../ConveyorRouterV1.sol";
``` 



File:BabyDogeCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:BabyDogeCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:BabyDogeCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
3:import "../lib/interfaces/token/IERC20.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
4:import "./LimitOrderBook.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
5:import "./ConveyorErrors.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
6:import "../lib/interfaces/token/IWETH.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
7:import "./LimitOrderSwapRouter.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
8:import "./interfaces/ILimitOrderQuoter.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
9:import "./interfaces/IConveyorExecutor.sol";
``` 



File:LimitOrderRouter.sol 
```solidity
10:import "./interfaces/ILimitOrderRouter.sol";
``` 



File:ConveyorMath.sol 
```solidity
3:import "../../lib/libraries/Uniswap/FullMath.sol";
``` 



File:KyberSwapV3Callback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:TraderJoeCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:TraderJoeCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:TraderJoeCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:DeployTest.s.sol 
```solidity
6:import "../../test/utils/Console.sol";
``` 



File:UniswapV3Callback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:ISandboxLimitOrderRouter.sol 
```solidity
3:import "../SandboxLimitOrderRouter.sol";
``` 



File:LinkSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:LinkSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:LinkSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:DefiSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:DefiSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:DefiSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:AlgebraCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:ApeSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:ApeSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:ApeSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:UniFiCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:UniFiCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:UniFiCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
3:import "../lib/interfaces/token/IERC20.sol";
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
4:import "./ConveyorErrors.sol";
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
5:import "./interfaces/ISandboxLimitOrderBook.sol";
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
6:import "../lib/libraries/token/SafeERC20.sol";
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
7:import "./interfaces/ISandboxLimitOrderRouter.sol";
``` 



File:SandboxLimitOrderRouter.sol 
```solidity
8:import "./interfaces/IConveyorExecutor.sol";
``` 



File:LimitOrderQuoter.sol 
```solidity
3:import "./LimitOrderSwapRouter.sol";
``` 



File:LimitOrderQuoter.sol 
```solidity
4:import "./lib/ConveyorTickMath.sol";
``` 



File:LimitOrderQuoter.sol 
```solidity
5:import "./interfaces/ILimitOrderQuoter.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
3:import "./LimitOrderSwapRouter.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
4:import "./interfaces/ILimitOrderQuoter.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
5:import "./lib/ConveyorFeeMath.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
6:import "./LimitOrderRouter.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
7:import "./interfaces/ILimitOrderSwapRouter.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
8:import "./interfaces/ISandboxLimitOrderRouter.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
9:import "./interfaces/ISandboxLimitOrderBook.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
10:import "./interfaces/ILimitOrderBook.sol";
``` 



File:ConveyorExecutor.sol 
```solidity
11:import "./interfaces/IConveyorExecutor.sol";
``` 



File:ConveyorFeeMath.sol 
```solidity
3:import "./ConveyorMath.sol";
``` 



File:ConveyorFeeMath.sol 
```solidity
4:import "../../lib/libraries/QuadruplePrecision.sol";
``` 



File:DXSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:DXSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:DXSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:ISandboxLimitOrderBook.sol 
```solidity
3:import "../SandboxLimitOrderRouter.sol";
``` 



File:ISandboxLimitOrderBook.sol 
```solidity
4:import "../SandboxLimitOrderBook.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
3:import "./ConveyorErrors.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
4:import "../lib/interfaces/token/IERC20.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
5:import "./interfaces/ILimitOrderBook.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
6:import "./interfaces/ILimitOrderSwapRouter.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
7:import "./LimitOrderSwapRouter.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
8:import "./lib/ConveyorMath.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
9:import "./interfaces/IConveyorExecutor.sol";
``` 



File:SandboxLimitOrderBook.sol 
```solidity
10:import "./SandboxLimitOrderRouter.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
3:import "../../lib/libraries/Uniswap/FullMath.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
4:import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
5:import "../../lib/libraries/Uniswap/SafeCast.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
6:import "../../lib/libraries/Uniswap/SqrtPriceMath.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
7:import "../../lib/libraries/Uniswap/TickMath.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
8:import "../../lib/libraries/Uniswap/TickBitmap.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
9:import "../../lib/libraries/Uniswap/SwapMath.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
10:import "../../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
11:import "../../lib/libraries/Uniswap/LowGasSafeMath.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
12:import "../../lib/libraries/Uniswap/LiquidityMath.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
13:import "../../lib/libraries/Uniswap/Tick.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
14:import "../../lib/libraries/Uniswap/SafeCast.sol";
``` 



File:ConveyorTickMath.sol 
```solidity
15:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:ConveyorRouterV1.sol 
```solidity
3:import "./ConveyorErrors.sol";
``` 



File:CafeSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:CafeSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:CafeSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:NomiswapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:NomiswapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:NomiswapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:WaultSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:WaultSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:WaultSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:SakeSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:SakeSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:SakeSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:PancakeV3Callback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:BiswapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:BiswapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:BiswapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:IConveyorExecutor.sol 
```solidity
3:import "../LimitOrderBook.sol";
``` 



File:IConveyorExecutor.sol 
```solidity
4:import "../SandboxLimitOrderBook.sol";
``` 



File:IConveyorExecutor.sol 
```solidity
5:import "../SandboxLimitOrderRouter.sol";
``` 



File:JetSwapCallback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:JetSwapCallback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:JetSwapCallback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
3:import "../lib/interfaces/token/IERC20.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
4:import "../lib/interfaces/uniswap-v2/IUniswapV2Factory.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
5:import "../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
6:import "../lib/interfaces/uniswap-v3/IUniswapV3Factory.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
7:import "../lib/interfaces/uniswap-v3/IUniswapV3Pool.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
8:import "./lib/ConveyorMath.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
9:import "./LimitOrderBook.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
10:import "./lib/ConveyorTickMath.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
11:import "../lib/libraries/Uniswap/FullMath.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
12:import "../lib/libraries/Uniswap/FixedPoint96.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
13:import "../lib/libraries/Uniswap/TickMath.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
14:import "../lib/interfaces/token/IWETH.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
15:import "./lib/ConveyorFeeMath.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
16:import "../lib/libraries/Uniswap/SqrtPriceMath.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
17:import "../lib/interfaces/uniswap-v3/IQuoter.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
18:import "../lib/libraries/token/SafeERC20.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
19:import "./ConveyorErrors.sol";
``` 



File:LimitOrderSwapRouter.sol 
```solidity
20:import "./interfaces/ILimitOrderSwapRouter.sol";
``` 



File:PancakeV2Callback.sol 
```solidity
3:import "../../lib/interfaces/token/IERC20.sol";
``` 



File:PancakeV2Callback.sol 
```solidity
4:import "../../lib/interfaces/uniswap-v2/IUniswapV2Pair.sol";
``` 



File:PancakeV2Callback.sol 
```solidity
5:import "../lib/OracleLibraryV2.sol";
``` 



File:ILimitOrderSwapRouter.sol 
```solidity
3:import "../LimitOrderSwapRouter.sol";
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-4]></a> [NC-4] 
 <h3> Constants & Immutables should be named with screaming snake case - Instances: 6 </h3> 
 </summary>
 Consider renaming to follow convention 

File:ConveyorMath.sol 
```solidity
7:    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
``` 



File:ConveyorMath.sol 
```solidity
12:    int128 private constant MIN_64x64 = -0x80000000000000000000000000000000;
``` 



File:ConveyorMath.sol 
```solidity
15:    uint256 private constant MAX_128x128 = 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
100:    uint128 private constant MIN_FEE_64x64 = 18446744073709552;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
104:    uint256 private constant ONE_128x128 = uint256(1) << 128;
``` 



File:ConveyorTickMath.sol 
```solidity
27:    uint128 private constant MAX_64x64 = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-5]></a> [NC-5] 
 <h3> Consider using scientific notation for large multiples of 10 - Instances: 17 </h3> 
 </summary>
 For example 100000 can be written as 1e5 

File:LimitOrderSwapRouter.sol 
```solidity
101:    uint128 private constant BASE_SWAP_FEE = 55340232221128660;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
106:    uint256 private constant ZERO_POINT_NINE = 16602069666338597000 << 64;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
107:    uint256 private constant ONE_POINT_TWO_FIVE = 23058430092136940000 << 64;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
108:    uint128 private constant ZERO_POINT_ONE = 1844674407370955300;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
109:    uint128 private constant ZERO_POINT_ZERO_ZERO_FIVE = 92233720368547760;
``` 



File:LimitOrderSwapRouter.sol 
```solidity
110:    uint128 private constant ZERO_POINT_ZERO_ZERO_ONE = 18446744073709550;
``` 



File:ConveyorFeeMath.sol 
```solidity
8:    uint128 constant ZERO_POINT_ZERO_ZERO_FIVE = 92233720368547760;
``` 



File:ConveyorFeeMath.sol 
```solidity
9:    uint128 constant ZERO_POINT_ZERO_ZERO_ONE = 18446744073709550;
``` 



File:ConveyorFeeMath.sol 
```solidity
10:    uint128 constant MAX_CONVEYOR_PERCENT = 110680464442257300 * 10 ** 2;
``` 



File:ConveyorFeeMath.sol 
```solidity
11:    uint128 constant MIN_CONVEYOR_PERCENT = 7378697629483821000;
``` 



File:ConveyorRouterV1.sol 
```solidity
26:    uint128 private constant AFFILIATE_PERCENT = 5534023222112865000;
``` 



File:ConveyorRouterV1.sol 
```solidity
27:    uint128 private constant REFERRAL_PERCENT = 5534023222112865000;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
32:    uint256 private constant REFRESH_INTERVAL = 2592000;
``` 



File:SandboxLimitOrderBook.sol 
```solidity
38:    uint256 private constant REFRESH_FEE = 20000000000000000;
``` 



File:ConveyorExecutor.sol 
```solidity
34:    uint128 private constant STOP_LOSS_MAX_BEACON_REWARD = 50000000000000000;
``` 



File:LimitOrderRouter.sol 
```solidity
48:    uint256 private constant REFRESH_INTERVAL = 2592000;
``` 



File:LimitOrderRouter.sol 
```solidity
52:    uint256 private constant REFRESH_FEE = 20000000000000000;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-6]></a> [NC-6] 
 <h3> Remove any unused functions - Instances: 28 </h3> 
 </summary>
  

File:OracleLibraryV2.sol 
```solidity
4:    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut, uint24 swapFee)
5:        internal
6:        pure
7:        returns (uint256 amountIn)
8:    {
``` 



File:ConveyorMath.sol 
```solidity
140:    function mul64U(uint128 x, uint256 y) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
105:    function add128x64(uint256 x, uint128 y) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
30:    function toUInt64(uint128 x) internal pure returns (uint64) {
``` 



File:ConveyorMath.sol 
```solidity
39:    function fromUInt128(uint128 x) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
95:    function add128x128(uint256 x, uint256 y) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
127:    function mul128x64(uint256 x, uint128 y) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
216:    function divUU(uint256 x, uint256 y) internal pure returns (uint128) {
``` 



File:ConveyorMath.sol 
```solidity
83:    function sub(int128 x, int128 y) internal pure returns (int128) {
``` 



File:ConveyorMath.sol 
```solidity
20:    function fromUInt256(uint256 x) internal pure returns (uint128) {
``` 



File:ConveyorMath.sol 
```solidity
61:    function to128x128(uint128 x) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
71:    function add64x64(uint128 x, uint128 y) internal pure returns (uint128) {
``` 



File:ConveyorMath.sol 
```solidity
517:    function sqrtu(uint256 x) internal pure returns (uint128) {
``` 



File:ConveyorMath.sol 
```solidity
115:    function mul64x64(uint128 x, uint128 y) internal pure returns (uint128) {
``` 



File:ConveyorMath.sol 
```solidity
197:    function div128x128(uint256 x, uint256 y) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
287:    function fromX64ToX16(uint128 x) internal pure returns (uint32) {
``` 



File:ConveyorMath.sol 
```solidity
182:    function div64x64(uint128 x, uint128 y) internal pure returns (uint128) {
``` 



File:ConveyorMath.sol 
```solidity
161:    function mul128U(uint256 x, uint256 y) internal pure returns (uint256) {
``` 



File:ConveyorMath.sol 
```solidity
172:    function abs(int256 x) internal pure returns (int256) {
``` 



File:ConveyorMath.sol 
```solidity
50:    function from128x128(uint256 x) internal pure returns (uint128) {
``` 



File:ConveyorMath.sol 
```solidity
506:    function exp(uint128 x) internal pure returns (uint128) {
``` 



File:ConveyorTickMath.sol 
```solidity
68:    function fromSqrtX96(uint160 sqrtPriceX96, bool token0IsReserve0, address token0, address token1)
69:        internal
70:        view
71:        returns (uint256 priceX128)
72:    {
``` 



File:ConveyorTickMath.sol 
```solidity
102:    function simulateAmountOutOnSqrtPriceX96(
103:        address token0,
104:        address tokenIn,
105:        address pool,
106:        uint256 amountIn,
107:        int24 tickSpacing,
108:        uint128 liquidity,
109:        uint24 fee
110:    ) internal view returns (uint128 amountOut, uint160 sqrtPriceX96) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
294:    function _swap(
295:        address _tokenIn,
296:        address _tokenOut,
297:        address _lp,
298:        uint24 _fee,
299:        uint256 _amountIn,
300:        uint256 _amountOutMin,
301:        address _receiver,
302:        address _sender
303:    ) internal returns (uint256 amountReceived) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
213:    function _transferTokensOutToOwner(address orderOwner, uint256 amount, address tokenOut) internal {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
221:    function _transferBeaconReward(uint256 totalBeaconReward, address executorAddress, address weth) internal {
``` 



File:LimitOrderBook.sol 
```solidity
495:    function _removeOrderFromSystem(bytes32 orderId) internal {
``` 



File:LimitOrderBook.sol 
```solidity
510:    function _resolveCompletedOrder(bytes32 orderId) internal {
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-7]></a> [NC-7] 
 <h3> Storage variables should be named with camel case - Instances: 1 </h3> 
 </summary>
 Consider renaming to follow convention 

File:ConveyorRouterV1.sol 
```solidity
20:    address public CONVEYOR_MULTICALL;
``` 

 
 </details>

 <details open> 
 <summary> 
 <a name=[NC-8]></a> [NC-8] 
 <h3> Remove any unused returns - Instances: 11 </h3> 
 </summary>
  

File:SandboxLimitOrderBook.sol 
```solidity
559:    function validateAndCancelOrder(bytes32 orderId) external nonReentrant returns (bool success) {
``` 



File:SandboxLimitOrderBook.sol 
```solidity
1177:    function getTotalOrdersValue(address token) public view returns (uint256 totalOrderValue) {
``` 



File:ConveyorRouterV1.sol 
```solidity
259:    function quoteSwapExactTokenForToken(
260:        TokenToTokenSwapData calldata swapData,
261:        SwapAggregatorMulticall calldata swapAggregatorMulticall
262:    ) external payable returns (uint256 gasConsumed) {
``` 



File:ConveyorRouterV1.sol 
```solidity
275:    function quoteSwapExactEthForToken(
276:        EthToTokenSwapData calldata swapData,
277:        SwapAggregatorMulticall calldata swapAggregatorMulticall
278:    ) external payable returns (uint256 gasConsumed) {
``` 



File:ConveyorRouterV1.sol 
```solidity
291:    function quoteSwapExactTokenForEth(
292:        TokenToEthSwapData calldata swapData,
293:        SwapAggregatorMulticall calldata swapAggregatorMulticall
294:    ) external payable returns (uint256 gasConsumed) {
``` 



File:LimitOrderBook.sol 
```solidity
536:    function getTotalOrdersValue(address token) public view returns (uint256 totalOrderValue) {
``` 



File:LimitOrderRouter.sol 
```solidity
110:    function _refreshLimitOrder(LimitOrder memory order) internal returns (uint256 executorFee) {
``` 



File:LimitOrderRouter.sol 
```solidity
152:    function validateAndCancelOrder(bytes32 orderId) external nonReentrant returns (bool success) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
320:    function _swapV3(
321:        address _lp,
322:        address _tokenIn,
323:        address _tokenOut,
324:        uint24 _fee,
325:        uint256 _amountIn,
326:        uint256 _amountOutMin,
327:        address _receiver,
328:        address _sender
329:    ) internal returns (uint256 amountReceived) {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
576:    function getAllPrices(address token0, address token1, uint24 FEE)
577:        public
578:        view
579:        returns (SpotReserve[] memory prices, address[] memory lps)
580:    {
``` 



File:LimitOrderSwapRouter.sol 
```solidity
576:    function getAllPrices(address token0, address token1, uint24 FEE)
577:        public
578:        view
579:        returns (SpotReserve[] memory prices, address[] memory lps)
580:    {
``` 

 
 </details> 
 </details>
