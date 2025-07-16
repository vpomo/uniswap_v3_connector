import { type Abi } from 'viem';

export const contractAddress = '0x1efc8d699d20c030b393Ffbf406cf2C317383ddf';

export const contractAbi = [
  {
    "type": "function",
    "name": "swapExactInputSingle",
    "inputs": [
      { "name": "_amountIn", "type": "uint256", "internalType": "uint256" },
      { "name": "_minAmountOut", "type": "uint256", "internalType": "uint256" },
      { "name": "_zeroForOne", "type": "bool", "internalType": "bool" }
    ],
    "outputs": [
      { "name": "amountOut", "type": "uint256", "internalType": "uint256" }
    ],
    "stateMutability": "payable"
  },
  {
    "type": "function",
    "name": "collectPoolAllFees",
    "inputs": [],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "mintPosition",
    "inputs": [
      { "name": "_tickLower", "type": "int24", "internalType": "int24" },
      { "name": "_tickUpper", "type": "int24", "internalType": "int24" },
      { "name": "_amount0Max", "type": "uint256", "internalType": "uint256" },
      { "name": "_amount1Max", "type": "uint256", "internalType": "uint256" }
    ],
    "outputs": [
      { "name": "tokenId", "type": "uint256", "internalType": "uint256" },
      { "name": "liquidity", "type": "uint128", "internalType": "uint128" },
      { "name": "amount0", "type": "uint256", "internalType": "uint256" },
      { "name": "amount1", "type": "uint256", "internalType": "uint256" }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "burnPosition",
    "inputs": [
      { "name": "_tokenId", "type": "uint256", "internalType": "uint256" },
      { "name": "_amount0Min", "type": "uint256", "internalType": "uint256" },
      { "name": "_amount1Min", "type": "uint256", "internalType": "uint256" }
    ],
    "outputs": [],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "increaseLiquidity",
    "inputs": [
      { "name": "_tokenId", "type": "uint256", "internalType": "uint256" },
      { "name": "_amount0Max", "type": "uint128", "internalType": "uint128" },
      { "name": "_amount1Max", "type": "uint128", "internalType": "uint128" }
    ],
    "outputs": [
      { "name": "liquidity", "type": "uint128", "internalType": "uint128" },
      { "name": "amount0", "type": "uint256", "internalType": "uint256" },
      { "name": "amount1", "type": "uint256", "internalType": "uint256" }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "decreaseLiquidity",
    "inputs": [
      { "name": "_tokenId", "type": "uint256", "internalType": "uint256" },
      { "name": "_liquidity", "type": "uint128", "internalType": "uint128" },
      { "name": "_amount0Min", "type": "uint256", "internalType": "uint256" },
      { "name": "_amount1Min", "type": "uint256", "internalType": "uint256" }
    ],
    "outputs": [
      { "name": "amount0", "type": "uint256", "internalType": "uint256" },
      { "name": "amount1", "type": "uint256", "internalType": "uint256" }
    ],
    "stateMutability": "nonpayable"
  },
  {
    "type": "function",
    "name": "getDynamicInfo",
    "inputs": [
      { "name": "_tokenId", "type": "uint256", "internalType": "uint256" }
    ],
    "outputs": [
      { "name": "price", "type": "uint256", "internalType": "uint256" },
      { "name": "currentTick", "type": "int24", "internalType": "int24" },
      { "name": "amount0", "type": "uint256", "internalType": "uint256" },
      { "name": "amount1", "type": "uint256", "internalType": "uint256" }
    ],
    "stateMutability": "view"
  }
] as const satisfies Abi;

