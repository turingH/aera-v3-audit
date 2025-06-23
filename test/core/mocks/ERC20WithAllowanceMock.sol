pragma solidity 0.8.29;

import { ERC20 } from "@oz/token/ERC20/ERC20.sol";
import { IERC20WithAllowance } from "src/dependencies/openzeppelin/token/ERC20/IERC20WithAllowance.sol";

contract ERC20WithAllowanceMock is ERC20, IERC20WithAllowance {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) { }

    /**
     * @dev Indicates a failed `decreaseAllowance` request.
     */
    error ERC20FailedDecreaseAllowance(address spender, uint256 currentAllowance, uint256 requestedDecrease);

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 requestedDecrease) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance < requestedDecrease) {
            revert ERC20FailedDecreaseAllowance(spender, currentAllowance, requestedDecrease);
        }
        unchecked {
            _approve(owner, spender, currentAllowance - requestedDecrease);
        }

        return true;
    }
}
