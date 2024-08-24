//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "hardhat/console.sol";
import "./Token.sol";

// Manage pool
// Manage deposits
// Facilitate swaps
// Manage withdraws

contract AMM {
	Token public token1;
	Token public token2;

	mapping(uint256 => Token) public tokens;
	mapping(uint256 => uint256) public tokenBalance;
	mapping(string => uint256) public tokenNames;
	uint256 public token1Balance;
	uint256 public token2Balance;
	uint256 public K;

	uint256 public totalShares;
	mapping(address => uint256) public shares;
	uint256 constant PRECISION = 10**18;

    struct SwapResults {
        uint256 tokenOutAmount;
        uint256 tokenInBalance;
        uint256 tokenOutBalance;
    }

	event Swap(
		address user, 
		address tokenGive,
		uint256 tokenGiveAmount,
		address tokenGet,
		uint256 tokenGetAmount,
		uint256 token1Balance,
		uint256 token2Balance,
		uint256 timestamp
		);


	constructor(Token _token1, string memory _token1Name, Token _token2, string memory _token2Name) {
		tokens[1] = _token1;
		tokens[2] = _token2;
		tokenNames[_token1Name] = 1;
		tokenNames[_token2Name] = 2;
		// Maintaining the original properties so I don't have to rewrite the tests or website
		token1 = _token1;
		token2 = _token2;
	}

	// Liquidity
	function addLiquidity(uint256 _token1Amount, uint256 _token2Amount) external {
		// Deposit tokens
		require(
			tokens[1].transferFrom(msg.sender, address(this), _token1Amount));
		require(
			tokens[2].transferFrom(msg.sender, address(this), _token2Amount));

		// Issue shares
		uint256 share;

		// If first time adding liquidity, make shares 100
		if (totalShares == 0) {
			share = 100 * PRECISION;
		} else {
			uint256 share1 = (totalShares * _token1Amount) / tokenBalance[1];
			uint256 share2 = (totalShares * _token2Amount) / tokenBalance[2];
			require((share1 / 10**3) == (share2 / 10**3), "must provide equal token amounts");
			share = share1;
		}

		totalShares += share;
		shares[msg.sender] += share;

		// Manage pool
		tokenBalance[1] += _token1Amount;
		tokenBalance[2] += _token2Amount;
		K = tokenBalance[1] * tokenBalance[2];

		// Maintaining the original properties so I don't have to rewrite the tests or website
		token1Balance = tokenBalance[1];
		token2Balance = tokenBalance[2];
	}

	function _calculateTokenDeposit(uint256 _tokenInAmount, uint256 _tokenInNumber, uint256 _tokenOutNumber) private view returns(uint256 tokenOutAmount) {
		uint256 tokenInBalance = tokenBalance[_tokenInNumber];
		uint256 tokenOutBalance = tokenBalance[_tokenOutNumber];
		tokenOutAmount = (tokenOutBalance * _tokenInAmount) / tokenInBalance;
	}

	// Determine how many token2 need to be deposited when token1 is known
	function calculateToken2Deposit(uint256 _token1Amount) public view returns(uint256 token2Amount) {
		// token2Amount = (token2Balance * _token1Amount) / token1Balance;
		token2Amount = _calculateTokenDeposit(_token1Amount, 1, 2);
	}
	// Determine how many token1 need to be deposited when token2 is known
	function calculateToken1Deposit(uint256 _token2Amount) public view returns(uint256 token1Amount) {
		// token1Amount = (token1Balance * _token2Amount) / token2Balance;
		token1Amount = _calculateTokenDeposit(_token2Amount, 2, 1);
	}

	// Swap
	function calculateToken1Swap(uint256 _token1Amount) public view returns(uint256 token2Amount) {
		token2Amount = _calculateTokenSwap(_token1Amount, 1, 2);
	}

	function calculateToken2Swap(uint256 _token2Amount) public view returns(uint256 token1Amount) {
		token1Amount = _calculateTokenSwap(_token2Amount, 2, 1);
	}

	function _calculateTokenSwap(
		uint256 _tokenInAmount, 
		uint256 _tokenInNumber,
		uint256 _tokenOutNumber) 
		private view returns(uint256 tokenOutAmount) 
		{
		uint256 tokenInAfter = tokenBalance[_tokenInNumber] + _tokenInAmount;
		uint256 tokenOutAfter = K / tokenInAfter;
		tokenOutAmount = tokenBalance[_tokenOutNumber] - tokenOutAfter;

		// Don't let pool go to 0
		if (tokenOutAmount == tokenBalance[_tokenOutNumber]) {
			tokenOutAmount--;
		}

		require(tokenOutAmount < tokenBalance[_tokenOutNumber], "swap cannot exceed pool balance");
	}

	function _performSwap(
		uint256 _tokenInAmount, 
		address _senderAddress, 
		uint256 _tokenInNumber, 
		uint256 _tokenOutNumber) private returns(uint256 tokenOutAmount) {
		// Calculate amount of token 2 caller will get
		tokenOutAmount = _calculateTokenSwap(_tokenInAmount, _tokenInNumber, _tokenOutNumber);

		// Do swap
		// 1 - tranfer tokens from user wallet
		tokens[_tokenInNumber].transferFrom(_senderAddress, address(this), _tokenInAmount);
		// 2 - update token1 balance in contract
		tokenBalance[_tokenInNumber] += _tokenInAmount;
		// 3 - update token2 balance in contract
		tokenBalance[_tokenOutNumber] -= tokenOutAmount;
		// 4 - transfer token2 tokens to user wallet
		tokens[_tokenOutNumber].transfer(_senderAddress, tokenOutAmount);

		// tokenBalance[_tokenInNumber] = tokenInBalance;
		// tokenBalance[_tokenOutNumber] = tokenOutBalance;

		// // Emit an event
		emit Swap(
			msg.sender,
			address(tokens[_tokenInNumber]),
			_tokenInAmount,
			address(tokens[_tokenOutNumber]),
			tokenOutAmount,
			tokenBalance[1],
			tokenBalance[2],
			block.timestamp
		);
	}

	function swapToken1(uint256 _token1Amount) external returns(uint256 token2Amount) {
		token2Amount = _performSwap(_token1Amount, msg.sender, 1, 2);

		// Maintaining the original properties so I don't have to rewrite the tests or website
		token1Balance = tokenBalance[1];
		token2Balance = tokenBalance[2];

	}

	function swapToken2(uint256 _token2Amount) external returns(uint256 token1Amount) {
		token1Amount = _performSwap(_token2Amount, msg.sender, 2, 1);

		// Maintaining the original properties so I don't have to rewrite the tests or website
		token1Balance = tokenBalance[1];
		token2Balance = tokenBalance[2];

	}

	function calculateWithdrawAmount(uint256 _share) public view returns(uint256 token1Amount, uint256 token2Amount) {
		require(_share <= totalShares, "must be less than total shares");
		token1Amount = (_share * tokenBalance[1]) / totalShares;
		token2Amount = (_share * tokenBalance[2]) / totalShares;
 	}

	function removeLiquidity(uint256 _share) external returns(uint256 token1Amount, uint256 token2Amount) {
		require(_share <= shares[msg.sender], "cannot withdraw more shares than you have");
		(token1Amount, token2Amount) = calculateWithdrawAmount(_share);

		shares[msg.sender] -= _share;
		totalShares -= _share;

		tokenBalance[1] -= token1Amount;
		tokenBalance[2] -= token2Amount;
		K = tokenBalance[1] * tokenBalance[2];

		tokens[1].transfer(msg.sender, token1Amount);
		tokens[2].transfer(msg.sender, token2Amount);

		// Maintaining the original properties so I don't have to rewrite the tests or website
		token1Balance = tokenBalance[1];
		token2Balance = tokenBalance[2];
	}
}