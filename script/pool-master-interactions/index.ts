import { publicClient, adminWalletClient, userWalletClient, adminAccount, userAccount } from './clients';
import { contractAddress, contractAbi } from './config';

/**
 * Вызывает view-функцию getDynamicInfo для получения информации о позиции.
 * @param tokenId ID токена позиции NFT.
 */
async function getDynamicInfo(tokenId: bigint) {
  console.log(`\n[READ] Reading dynamic info for tokenId: ${tokenId}...`);
  try {
    // readContract используется для вызова view/pure функций
    // https://web3auth.io/docs/connect-blockchain/evm/arbitrum/web
    const data = await publicClient.readContract({
      address: contractAddress,
      abi: contractAbi,
      functionName: 'getDynamicInfo',
      args: [tokenId],
    });
    console.log('Dynamic Info:', {
        price: data[0],
        currentTick: data[1],
        amount0: data[2],
        amount1: data[3],
    });
    return data;
  } catch (error) {
    console.error('Error reading dynamic info:', error);
  }
}

/**
 * Вызывает функцию swapExactInputSingle для обмена токенов.
 * @param amountIn Количество токенов для обмена (в wei).
 * @param minAmountOut Минимальное количество токенов, которое ожидается получить.
 * @param zeroForOne Направление обмена (true для token0 -> token1).
 */
async function swapExactInputSingle(amountIn: bigint, minAmountOut: bigint, zeroForOne: boolean) {
  console.log(`\n[WRITE] Swapping ${amountIn} tokens...`);
  try {
    // writeContract используется для вызова функций, изменяющих состояние
    // https://viem.sh/docs/contract/writeContract.html
    const hash = await userWalletClient.writeContract({
      address: contractAddress,
      abi: contractAbi,
      functionName: 'swapExactInputSingle',
      args: [amountIn, minAmountOut, zeroForOne],
      account: userAccount, // Указываем аккаунт пользователя
    });
    console.log(`Transaction sent! Hash: ${hash}`);
    
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    //console.log('Transaction confirmed! Receipt:', receipt);
    return receipt;
  } catch (error) {
    console.error('Error during swap:', error);
  }
}

/**
 * Собирает все комиссии со всех позиций.
 */
async function collectPoolAllFees() {
    console.log(`\n[WRITE] Collecting all pool fees...`);
    try {
        const hash = await userWalletClient.writeContract({
            address: contractAddress,
            abi: contractAbi,
            functionName: 'collectPoolAllFees',
            args: [],
            account: userAccount,
        });
        console.log(`Transaction sent! Hash: ${hash}`);
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        //console.log('Transaction confirmed! Receipt:', receipt);
        return receipt;
    } catch (error) {
        console.error('Error collecting fees:', error);
    }
}

/**
 * Создает новую позицию ликвидности. (Требует ADMIN_ROLE)
 * @param tickLower Нижний тик.
 * @param tickUpper Верхний тик.
 * @param amount0Max Максимальное количество токена0.
 * @param amount1Max Максимальное количество токена1.
 */
async function mintPosition(tickLower: number, tickUpper: number, amount0Max: bigint, amount1Max: bigint) {
  console.log(`\n[ADMIN-WRITE] Minting new position...`);
  try {
    const hash = await adminWalletClient.writeContract({
      address: contractAddress,
      abi: contractAbi,
      functionName: 'mintPosition',
      args: [tickLower, tickUpper, amount0Max, amount1Max],
      account: adminAccount, // Используем кошелек администратора
    });
    console.log(`Transaction sent! Hash: ${hash}`);
    const receipt = await publicClient.waitForTransactionReceipt({ hash });
    //console.log('Transaction confirmed! Receipt:', receipt);
    return receipt;
  } catch (error) {
    console.error('Error minting position:', error);
  }
}

/**
 * Сжигает позицию ликвидности. (Требует ADMIN_ROLE)
 * @param tokenId ID токена позиции.
 * @param amount0Min Минимальное количество токена0 для вывода.
 * @param amount1Min Минимальное количество токена1 для вывода.
 */
async function burnPosition(tokenId: bigint, amount0Min: bigint, amount1Min: bigint) {
    console.log(`\n[ADMIN-WRITE] Burning position with tokenId: ${tokenId}...`);
    try {
        const hash = await adminWalletClient.writeContract({
            address: contractAddress,
            abi: contractAbi,
            functionName: 'burnPosition',
            args: [tokenId, amount0Min, amount1Min],
            account: adminAccount,
        });
        console.log(`Transaction sent! Hash: ${hash}`);
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        //console.log('Transaction confirmed! Receipt:', receipt);
        return receipt;
    } catch (error) {
        console.error('Error burning position:', error);
    }
}

/**
 * Увеличивает ликвидность существующей позиции. (Требует ADMIN_ROLE)
 * @param tokenId ID токена позиции.
 * @param amount0Max Максимальное количество токена0 для добавления.
 * @param amount1Max Максимальное количество токена1 для добавления.
 */
async function increaseLiquidity(tokenId: bigint, amount0Max: bigint, amount1Max: bigint) {
    console.log(`\n[ADMIN-WRITE] Increasing liquidity for tokenId: ${tokenId}...`);
    try {
        const hash = await adminWalletClient.writeContract({
            address: contractAddress,
            abi: contractAbi,
            functionName: 'increaseLiquidity',
            args: [tokenId, amount0Max, amount1Max],
            account: adminAccount,
        });
        console.log(`Transaction sent! Hash: ${hash}`);
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        //console.log('Transaction confirmed! Receipt:', receipt);
        return receipt;
    } catch (error) {
        console.error('Error increasing liquidity:', error);
    }
}

/**
 * Уменьшает ликвидность существующей позиции. (Требует ADMIN_ROLE)
 * @param tokenId ID токена позиции.
 * @param liquidity Количество ликвидности для изъятия.
 * @param amount0Min Минимальное количество токена0 для вывода.
 * @param amount1Min Минимальное количество токена1 для вывода.
 */
async function decreaseLiquidity(tokenId: bigint, liquidity: bigint, amount0Min: bigint, amount1Min: bigint) {
    console.log(`\n[ADMIN-WRITE] Decreasing liquidity for tokenId: ${tokenId}...`);
    try {
        const hash = await adminWalletClient.writeContract({
            address: contractAddress,
            abi: contractAbi,
            functionName: 'decreaseLiquidity',
            args: [tokenId, liquidity, amount0Min, amount1Min],
            account: adminAccount,
        });
        console.log(`Transaction sent! Hash: ${hash}`);
        const receipt = await publicClient.waitForTransactionReceipt({ hash });
        //console.log('Transaction confirmed! Receipt:', receipt);
        return receipt;
    } catch (error) {
        console.error('Error decreasing liquidity:', error);
    }
}


async function main() {
//  await getDynamicInfo(2107n);

//  await swapExactInputSingle(100000000000000000n, 0n, true);

//  await getDynamicInfo(2107n);

//  await swapExactInputSingle(100000000000000000n, 0n, false);

//  await getDynamicInfo(2107n);

//  await collectPoolAllFees();

//  await increaseLiquidity(2107n, 500000n, 500000n);

//  await getDynamicInfo(2107n);

//  await decreaseLiquidity(2107n, 100000n, 0n, 0n);

//  await getDynamicInfo(2107n);


   await burnPosition(2107n, 0n, 0n);
   await mintPosition(31920, 39060, 5000000000000000000000n, 5000000000000000000000n);
//  await burnPosition(2108n, 0n, 0n);
}

//49 - uni4
//2110 - uni3
main().catch(console.error);
