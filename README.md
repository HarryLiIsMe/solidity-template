# ZK Game Solidity Template

快速開發各種 ZK Game 用的 solidity template project

## Dev Goals

- 加入 zk lib
- 測試 mock
- deploy Findora 驗證

https://hackmd.io/@nmohnblatt/SJKJfVqzq#

1. player pk -> player public key ??

2. 集合所有 pub key 生成 aggregate pub key (no secret key)


## Guides

### GSC Testnet 快速 restart

```bash
$ ln -s env/gsc.testnet.0xbbbb690a9B1ACdbF0e7BAE4f9aCB457703f02556.env .env

# step1: 從 Genisis wallet 轉 gas 至 deployer wallet:
$ yarn hardhat run scripts/transfer.ts

# step2: Deploy 共用 contracts:
$ yarn hardhat run scripts/deploy-multicall.ts

# step3: Deploy example contracts
$ yarn hardhat run scripts/deploy-poker.ts
```
