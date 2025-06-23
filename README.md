# Aera Protocol V3

[![CI](https://github.com/aera-finance/aera-contracts-v3/actions/workflows/ci.yml/badge.svg)](https://github.com/aera-finance/aera-contracts-v3/actions/workflows/ci.yml)

Tools used:

- [Foundry](https://github.com/foundry-rs/foundry): Compile and run the smart contracts on a local development network
- [Slither](https://github.com/crytic/slither): solidity analyzer
- [Solhint](https://github.com/protofire/solhint): linter

## Usage

Before running any command, make sure to install dependencies:

```sh
$ forge install
$ git submodule update --init --recursive
```

Then, copy the example environment file into an `.env` file like so:

```sh
$ cp .env.example .env
```

Finally, install the pre-commit hooks:

```sh
$ pip3 install pre-commit  # Install pre-commit
$ pre-commit -V            # Confirm installation
$ pre-commit install       # Install the hooks
```

Team secrets are managed in
[GCP secret manager](https://console.cloud.google.com/security/secret-manager?project=gauntlet-sim). If you don't have
access, you need to be added to engineering@gauntlet.network

## Documentation

Detailed documentation generated from the NatSpec documentation of the contracts can be found [here](./docs/autogen/src/SUMMARY.md).

Alternatively, once you run `make docs`, you can view them as an HTML page [here](./docs/autogen/book/index.html) (docs -> autogen -> book -> index.html)

## Available Commands

Check all the commands that you can use:

```sh
$ make help
```

### Compile

Compile the smart contracts with Forge:

```sh
$ make build
```

### Generate Docs

Generate the docs:

```sh
$ make docs
```

#### Note

If you encounter permission issues with scripts, run:

```sh
$ chmod +x ./script/util/doc_gen.sh
```

### Analyze Solidity

Analyze the Solidity code:

```sh
$ make slither
```

### Lint Solidity

Lint the Solidity code:

```sh
$ make lint
```

### Test

Run the forge tests:

```sh
$ make test
```

Tests run against forks of target environments (ie Mainnet, Polygon) and require a node provider to be authenticated in
your [.env](./.env).

### Coverage

Generate the coverage report with env variables:

```sh
$ make coverage-report
```

Check if the coverage is above the minimum:

```sh
$ make coverage-check
```

### Report Gas

See the gas usage per unit test and average gas per method call:

```sh
$ make gas-report
```

Create a snapshot:

```sh
$ make snapshot
```

or check the diff between the current snapshot and the previous one:

```sh
$ make snapshot-diff
```

### Clean

Delete the smart contract artifacts and cache directories:

```sh
$ make clean
```

## Syntax Highlighting

If you use VSCode, you can enjoy syntax highlighting for your Solidity code via the
[vscode-solidity](https://github.com/juanfranblanco/vscode-solidity) extension. The recommended approach to set the
compiler version is to add the following fields to your VSCode user settings:

```json
{
  "solidity.compileUsingRemoteVersion": "v0.8.25",
  "solidity.defaultCompiler": "remote"
}
```

Where of course `v0.8.25` can be replaced with any other version.
