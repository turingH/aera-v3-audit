// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import { INonfungiblePositionManager } from "test/dependencies/interfaces/INonfungiblePositionManager.sol";

interface INonfungibleTokenPositionDescriptor {
    function tokenURI(INonfungiblePositionManager positionManager, uint256 tokenId)
        external
        view
        returns (string memory);
}
