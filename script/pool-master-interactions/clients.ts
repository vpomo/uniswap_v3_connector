import { createPublicClient, createWalletClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { arbitrumSepolia } from 'viem/chains';
import 'dotenv/config';

const rpcUrl = process.env.ARBITRUM_SEPOLIA_RPC_URL;
if (!rpcUrl) {
  throw new Error("ARBITRUM_SEPOLIA_RPC_URL is not set in .env file");
}

export const publicClient = createPublicClient({
  chain: arbitrumSepolia,
  transport: http(rpcUrl),
});

const adminPrivateKey = process.env.ADMIN_PRIVATE_KEY;
if (!adminPrivateKey) {
  throw new Error("ADMIN_PRIVATE_KEY is not set in .env file");
}
export const adminAccount = privateKeyToAccount(adminPrivateKey as `0x${string}`);
export const adminWalletClient = createWalletClient({
  account: adminAccount,
  chain: arbitrumSepolia,
  transport: http(rpcUrl),
});

const userPrivateKey = process.env.USER_PRIVATE_KEY;
if (!userPrivateKey) {
    throw new Error("USER_PRIVATE_KEY is not set in .env file");
}
export const userAccount = privateKeyToAccount(userPrivateKey as `0x${string}`);
export const userWalletClient = createWalletClient({
    account: userAccount,
    chain: arbitrumSepolia,
    transport: http(rpcUrl),
});
