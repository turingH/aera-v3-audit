pragma solidity 0.8.29;

import { ERC20Mock } from "@oz/mocks/token/ERC20Mock.sol";
import { IERC20 } from "@oz/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@oz/token/ERC20/utils/SafeERC20.sol";
import { IMultiDepositorVault } from "src/core/interfaces/IMultiDepositorVault.sol";

contract MockMultiDepositorVault is ERC20Mock {
    using SafeERC20 for IERC20;

    function enter(address from, IERC20 token, uint256 tokenAmount, uint256 unitsAmount, address recipient) external {
        token.safeTransferFrom(from, address(this), tokenAmount);
        _mint(recipient, unitsAmount);
    }

    function exit(address from, IERC20 token, uint256 tokenAmount, uint256 unitsAmount, address recipient) external {
        _burn(from, unitsAmount);
        token.safeTransfer(recipient, tokenAmount);
    }
}
