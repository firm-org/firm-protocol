// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.16;

import "solmate/tokens/ERC20.sol";
import "openzeppelin/access/Ownable.sol";

contract TestnetERC20 is ERC20, Ownable {
    constructor(string memory name, string memory symbol, uint8 decimals) ERC20(name, symbol, decimals) {}

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
