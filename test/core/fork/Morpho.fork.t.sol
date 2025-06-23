// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { IERC20 } from "@oz/interfaces/IERC20.sol";
import { IERC4626 } from "@oz/interfaces/IERC4626.sol";
import { Authority } from "@solmate/auth/Auth.sol";
import { BaseVaultParameters, CallbackData, Clipboard, Operation, ReturnValueType } from "src/core/Types.sol";
import { ISwapRouter } from "src/dependencies/uniswap/v3/interfaces/ISwapRouter.sol";
import { IMorpho, IMorphoBase, Id, MarketParams, Position } from "test/dependencies/interfaces/morpho/IMorpho.sol";
import { IMorphoFlashLoanCallback } from "test/dependencies/interfaces/morpho/IMorphoCallbacks.sol";

import { ISubmitHooks } from "src/core/interfaces/ISubmitHooks.sol";
import { IWhitelist } from "src/core/interfaces/IWhitelist.sol";

import { BaseVault } from "src/core/BaseVault.sol";
import { MockBaseVaultFactory } from "test/core/mocks/MockBaseVaultFactory.sol";
import { Encoder } from "test/core/utils/Encoder.sol";
import { HelperCalculator } from "test/core/utils/HelperCalculator.sol";
import { TestBaseMorpho } from "test/core/utils/TestBaseMorpho.t.sol";
import { TestBaseUniV3 } from "test/core/utils/TestBaseUniV3.t.sol";

import { BaseMerkleTree } from "test/utils/BaseMerkleTree.t.sol";
import { BaseTest } from "test/utils/BaseTest.t.sol";
import { MerkleHelper } from "test/utils/MerkleHelper.sol";

contract MorphoForkTest is TestBaseMorpho, TestBaseUniV3, BaseTest, BaseMerkleTree, MockBaseVaultFactory {
    using MarketParamsLib for MarketParams;

    HelperCalculator internal helperCalculator;
    BaseVault public vault;

    function setUp() public override(TestBaseMorpho, TestBaseUniV3, BaseTest) {
        BaseTest.setUp();
        TestBaseMorpho.setUp();
        TestBaseUniV3.setUp();

        vault = BaseVault(BASE_VAULT);

        // 0 WETH approve MORPHO
        leaves.push(
            MerkleHelper.getLeaf({
                target: WETH,
                selector: IERC20.approve.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(MORPHO)
            })
        );
        // 1 flashloan any token from Morpho
        leaves.push(
            MerkleHelper.getLeaf({
                target: MORPHO,
                selector: IMorphoBase.flashLoan.selector,
                hasValue: false,
                configurableHooksOffsets: new uint16[](0),
                hooks: address(0),
                callbackData: CallbackData({
                    caller: MORPHO,
                    selector: IMorphoFlashLoanCallback.onMorphoFlashLoan.selector,
                    calldataOffset: _getMorphoFlashloanOffset()
                }),
                extractedData: ""
            })
        );
        // 2 WBTCA approve MORPHO
        leaves.push(
            MerkleHelper.getLeaf({
                target: WBTC,
                selector: IERC20.approve.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(MORPHO)
            })
        );
        // 3 WETH approve UNISWAP_V3_ROUTER_MAINNET
        leaves.push(
            MerkleHelper.getLeaf({
                target: WETH,
                selector: IERC20.approve.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(UNISWAP_V3_ROUTER_MAINNET)
            })
        );
        // 4 UNISWAP_V3_ROUTER_MAINNET exactInputSingle WETH to WBTC
        leaves.push(
            MerkleHelper.getLeaf({
                target: UNISWAP_V3_ROUTER_MAINNET,
                selector: ISwapRouter.exactInputSingle.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 96),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(WETH, WBTC, BASE_VAULT)
            })
        );

        // 5 MORPHO supplyCollateral WETH → WBTC
        leaves.push(
            MerkleHelper.getLeaf({
                target: MORPHO,
                selector: IMorphoBase.supplyCollateral.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 192),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(
                    WETH, WBTC, WETH_WBTC_MORPHO_ORACLE, WETH_WBTC_MORPHO_IRM, uint256(0.915e18), BASE_VAULT
                )
            })
        );

        // 6 MORPHO borrow WETH → WBTC
        leaves.push(
            MerkleHelper.getLeaf({
                target: MORPHO,
                selector: IMorphoBase.borrow.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 224, 256),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(
                    WETH, WBTC, WETH_WBTC_MORPHO_ORACLE, WETH_WBTC_MORPHO_IRM, uint256(0.915e18), BASE_VAULT, BASE_VAULT
                )
            })
        );

        // 7 UNISWAP_V3_ROUTER_MAINNET exactOutputSingle WETH → WBTC
        leaves.push(
            MerkleHelper.getLeaf({
                target: UNISWAP_V3_ROUTER_MAINNET,
                selector: ISwapRouter.exactOutputSingle.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 96),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(WETH, WBTC, BASE_VAULT)
            })
        );

        // 8 WBTC approve UNISWAP_V3_ROUTER_MAINNET
        leaves.push(
            MerkleHelper.getLeaf({
                target: WBTC,
                selector: IERC20.approve.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(UNISWAP_V3_ROUTER_MAINNET)
            })
        );

        // 9 WETH approve GAUNTLET_WETH_VAULT
        leaves.push(
            MerkleHelper.getLeaf({
                target: WETH,
                selector: IERC20.approve.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(GAUNTLET_WETH_VAULT)
            })
        );

        // 10 MORPHO vault deposit
        leaves.push(
            MerkleHelper.getLeaf({
                target: GAUNTLET_WETH_VAULT,
                selector: IERC4626.deposit.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(BASE_VAULT)
            })
        );

        // 11 MORPHO vault mint
        leaves.push(
            MerkleHelper.getLeaf({
                target: GAUNTLET_WETH_VAULT,
                selector: IERC4626.mint.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(BASE_VAULT)
            })
        );

        // 12 MORPHO vault withdraw
        leaves.push(
            MerkleHelper.getLeaf({
                target: GAUNTLET_WETH_VAULT,
                selector: IERC4626.withdraw.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(BASE_VAULT, BASE_VAULT)
            })
        );

        // 13 MORPHO vault redeem
        leaves.push(
            MerkleHelper.getLeaf({
                target: GAUNTLET_WETH_VAULT,
                selector: IERC4626.redeem.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(BASE_VAULT, BASE_VAULT)
            })
        );

        // 14 MORPHO market supply
        leaves.push(
            MerkleHelper.getLeaf({
                target: MORPHO,
                selector: IMorphoBase.supply.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 224),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(
                    WETH, WBTC, WETH_WBTC_MORPHO_ORACLE, WETH_WBTC_MORPHO_IRM, uint256(0.915e18), BASE_VAULT
                )
            })
        );

        // 15 MORPHO market withdraw
        leaves.push(
            MerkleHelper.getLeaf({
                target: MORPHO,
                selector: IMorphoBase.withdraw.selector,
                hasValue: false,
                configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 224, 256),
                hooks: address(0),
                callbackData: Encoder.emptyCallbackData(),
                extractedData: abi.encode(
                    WETH, WBTC, WETH_WBTC_MORPHO_ORACLE, WETH_WBTC_MORPHO_IRM, uint256(0.915e18), BASE_VAULT, BASE_VAULT
                )
            })
        );

        bytes32 root = MerkleHelper.getRoot(leaves);

        setGuardian(users.guardian);
        setBaseVaultParameters(
            BaseVaultParameters({
                owner: address(this),
                authority: Authority(address(0)),
                submitHooks: ISubmitHooks(address(0)),
                whitelist: IWhitelist(WHITELIST)
            })
        );
        deployCodeTo("BaseVault.sol", address(BASE_VAULT));

        vault.acceptOwnership();
        vault.setGuardianRoot(users.guardian, root);

        helperCalculator = new HelperCalculator();
    }

    ////////////////////////////////////////////////////////////
    //                  Morpho - flash loans                  //
    ////////////////////////////////////////////////////////////

    function test_fork_submit_success_nestedSimpleFlashloan() public {
        uint256 flashAmount = 100e18;
        uint16 dataOffset = _getMorphoFlashloanOffset();

        deal(WETH, MORPHO, flashAmount * 2);

        Operation[] memory operations = new Operation[](1); // flashloan
        Operation[] memory callbackOps = new Operation[](2); // flashloan + approve
        Operation[] memory nestedCallbackOps = new Operation[](1); // approve

        nestedCallbackOps[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, MORPHO, flashAmount),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });

        callbackOps[0] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(
                IMorphoBase.flashLoan.selector,
                WETH,
                flashAmount,
                Encoder.encodeCallbackOperations(nestedCallbackOps, ReturnValueType.NO_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: MORPHO,
                selector: IMorphoFlashLoanCallback.onMorphoFlashLoan.selector,
                calldataOffset: dataOffset
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        callbackOps[1] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, MORPHO, flashAmount),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });
        operations[0] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(
                IMorphoBase.flashLoan.selector,
                WETH,
                flashAmount,
                Encoder.encodeCallbackOperations(nestedCallbackOps, ReturnValueType.NO_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: MORPHO,
                selector: IMorphoFlashLoanCallback.onMorphoFlashLoan.selector,
                calldataOffset: dataOffset
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
    }

    function test_fork_submit_success_simpleFlashloan() public {
        uint256 flashAmount = 100e18;

        deal(WETH, MORPHO, flashAmount);

        Operation[] memory operations = new Operation[](1);

        Operation[] memory callbackOps = new Operation[](1);
        callbackOps[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, MORPHO, flashAmount),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });

        uint16 dataOffset = _getMorphoFlashloanOffset();
        operations[0] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(
                IMorphoBase.flashLoan.selector,
                WETH,
                flashAmount,
                Encoder.encodeCallbackOperations(callbackOps, ReturnValueType.NO_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: MORPHO,
                selector: IMorphoFlashLoanCallback.onMorphoFlashLoan.selector,
                calldataOffset: dataOffset
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));
    }

    function test_fork_submit_success_flashloanLeveragedLong() public {
        uint256 initialWETH = 20e18;
        uint256 flashWBTCAmount = helperCalculator.calculateFlashAmount(initialWETH, WETH_WBTC_MORPHO_ORACLE);

        // Setup: Give WETH to vault
        deal(WETH, address(vault), initialWETH);
        deal(WBTC, MORPHO, flashWBTCAmount);

        // https://app.morpho.org/market?id=0x138eec0e4a1937eb92ebc70043ed539661dd7ed5a89fb92a720b341650288a40&network=mainnet
        MarketParams memory marketParams = MarketParams({
            loanToken: WETH,
            collateralToken: WBTC,
            oracle: WETH_WBTC_MORPHO_ORACLE,
            irm: WETH_WBTC_MORPHO_IRM,
            lltv: 0.915e18
        });

        Operation[] memory operations = new Operation[](5);

        // ~~~~~~~~~~~~~ 1. Setup ~~~~~~~~~~~~~
        // 1.a. Approve WBTC for Morpho (max so that we don't need to approve again for new supply)
        operations[0] = Operation({
            target: WBTC,
            data: abi.encodeWithSelector(IERC20.approve.selector, MORPHO, type(uint256).max),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // 1.b. Approve Uniswap V3 Router for WETH
        operations[1] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_ROUTER_MAINNET, type(uint256).max),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        // 1.c. Swap WETH → WBTC for collateral
        // https://app.uniswap.org/explore/pools/ethereum/0x4585FE77225b41b697C938B018E2Ac67Ac5a20c0
        operations[2] = Operation({
            target: UNISWAP_V3_ROUTER_MAINNET,
            data: abi.encodeWithSelector(
                ISwapRouter.exactInputSingle.selector, _getInputSwapParams(WETH, WBTC, 500, address(vault), initialWETH)
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 96),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });

        // -------------------------------------------------------------------------------------------------------------
        // 2. Flashloan WBTC from Morpho, with callback ops
        Operation[] memory callbackOps = new Operation[](12);

        // ~~~~~~~~~~~~~ 2.a. Supply all WBTC as collateral ~~~~~~~~~~~~~

        // >> 2.a.1. Get WBTC balance
        callbackOps[0] = Operation({
            target: WBTC,
            data: abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        // >> 2.a.2. Supply WBTC as collateral
        callbackOps[1] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(IMorphoBase.supplyCollateral.selector, marketParams, 0, address(vault), ""),
            clipboards: Encoder.makeClipboardArray(0, 0, MARKET_PARAMS_WORDS * 32),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 192),
            proof: MerkleHelper.getProof(leaves, 5),
            hooks: address(0),
            value: 0
        });

        // ~~~~~~~~~~~~~ 2.b. First, borrow WETH against WBTC collateral ~~~~~~~~~~~~~

        // >> 2.b.1. Calculate the amount to borrow
        callbackOps[2] = Operation({
            target: address(helperCalculator),
            data: abi.encodeWithSelector(
                // ideally this would be a helper contract that can calculate the amount to borrow
                HelperCalculator.calculateBorrowAmount.selector,
                marketParams,
                0,
                WETH_WBTC_MORPHO_ORACLE
            ),
            clipboards: Encoder.makeClipboardArray(0, 0, MARKET_PARAMS_WORDS * 32),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        // >> 2.b.2. Borrow WETH against WBTC collateral
        callbackOps[3] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(IMorphoBase.borrow.selector, marketParams, 0, 0, address(vault), address(vault)),
            clipboards: Encoder.makeClipboardArray(2, 0, MARKET_PARAMS_WORDS * 32),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 224, 256),
            proof: MerkleHelper.getProof(leaves, 6),
            hooks: address(0),
            value: 0
        });

        // ~~~~~~~~~~~ 2.c. Leverage - swap borrowed WETH for more WBTC, supply new WBTC and borrow more WETH ~~~~~~~~~~
        // >> 2.c.1. Swap borrowed WETH for more WBTC
        callbackOps[4] = Operation({
            target: UNISWAP_V3_ROUTER_MAINNET,
            data: abi.encodeWithSelector(
                ISwapRouter.exactInputSingle.selector, _getInputSwapParams(WETH, WBTC, 500, address(vault), 0)
            ),
            clipboards: Encoder.makeClipboardArray(3, 0, AMOUNT_INOUT_WORDS * 32),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 96),
            proof: MerkleHelper.getProof(leaves, 4),
            hooks: address(0),
            value: 0
        });

        // >> 2.c.2. Supply additional WBTC as collateral
        callbackOps[5] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(IMorphoBase.supplyCollateral.selector, marketParams, 0, address(vault), ""),
            clipboards: Encoder.makeClipboardArray(4, 0, MARKET_PARAMS_WORDS * 32),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 192),
            proof: MerkleHelper.getProof(leaves, 5),
            hooks: address(0),
            value: 0
        });

        // >> 2.c.3. Calculate the amount to borrow
        callbackOps[6] = Operation({
            target: address(helperCalculator),
            data: abi.encodeWithSelector(
                // ideally this would be a helper contract that can calculate the amount to borrow
                HelperCalculator.calculateBorrowAmount.selector,
                marketParams,
                0,
                WETH_WBTC_MORPHO_ORACLE
            ),
            clipboards: Encoder.makeClipboardArray(4, 0, MARKET_PARAMS_WORDS * 32),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        // >> 2.c.4. Borrow more WETH against WBTC collateral
        callbackOps[7] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(IMorphoBase.borrow.selector, marketParams, 0, 0, address(vault), address(vault)),
            clipboards: Encoder.makeClipboardArray(6, 0, MARKET_PARAMS_WORDS * 32),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 224, 256),
            proof: MerkleHelper.getProof(leaves, 6),
            hooks: address(0),
            value: 0
        });

        // ~~~~~~~~~~~~~ 2.d. Swap borrowed WETH to WBTC to repay flashloan ~~~~~~~~~~~~~

        // 2.d.1. Get WETH balance
        callbackOps[8] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        // 2.d.2. Swap borrowed WETH to WBTC to repay flashloan
        callbackOps[9] = Operation({
            target: UNISWAP_V3_ROUTER_MAINNET,
            data: abi.encodeWithSelector(
                ISwapRouter.exactOutputSingle.selector,
                _getOutputSwapParams(WETH, WBTC, 500, address(vault), flashWBTCAmount, 0)
            ),
            // pipe total balance into amountInMaximum
            clipboards: Encoder.makeClipboardArray(8, 0, (AMOUNT_INOUT_WORDS + 1) * 32),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 96),
            proof: MerkleHelper.getProof(leaves, 7),
            hooks: address(0),
            value: 0
        });

        // 2.d.3. Approve flashloaned WBTC amount to Morpho
        callbackOps[10] = Operation({
            target: WBTC,
            data: abi.encodeWithSelector(IERC20.approve.selector, MORPHO, flashWBTCAmount),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });

        // ~~~~~~~~~~~~~ 2.e. Cleanup ~~~~~~~~~~~~~

        // 2.e.1. Reset WETH allowance for Uniswap V3 Router, because it probably didn't take all the WETH for swap
        callbackOps[11] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, UNISWAP_V3_ROUTER_MAINNET, 0),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 3),
            hooks: address(0),
            value: 0
        });

        operations[3] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(
                IMorphoBase.flashLoan.selector,
                WBTC,
                flashWBTCAmount,
                Encoder.encodeCallbackOperations(callbackOps, ReturnValueType.NO_RETURN, new bytes(0))
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: CallbackData({
                caller: MORPHO,
                selector: IMorphoFlashLoanCallback.onMorphoFlashLoan.selector,
                calldataOffset: _getMorphoFlashloanOffset()
            }),
            configurableHooksOffsets: new uint16[](0),
            proof: MerkleHelper.getProof(leaves, 1),
            hooks: address(0),
            value: 0
        });

        // Reset WBTC allowance for Morpho
        operations[4] = Operation({
            target: WBTC,
            data: abi.encodeWithSelector(IERC20.approve.selector, MORPHO, 0),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 2),
            hooks: address(0),
            value: 0
        });
        // -------------------------------------------------------------------------------------------------------------
        vm.allowCheatcodes(address(vault));
        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operations));

        // Assert final position
        assertLt(IERC20(WETH).balanceOf(address(vault)), initialWETH); // Should have lost WETH to WBTC collateral
        assertGt(IERC20(WBTC).balanceOf(MORPHO), flashWBTCAmount); // Flashloan repaid + collateral from our position
    }

    ////////////////////////////////////////////////////////////
    //                    Morpho - vaults                     //
    ////////////////////////////////////////////////////////////

    function test_fork_submit_success_vaultDepositAndWithdraw() public {
        uint256 initialWETH = 10e18;
        deal(WETH, address(vault), initialWETH);

        Operation[] memory operationsBefore = new Operation[](2);
        operationsBefore[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, GAUNTLET_WETH_VAULT, initialWETH),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 9),
            hooks: address(0),
            value: 0
        });

        operationsBefore[1] = Operation({
            target: GAUNTLET_WETH_VAULT,
            data: abi.encodeWithSelector(IERC4626.deposit.selector, initialWETH, address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32),
            proof: MerkleHelper.getProof(leaves, 10),
            hooks: address(0),
            value: 0
        });

        Operation[] memory operationsAfter = new Operation[](2);
        operationsAfter[0] = Operation({
            target: GAUNTLET_WETH_VAULT,
            data: abi.encodeWithSelector(IERC4626.maxWithdraw.selector, address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        operationsAfter[1] = Operation({
            target: GAUNTLET_WETH_VAULT,
            data: abi.encodeWithSelector(IERC4626.withdraw.selector, 0, address(vault), address(vault)),
            clipboards: Encoder.makeClipboardArray(0, 0, 0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64),
            proof: MerkleHelper.getProof(leaves, 12),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operationsBefore));

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH balance should be 0");
        assertGt(
            IERC4626(GAUNTLET_WETH_VAULT).balanceOf(address(vault)), 0, "Number of shares should be greater than 0"
        );

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operationsAfter));

        assertApproxEqAbs(IERC20(WETH).balanceOf(address(vault)), initialWETH, 1, "WETH balance should be initialWETH");
        assertEq(IERC4626(GAUNTLET_WETH_VAULT).balanceOf(address(vault)), 0, "Number of shares should be 0");
    }

    function test_fork_submit_success_vaultMintAndRedeem() public {
        uint256 initialWETH = 10e18;
        deal(WETH, address(vault), initialWETH);
        uint256 sharesToMint = IERC4626(GAUNTLET_WETH_VAULT).convertToShares(initialWETH);

        Operation[] memory operationsBefore = new Operation[](2);
        operationsBefore[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, GAUNTLET_WETH_VAULT, initialWETH),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 9),
            hooks: address(0),
            value: 0
        });

        operationsBefore[1] = Operation({
            target: GAUNTLET_WETH_VAULT,
            data: abi.encodeWithSelector(IERC4626.mint.selector, sharesToMint, address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32),
            proof: MerkleHelper.getProof(leaves, 11),
            hooks: address(0),
            value: 0
        });

        Operation[] memory operationsAfter = new Operation[](2);
        operationsAfter[0] = Operation({
            target: GAUNTLET_WETH_VAULT,
            data: abi.encodeWithSelector(IERC20.balanceOf.selector, address(vault)),
            clipboards: new Clipboard[](0),
            isStaticCall: true,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: new uint16[](0),
            proof: new bytes32[](0),
            hooks: address(0),
            value: 0
        });

        operationsAfter[1] = Operation({
            target: GAUNTLET_WETH_VAULT,
            data: abi.encodeWithSelector(IERC4626.redeem.selector, 0, address(vault), address(vault)),
            clipboards: Encoder.makeClipboardArray(0, 0, 0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(32, 64),
            proof: MerkleHelper.getProof(leaves, 13),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operationsBefore));

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH balance should be 0");
        assertEq(
            IERC4626(GAUNTLET_WETH_VAULT).balanceOf(address(vault)),
            sharesToMint,
            "Number of shares should be sharesToMint"
        );

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operationsAfter));

        assertApproxEqAbs(IERC20(WETH).balanceOf(address(vault)), initialWETH, 1, "WETH balance should be initialWETH");
        assertEq(IERC4626(GAUNTLET_WETH_VAULT).balanceOf(address(vault)), 0, "Number of shares should be 0");
    }

    ////////////////////////////////////////////////////////////
    //                    Morpho - markets                    //
    ////////////////////////////////////////////////////////////

    function test_fork_submit_success_marketSupplyAndWithdraw() public {
        uint256 initialWETH = 10e18;
        deal(WETH, address(vault), initialWETH);

        Operation[] memory operationsBefore = new Operation[](2);
        operationsBefore[0] = Operation({
            target: WETH,
            data: abi.encodeWithSelector(IERC20.approve.selector, MORPHO, initialWETH),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0),
            proof: MerkleHelper.getProof(leaves, 0),
            hooks: address(0),
            value: 0
        });

        MarketParams memory marketParams = MarketParams({
            loanToken: WETH,
            collateralToken: WBTC,
            oracle: WETH_WBTC_MORPHO_ORACLE,
            irm: WETH_WBTC_MORPHO_IRM,
            lltv: 0.915e18
        });

        operationsBefore[1] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(IMorphoBase.supply.selector, marketParams, initialWETH, 0, address(vault), ""),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 224),
            proof: MerkleHelper.getProof(leaves, 14),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operationsBefore));

        // ~~~~~~~~~~ Verify ~~~~~~~~~~
        Id id = marketParams.id();
        Position memory position = IMorpho(MORPHO).position(id, address(vault));

        assertEq(IERC20(WETH).balanceOf(address(vault)), 0, "WETH balance should be 0");
        assertGt(position.supplyShares, 0, "Number of shares should be greater than 0");

        Operation[] memory operationsAfter = new Operation[](1);
        operationsAfter[0] = Operation({
            target: MORPHO,
            data: abi.encodeWithSelector(
                IMorphoBase.withdraw.selector, marketParams, 0, position.supplyShares, address(vault), address(vault)
            ),
            clipboards: new Clipboard[](0),
            isStaticCall: false,
            callbackData: Encoder.emptyCallbackData(),
            configurableHooksOffsets: Encoder.makeExtractOffsetsArray(0, 32, 64, 96, 128, 224, 256),
            proof: MerkleHelper.getProof(leaves, 15),
            hooks: address(0),
            value: 0
        });

        vm.prank(users.guardian);
        vault.submit(Encoder.encodeOperations(operationsAfter));

        id = marketParams.id();
        position = IMorpho(MORPHO).position(id, address(vault));
        assertEq(position.supplyShares, 0, "Number of shares should be 0");
        assertApproxEqAbs(IERC20(WETH).balanceOf(address(vault)), initialWETH, 1, "WETH balance should be initialWETH");
    }
}

/// @title MarketParamsLib
/// @author Morpho Labs
/// @custom:contact security@morpho.org
/// @notice Library to convert a market to its id
library MarketParamsLib {
    /// @notice The length of the data used to compute the id of a market
    /// @dev The length is 5 * 32 because `MarketParams` has 5 variables of 32 bytes each
    uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

    /// @notice Returns the id of the market `marketParams`
    function id(MarketParams memory marketParams) internal pure returns (Id marketParamsId) {
        assembly ("memory-safe") {
            marketParamsId := keccak256(marketParams, MARKET_PARAMS_BYTES_LENGTH)
        }
    }
}
