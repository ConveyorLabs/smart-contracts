# Conveyor Smart Contracts
The core smart contracts of the Conveyor protocol.

## Build Instructions
First Clone the Repository
```sh
git clone https://github.com/ConveyorLabs/smart-contracts && cd smart-contracts
```
### Run The Test Suite
```sh
 forge test -f <RPC_URL> --ffi 
```
### Forge Coverage
```sh
 forge coverage -f <RPC_URL> --ffi 

```

### Forge Snapshot
```sh
 forge snapshot -f <RPC_URL> --ffi 

```

### Detailed Gas Report 
```sh
 forge test -f <RPC_URL> --ffi --gas-report

```


