#!/bin/bash
set -a
source .env
set +a

forge script script/foundry/DeployUserTokenB.s.sol:DeployUserToken \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify \
  --verifier custom \
  --verifier-url https://api-sepolia.arbiscan.io/api \
  --verifier-api-key $ARBISCAN_API_KEY
