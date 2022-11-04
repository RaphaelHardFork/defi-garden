// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "openzeppelin-contracts/token/ERC20/ERC20.sol";
import "openzeppelin-contracts/utils/Counters.sol";

contract Token is ERC20 {
    constructor() ERC20("Token", "T") {}

    function mint(address recipient, uint256 amount) external {
        _mint(recipient, amount);
    }
}

abstract contract BaseTest is Test {
    using Counters for Counters.Counter;

    // time variables
    uint256 public constant MONTH = 4096 * 30;

    // users & accounts
    address public constant OWNER = address(501);
    address[] internal USERS;

    // tokens
    Counters.Counter private _lastTokenId;
    mapping(uint256 => Token) public tokens;

    function _deployToken()
        internal
        returns (address tokenAddr, uint256 tokenIndex)
    {
        _lastTokenId.increment();
        tokenIndex = _lastTokenId.current();
        Token token = new Token();
        tokens[tokenIndex] = token;
        tokenAddr = address(token);
    }

    function _newUsersSet(uint256 offset, uint256 length) internal {
        address[] memory list = new address[](length);

        for (uint160 i = uint160(offset); i < length; i++) {
            list[i] = address(i + 1);
        }
        USERS = list;
    }

    function _mintTokenForAll(uint256 amount, uint256 tokenIndex) internal {
        Token t = tokens[tokenIndex];
        for (uint256 i; i < USERS.length; i++) {
            t.mint(USERS[i], amount);
        }
    }

    function _mintFor(
        address user,
        uint256 amount,
        uint256 tokenIndex
    ) internal {
        Token t = tokens[tokenIndex];
        t.mint(user, amount);
    }
}
