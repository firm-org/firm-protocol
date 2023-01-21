// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.17;

import "openzeppelin/access/Ownable.sol";
import "openzeppelin/token/ERC20/ERC20.sol";

contract TestnetERC20 is ERC20, Ownable {
    uint8 private immutable _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external onlyOwner {
        _mint(to, amount);
    }
}

contract TestnetTokenFaucet is Ownable {
    struct TokenData {
        TestnetERC20 token;
        string symbol;
    }

    mapping(string => TestnetERC20) public tokenWithSymbol;
    TokenData[] public allTokens;
    uint256 public tokenCount;

    function create(string memory name, string memory symbol, uint8 decimals)
        public
        onlyOwner
        returns (TestnetERC20 token)
    {
        require(address(tokenWithSymbol[symbol]) == address(0), "testnet faucet: token exists");

        token = new TestnetERC20(name, symbol, decimals);
        tokenWithSymbol[symbol] = token;
        allTokens.push(TokenData(token, symbol));
        tokenCount++;
    }

    function drip(string calldata symbol, address to, uint256 amount) public {
        require(address(tokenWithSymbol[symbol]) != address(0), "testnet faucet: token doesnt exist");
        drip(tokenWithSymbol[symbol], to, amount);
    }

    function drip(TestnetERC20 token, address to, uint256 amount) public {
        token.mint(to, amount);
    }
}
