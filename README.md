# Stablecoin Project

This project is heavily based on the course from Cyfrin updraft [Advanced Foundry course](https://updraft.cyfrin.io/courses/advanced-foundry)

The contracts were deployed on the sepolia testnet:

- DecentralizedStableCoin: [0xb92d164E5C9BA23E9969964b52cE9A9760F7487c](https://sepolia.etherscan.io/address/0xb92d164e5c9ba23e9969964b52ce9a9760f7487c)
- DSCEngine: [0x9072d9a817786797B85e542CF81b871303585AA3](https://sepolia.etherscan.io/address/0x9072d9a817786797b85e542cf81b871303585aa3)

The DecentralizedStableCoin contract has also been verified, however I was not able to verify the DSCEngine contract.

## Features

It features DSC, An algorithmic ERC20 stablecoin pegged to 1 USD, collateralized by ETH and BTC.

The minting and burning logic of the DSC is handled by the DSCEngine contract, which allows users to deposit collateral, as wETH or wBTC, mint DSC and also redeem their collateral.

The protocol also allows to liquidate undercollateralized users by burning the liquidator's DSC to reduce the undercollateralized user's debt and claim part of their collateral, with a bonus (currently set to 10%).

## Deployment

This project also includes deployment scripts, to help deploying the contracts to sepolia ethereum testnet or a custom local anvil testnet.

These deployments scripts also help testing the contracts, by allowing easier setup of the environment before the tests.

I also added an Interactions file, which allows users to easily interact with the contract, either on the anvil chain or sepolia test.

## Tests

In this project, we also wrote test to ensure that the contracts were behaving as expected. We only wrote tests for the DSCEngine contract, including invariant testing as we discovered how to write stateful fuzzing tests, i.e. tests where several functions are called with pseudo-random values (we still add constraints to avoid reverts, such as making sure we are using valid addresses) while keeping the state of the contract after the last function call.

The coverage of the tests on DSCEngine is of 87.5% of the contract's lines.

# Getting started

## Foundry

The project uses the Foundry smart contract development toolkit, [click here](https://updraft.cyfrin.io/courses/advanced-foundry) to get started with foundry.

## Install dependencies

Use this method to install the project dependencies:

```
make install
```

## Deploying

The contracts are by default deployed on an anvil test chain
To run the anvil chain:

```
anvil
```

To send transactions on the anvil chain, you will first need to set the `ANVIL_PRIVATE_KEY` variable in a .env file. you can chose the anvil private key you want to use from the list given when using the `anvil` command.

To deploy the contracts:

```
make deploy
```

## Interacting with the contract

### Currently only works on anvil chain as it tries to mint the required collateral

To deposit collateral:

```
make deposit ARGS="<token> <amount in ether>"
```

The available values for "token" are: weth, wbtc

As suggested, the amount given will be multiplied by 1e18

For example, using

```
make deposit ARGS="weth 1"
```

will deposit 1 wETH to the contract

To redeem:

```
make redeem ARGS="<token> <value in ether>"
```

To view the current deposited collateral for a given token:

```
make getCollateral ARGS="<token>"
```

There are also a few other functions to discover, including minting some DSC, viewing the current health factor ...

By default, if you do not enter any ARGS value, the collateral token will be set to weth, and the amount to 1e18.

## Deploying to other chains

Also, you can use those functions on sepolia testnet by adding "RPC=testnet" to the above functions, as in the example:

```
make deploy RPC=testnet
```

Will deploy the contracts to the sepolia Ethereum testnet.

For this to work, you will need to have a .env file with your sepolia rpc url set in `SEPOLIA_RPC_URL`, as well as an account, which you can learn how to create using `cast wallet --help`. You also need to set the chosen account name as the variable `ACCOUNT_NAME` of the .env file.

## Testing

You can perform tests on the project by using the command:

```
forge test
```

You can also see the coverage of the current tests with

```
forge coverage
```
