
# STABLE COIN - DSC

stablecoins are a vital component of the cryptocurrency ecosystem, offering stability, liquidity, and utility. They bridge the gap between traditional finance and blockchain technology, enabling a wide range of use cases, from everyday transactions to decentralized finance. As the adoption of cryptocurrencies continues to grow, the importance of stablecoins is expected to increase further.






## Deployment

Spin up the Anvil chain

```
  make deploy
```

Deploy on Anvil

```
make deploy
```
Test

```
forge test 
```
Coverage 

```
forge coverage
```


## Scripts

1.Get Weth:

```
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "deposit()" --value 0.1ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

2.Approve Weth:

```
cast send 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 "approve(address,uint256)" 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 1000000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

3.Deposit and MintDsc :
```
cast send 0x091EA0838eBD5b7ddA2F2A641B068d6D59639b98 "depositCollateralAndMintDsc(address,uint256,uint256)" 0xdd13E55209Fd76AfE204dBda4007C227904f0a81 100000000000000000 10000000000000000 --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

## Thank U 


