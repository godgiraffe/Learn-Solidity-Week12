// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract MyErc20 is ERC20 {
    // 因為父合約中沒有紀錄 _decimals, 所以在子合約中紀錄
    uint256 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 calldata decimals
    ) ERC20(name, symbol) { // 這邊等於做了 ERC20 的 constructor
        _decimals = decimals;
    }

    // 在子合約中，繼承了父合約所有的 function 及 狀態, 因此可以直接使用
    function mint(uint amount) public {
      _mint(msg.sender, amount);
    }

    function burn(uint amount) public {
      _burn(msg.sender, amount);
    }

    // 因為父合約中的 decimals() 有 virtual、override 的 function modify，代表可以覆寫
    // 這邊是 override 父合約的 decimals function
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
