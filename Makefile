-include .env

install:
	@echo "Installing dependencies..."
	@forge install openzeppelin/openzeppelin-contracts@v5.0.2 --no-commit && forge install cyfrin/foundry-devops@0.2.2 --no-commit && forge install smartcontractkit/chainlink-brownie-contracts@0.6.1 --no-commit
	

RPC_PARAMS = --rpc-url http://127.0.0.1:8545 --private-key $(ANVIL_PRIVATE_KEY) 

ifeq ($(RPC),testnet)
	RPC_PARAMS = --fork-url $(SEPOLIA_RPC_URL) --account $(ACCOUNT_NAME)
endif

deploy:
	@echo "Deploying contracts..."
	forge script script/DeployDSC.s.sol $(RPC_PARAMS) --broadcast

deposit: ARGS = weth 1000000000000000000
deposit:
	@echo "Depositing funds..."
	forge script script/Interactions.s.sol:DepositCollateral $(RPC_PARAMS) --broadcast $(ARGS) --sig "run(string,uint256)"

mintWeth: ARGS = 1000000000000000000
mintWeth:
	@echo "Minting WETH..."
	forge script script/Interactions.s.sol:MintWeth $(RPC_PARAMS) --broadcast $(ARGS) --sig "run(uint256)"

getWethBalance:
	@echo "Getting WETH balance..."
	forge script script/Interactions.s.sol:GetWethBalance $(RPC_PARAMS) --broadcast $(ARGS) --sig "run()"

redeem: ARGS = weth 1000000000000000000
redeem:
	@echo "Redeeming funds..."
	forge script script/Interactions.s.sol:RedeemCollateral $(RPC_PARAMS) --broadcast $(ARGS) --sig "run(string,uint256)"

getCollateral: ARGS = weth
getCollateral:
	@echo "Getting collateral..."
	forge script script/Interactions.s.sol:GetCollateral $(RPC_PARAMS) --broadcast $(ARGS) --sig "run(string)"

mint: ARGS = 1000000000000000000
mint:
	@echo "Minting..."
	forge script script/Interactions.s.sol:Mint $(RPC_PARAMS) --broadcast $(ARGS) --sig "run(uint256)"

getMintedDsc:
	@echo "Getting minted DSC..."
	forge script script/Interactions.s.sol:GetMintedDsc $(RPC_PARAMS) --broadcast $(ARGS) --sig "run()"

burn: ARGS = 1000000000000000000
burn:
	@echo "Burning..."
	forge script script/Interactions.s.sol:Burn $(RPC_PARAMS) --broadcast $(ARGS) --sig "run(uint256)"

getHealthFactor:
	@echo "Getting health factor..."
	forge script script/Interactions.s.sol:GetHealthFactor $(RPC_PARAMS) --broadcast $(ARGS) --sig "run()"