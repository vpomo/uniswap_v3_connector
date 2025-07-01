# Makefile for running foundry tests
# Usage:
# - Prerequisites:
#   - Run `yarn install` to install all dependencies via Yarn.
#   - Run `foundryup` to ensure Foundry is up-to-date.
#   - Run `forge install` to install all foundry dependencies.
# - Commands:
#   - `make install`         : Install all dependencies defined in .gitmodules using Foundry's forge install.
#   - `make run_fork`        : Run an anvil fork on the BASE_LOCAL_FORK_PORT using the base RPC URL.
#   - `make run_arb_fork`    : Run an anvil fork on the ARB_LOCAL_FORK_PORT using the ARB RPC URL.
#   - `make test`            : Run all tests using forge with any optional arguments specified in --args.
#                              For example: `make test args="--match-test Deposit"`

include ./.env

ENV_FILES := ./.env
export $(shell cat $(ENV_FILES) | sed 's/=.*//' | sort | uniq)
#args = -vvv
args =

all: test

install:
	grep -E '^\s*url' ./.gitmodules | awk '{print $$3}' | xargs -I {} sh -c 'forge install {}'

test:
	forge test $(args)

gas_snapshot:
	sudo forge snapshot --mp "./test/foundry/src/gas/*.gas.sol"

coverage:
	forge coverage --skip "script/**" --report lcov
	sudo genhtml --ignore-errors inconsistent --ignore-errors corrupt --ignore-errors category -o ./coverage_report ./lcov.info
# open ./coverage_report/index.html
# rm -rf lcov.info

.PHONY: all test
