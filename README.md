# ERC-948
Groundhog ERC-948 proposal

# What are we trying to achieve? 

An ERC-948 compliant non custodial solution that enables a multitude of devices to interact on behalf on the wallet.

Our implementation will feature a multisignature wallet that also supports a subset of transactions to have subscription based qualitites. 

Recurring payments

Decentralized App Payments/Interactions

Different types of transaction


ETH held in escrow by the contract


ERC20's held in escrow by the contract


ERC20's that are leveraged using a transferProxy(in this case the actual contract itself) this is up for 
debate as you might want the proxy you control to be upgradeable, or to leverage a proxy that exists elsewhere. 

txDestination is the actual address the broadcasted transaction is going to target. 

This address can be either a normal address or a contract(in cases of tokens, the Token Smart Contract address)

