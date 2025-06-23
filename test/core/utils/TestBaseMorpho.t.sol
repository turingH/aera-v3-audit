// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { Test } from "forge-std/Test.sol";

import { IMorpho } from "test/dependencies/interfaces/morpho/IMorpho.sol";

abstract contract TestBaseMorpho is Test {
    IMorpho internal morpho;

    // Mainnet addresses
    address internal constant MORPHO = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address internal constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

    address internal constant WETH_WBTC_MORPHO_ORACLE = 0xc29B3Bc033640baE31ca53F8a0Eb892AdF68e663;
    address internal constant WETH_WBTC_MORPHO_IRM = 0x870aC11D48B15DB9a138Cf899d20F13F79Ba00BC;

    address internal constant GAUNTLET_WETH_VAULT = 0x2371e134e3455e0593363cBF89d3b6cf53740618;

    uint16 internal constant MARKET_PARAMS_WORDS = 5;

    function setUp() public virtual {
        vm.createSelectFork(vm.envString("ETH_NODE_URI_MAINNET"), 20_771_781);
        morpho = IMorpho(MORPHO);

        vm.label(MORPHO, "MORPHO");
        vm.label(WETH, "WETH");
        vm.label(WBTC, "WBTC");
    }

    function _getMorphoFlashloanOffset() internal pure returns (uint16 offset) {
        // For onMorphoFlashLoan(uint256 assets, bytes calldata data)
        offset = uint16(
            4 // selector
                + 32 // assets amount
                + 32 // data pointer
                + 32 // data length
        );
    }
}
