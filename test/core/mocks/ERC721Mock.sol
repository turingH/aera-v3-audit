// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.29;

import "@oz/token/ERC721/ERC721.sol";

contract ERC721Mock is ERC721 {
    constructor(string memory _name, string memory _symbol) ERC721(_name, _symbol) { }

    function mint(address _to, uint256 tokenId) public {
        _mint(_to, tokenId);
    }

    function burn(uint256 tokenId) public {
        _burn(tokenId);
    }
}
