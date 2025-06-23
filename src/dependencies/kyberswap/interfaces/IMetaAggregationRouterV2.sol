// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import { IAggregationExecutor } from "./IAggregationExecutor.sol";
import { IERC20 } from "@oz/interfaces/IERC20.sol";

interface IMetaAggregationRouterV2 {
    struct SwapDescriptionV2 {
        IERC20 srcToken;
        IERC20 dstToken;
        address[] srcReceivers;
        uint256[] srcAmounts;
        address[] feeReceivers;
        uint256[] feeAmounts;
        address dstReceiver;
        uint256 amount;
        uint256 minReturnAmount;
        uint256 flags;
        bytes permit;
    }

    struct SwapExecutionParams {
        address callTarget;
        address approveTarget;
        bytes targetData;
        SwapDescriptionV2 desc;
        bytes clientData;
    }

    struct SimpleSwapData {
        address[] firstPools;
        uint256[] firstSwapAmounts;
        bytes[] swapDatas;
        uint256 deadline;
        bytes destTokenFeeData;
    }

    function swap(SwapExecutionParams calldata execution)
        external
        payable
        returns (uint256 returnAmount, uint256 gasUsed);

    function swapSimpleMode(
        IAggregationExecutor caller,
        SwapDescriptionV2 calldata desc,
        bytes calldata executorData,
        bytes calldata clientData
    ) external returns (uint256 returnAmount, uint256 gasUsed);
}
