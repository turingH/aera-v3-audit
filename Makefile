.PHONY: all clean build docs lint slither test test-coverage-check test-coverage-report snapshot snapshot-diff gas-report pre-commit mine-address mine-address-parallel create2-address

help: ## Print all targets and descriptions
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[.a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-25s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } END { printf "\n" }' $(MAKEFILE_LIST)

all: ## Clean, build, lint, slither, test, check coverage (not working currently, bring back when fixed), snapshot gas and docs
	make clean && \
	make build && \
	make lint && \
	make slither && \
	make test && \
	make snapshot

clean: ## Clean the project
	forge clean && rm -rf cache out

build: ## Build the project forcefully
	forge build --force

docs: ## Generate docs
	./script/util/doc_gen.sh

slither: ## Run slither (requires 0.11.0)
	slither . --include-paths "(src/core|src/periphery)" --fail-low --config-file slither.config.json

lint: ## Run lint	
	forge fmt --check && \
  	solhint -c .solhint.json --max-warnings 0 "src/**/*.sol"  && \
  	solhint -c test/.solhint.json --max-warnings 0 "test/**/*.t.sol"
#  solhint -c script/.solhint.json  --max-warnings 0 "script/**/*.sol"

fmt:
	forge fmt && \
  	solhint -c .solhint.json --max-warnings 0 "src/**/*.sol"  && \
  	solhint -c test/.solhint.json --max-warnings 0 "test/**/*.t.sol"

test: ## Run tests (also generates snapshots in `./snapshots`)
	forge test --force --isolate -vvv --show-progress

coverage-summary: ## Run tests and generate coverage summary
	FOUNDRY_PROFILE=lite forge coverage --no-match-coverage "(test|mocks|dependencies|Executor.sol|MilkmanRouter.sol|CalldataReader.sol|Sweepable.sol|script)" --force --report summary

COVERAGE_MIN := 100
coverage-check: ## Check if test coverage is above the minimum
	make coverage-summary | tee coverage.txt
	@coverage=$$(grep "| Total" coverage.txt | awk '{print $$4}' | sed 's/%//'); \
	if [ -z "$$coverage" ]; then \
		echo "\n❌ Failed to extract coverage percentage.\n"; \
		exit 1; \
	elif [ $$(echo "$$coverage < $(COVERAGE_MIN)" | bc -l) -eq 1 ]; then \
		echo "\n❌ Current coverage of $$coverage% below the minimum of $(COVERAGE_MIN)%.\n"; \
		exit 1; \
	else \
		echo "\n✅ Current coverage of $$coverage% meets the minimum of $(COVERAGE_MIN)%.\n"; \
	fi
	@rm coverage.txt

coverage-report: ## Generate test coverage report (`./coverage/index.html`)
	forge coverage --no-match-coverage "(test|mocks|$(SKIP_TESTS))" --force --report lcov --show-progress && \
	lcov --extract lcov.info --rc branch_coverage=1 --ignore-errors inconsistent --rc derive_function_end_line=0 -o lcov.info 'src/*' && \
	genhtml lcov.info --rc branch_coverage=1 --rc derive_function_end_line=0 --ignore-errors category,inconsistent,corrupt -o coverage

snapshot: ## Create a snapshot
	forge snapshot --force --isolate --desc --show-progress

snapshot-pre-commit:
	@echo "\n" && make snapshot

snapshot-diff: ## Check snapshot diff
	forge snapshot --force --isolate --desc --diff --show-progress

gas-report: ## Generate a gas report (`.gas-snapshot`)
	forge test --force --gas-report --isolate --show-progress

pre-commit: ## Run pre-commit hooks manually
	@echo && pre-commit run --all-files

mine-address: ## Mine CREATE2 address with: DEPLOYER (required), CONTRACT (optional, default=SingleDepositorVault), STARTS_WITH (optional,default=0) and ENDS_WITH (optional)
	@if [ -z "$(DEPLOYER)" ]; then \
		echo "Error: DEPLOYER address is required. Usage: make mine-address DEPLOYER=0x..."; \
		exit 1; \
	fi
	@chmod +x script/util/mine_address.sh
	@./script/util/mine_address.sh \
		--deployer $(DEPLOYER) \
		$(if $(CONTRACT),--contract $(CONTRACT)) \
		$(if $(STARTS_WITH),--starts-with $(STARTS_WITH)) \
		$(if $(ENDS_WITH),--ends-with $(ENDS_WITH))


clean-abi:
	@rm -rf abi

generate-abi: clean-abi build
	@./script/util/abi_gen.sh

clean-4bytes:
	@rm -rf 4bytes

generate-4bytes: clean-4bytes generate-abi
	@./script/util/4bytes_gen.sh || true

uploadable-openchain: generate-4bytes
	@./script/util/openchain_uploadable.sh
	@echo "manually upload generated openchain_uploadable.txt to https://openchain.xyz/signatures/import"
