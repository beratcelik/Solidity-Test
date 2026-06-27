// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.7.0;

import "./IERC20.sol";
import "./IMintableToken.sol";
import "./IDividends.sol";
import "./SafeMath.sol";

contract Token is IERC20, IMintableToken, IDividends {
  // ------------------------------------------ //
  // ----- BEGIN: DO NOT EDIT THIS SECTION ---- //
  // ------------------------------------------ //
  using SafeMath for uint256;
  uint256 public totalSupply;
  uint256 public decimals = 18;
  string public name = "Test token";
  string public symbol = "TEST";
  mapping (address => uint256) public balanceOf;
  // ------------------------------------------ //
  // ----- END: DO NOT EDIT THIS SECTION ------ //  
  // ------------------------------------------ //

  /*
   * Dividend tracking uses a per-share accumulator (popularized by SushiSwap's MasterChef contract).
   * This pattern is used rather than a for loop in order to avoid wasting gas.
   *
   * Holder list uses index mapping of O(1) add/remove without array shifting. The aim is to avoid wasting gas.
   *
   * Payable functions follow the Checks-Effects-Interactions (CEI) pattern.
   * It is a safe way to avoid reentrant issues. On top of it, we must use ReentrancyGuard library of OpenZeppelin for production.
   *
   */

  // Variables
  uint256 private constant SCALE = 10**18;
  uint256 private _dividendPerShare;
  address[] private _holders;
  mapping(address => uint256) private _dividendDebt;
  mapping(address => uint256) private _dividends;
  mapping(address => uint256) private _holderIndex;
  mapping(address => mapping(address => uint256)) private _allowances;


  // IERC20

  function allowance(address owner, address spender) external view override returns (uint256) {
      return _allowances[owner][spender];
  }

  function transfer(address to, uint256 value) external override returns (bool) {
    // balance check is required yet i believe sub function already checks for it.
    _settle(msg.sender);
    if (to != msg.sender) _settle(to);
    balanceOf[msg.sender] = balanceOf[msg.sender].sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    if (balanceOf[msg.sender] == 0) _removeHolder(msg.sender);
    if (balanceOf[to] > 0) _addHolder(to);

    return true;
  }

  function approve(address spender, uint256 value) external override returns (bool) {
    _allowances[msg.sender][spender] = value;

    return true;
  }

  function transferFrom(address from, address to, uint256 value) external override returns (bool) {
    // SafeMath.sub reverts on underflow, making an explicit require redundant here
    _allowances[from][msg.sender] = _allowances[from][msg.sender].sub(value);
    _settle(from);
    _settle(to);
    balanceOf[from] = balanceOf[from].sub(value);
    balanceOf[to] = balanceOf[to].add(value);
    if (balanceOf[from] == 0) _removeHolder(from);
    if (balanceOf[to] > 0) _addHolder(to);

    return true;
  }

  // IMintableToken

  function mint() external payable override {
    require(msg.value > 0, "Ether Value must be nonzero");
    _settle(msg.sender);
    balanceOf[msg.sender] = balanceOf[msg.sender].add(msg.value);
    totalSupply = totalSupply.add(msg.value);

    _addHolder(msg.sender);
  }
  function _addHolder(address addr) private {
    if (_holderIndex[addr] == 0) {
      _holders.push(addr);
      _holderIndex[addr] = _holders.length;
    }
  }

  function burn(address payable dest) external override {
    uint256 amount = balanceOf[msg.sender];
    require(amount > 0, "Nothing to burn");
    _settle(msg.sender);
    balanceOf[msg.sender] = 0; // Set balance 0 before sending ETH
    totalSupply = totalSupply.sub(amount);
    _removeHolder(msg.sender);
    dest.transfer(amount);
  }
  function _removeHolder(address addr) private {
    uint256 idx = _holderIndex[addr];
    if(idx == 0) return;
// Instead of shifting the array we replace the last holder to the place of the one removed.
    uint256 lastIdx = _holders.length - 1;
    address lastHolder = _holders[lastIdx];
    _holders[idx -1] = lastHolder;
    _holderIndex[lastHolder] = idx;
    _holders.pop();
    _holderIndex[addr] = 0;

  }

  // IDividends

  function getNumTokenHolders() external view override returns (uint256) {
    return _holders.length;
  }

  function getTokenHolder(uint256 index) external view override returns (address) {
    return _holders[index - 1];
  }

  function recordDividend() external payable override {
    require(msg.value > 0, "Insufficient funds");
    _dividendPerShare = _dividendPerShare.add(msg.value.mul(SCALE).div(totalSupply));
  }


  function getWithdrawableDividend(address payee) external view override returns (uint256) {
      return _dividends[payee].add(_pendingDividend(payee));
  }

function _pendingDividend(address addr) private view returns (uint256) {
  return balanceOf[addr].mul(_dividendPerShare.sub(_dividendDebt[addr])).div(SCALE);
}

function _settle(address addr) private {
  if (_dividendPerShare == 0) return;
  _dividends[addr] = _dividends[addr].add(_pendingDividend(addr));
  _dividendDebt[addr] = _dividendPerShare;
}

  function withdrawDividend(address payable dest) external override {
    _settle(msg.sender);
    uint256 amount = _dividends[msg.sender];
    _dividends[msg.sender] = 0;
    dest.transfer(amount);
  }
}