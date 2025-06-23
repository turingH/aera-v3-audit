// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.29;

////////////////////////////////////////////////////////////
//                     Bit Operations                     //
////////////////////////////////////////////////////////////

// Mask for extracting 8-bit values
uint256 constant MASK_8_BIT = 0xff;

////////////////////////////////////////////////////////////
//                     Hooks Constants                    //
////////////////////////////////////////////////////////////

// Size of the address in the path
uint256 constant UNISWAP_PATH_ADDRESS_SIZE = 20;

// Size of the chunk in the path (20 bytes for address + 3 bytes for uint24 fee)
uint256 constant UNISWAP_PATH_CHUNK_SIZE = 23;

// ETH address used in OdosRouterV2
address constant ODOS_ROUTER_V2_ETH_ADDRESS = address(0);

// ETH address used in KyberSwap
address constant KYBERSWAP_ETH_ADDRESS = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

////////////////////////////////////////////////////////////
//                   Oracle Registry Constants            //
////////////////////////////////////////////////////////////

/// @dev Maximum update delay for oracle
uint256 constant MAXIMUM_UPDATE_DELAY = 30 days;
