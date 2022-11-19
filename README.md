# Conveyor Limit Orders v0
The core smart contracts of the Conveyor Limit Orders protocol.

## Build Instructions
First Clone the Repository
```sh
git clone https://github.com/ConveyorLabs/LimitOrders-v0 && cd LimitOrders-v0
```
### Run The Test Suite
```sh
 forge test -f <RPC_URL> --ffi --fork-block-number 15233771
 //Run a individual Test 
 forge test -f <RPC_URL> --ffi --fork-block-number 15233771 --match-contract LimitOrderRouterTest --match-test testOnlyEOA 

```
### Forge Coverage
```sh
 forge coverage -f <RPC_URL> --ffi --fork-block-number 15233771

```

### Forge Snapshot
```sh
 forge snapshot -f <RPC_URL> --ffi --fork-block-number 15233771

```

### Detailed Gas Report 
```sh
 forge test -f <RPC_URL> --ffi --fork-block-number 15233771  --gas-report

```





