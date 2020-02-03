pragma solidity ^0.5.0;

import "@openzeppelin/contracts/token/ERC721/ERC721Full.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721Burnable.sol";
import "@openzeppelin/contracts/ownership/Ownable.sol";
import "./Strings.sol";

contract OwnableDelegateProxy { }

contract ProxyRegistry {
    mapping(address => OwnableDelegateProxy) public proxies;
}

/**
 * @title Promoted Pool
 * Promoted Pool - ERC721 contract that gives the holder the right to promote a pool on pools.fyi during the specified timeframe.
 */
contract PromotedPool is ERC721Full, ERC721Burnable, Ownable {
  using Strings for string;

  address proxyRegistryAddress;
  uint256 private _currentTokenId;
  uint256 private _activeTokenId;

  struct PromotionPeriod {
    uint256 startTime;
    uint256 endTime;
  }

  struct PoolProposal {
    address proposedPool;
    address approvedPool;
  }

  mapping (uint256 => PromotionPeriod) promotionPeriods;
  mapping (uint256 => PoolProposal) proposedPools;

  event MintedToken(uint256 indexed tokenId, address indexed tokenOwner, uint256 indexed startTime, uint256 endTime);
  event PromotedPoolProposed(address indexed poolAddress, uint256 indexed tokenId, uint256 indexed startTime, uint256 endTime);
  event PromotedPoolApproved(address indexed poolAddress, uint256 indexed tokenId, uint256 indexed startTime, uint256 endTime);
  event ActiveTokenUpdated(uint256 indexed tokenId);
  event PromotedPoolReset(uint256 indexed tokenId);

  constructor(string memory _name, string memory _symbol, address _proxyRegistryAddress) ERC721Full(_name, _symbol) public {
    proxyRegistryAddress = _proxyRegistryAddress;
    // promotionPeriods[_currentTokenId].startTime = 0;
    // promotionPeriods[_currentTokenId].endTime = 0;
  }

  /**
    * @dev Mints a token to an address with a tokenURI.
    * @param _to address of the future owner of the token
    */
  function mintTo(address _to, uint256 _startTime, uint256 _endTime) public onlyOwner {
    require(_startTime > now, "Token must have start time in the future.");
    require(_startTime > promotionPeriods[_currentTokenId].endTime, "Token must have start time > most recent token's end time");
    if(promotionPeriods[_currentTokenId].endTime != 0) {
      require(_startTime - promotionPeriods[_currentTokenId].endTime < 7890000 , "Token must have start time < 1 year after the most recent token's end time");
    }
    uint256 newTokenId = _getNextTokenId();
    _mint(_to, newTokenId);
    _incrementTokenId();
    promotionPeriods[newTokenId] = PromotionPeriod(_startTime, _endTime);
    proposedPools[newTokenId] = PoolProposal(address(0), address(0));
    emit MintedToken(newTokenId, _to, _startTime, _endTime);
  }

  function proposePromotedPool(uint256 _tokenId, address _poolAddress) public {
    require(msg.sender == ownerOf(_tokenId), "You must be the owner of a valid token to propose a promoted pool");
    require(promotionPeriods[_tokenId].endTime > now, "Sorry, this token has expired");
    proposedPools[_tokenId].proposedPool = _poolAddress;
    emit PromotedPoolProposed(_poolAddress, _tokenId, promotionPeriods[_tokenId].startTime, promotionPeriods[_tokenId].endTime);
  }

  function approvePromotedPool(uint256 _tokenId, address _poolAddress) public onlyOwner {
    require(proposedPools[_tokenId].proposedPool == _poolAddress, "Pool address must match pool proposed by token holder");
    require(promotionPeriods[_tokenId].endTime > now, "This token has expired");
    proposedPools[_tokenId].approvedPool = _poolAddress;
    emit PromotedPoolApproved(_poolAddress, _tokenId, promotionPeriods[_tokenId].startTime, promotionPeriods[_tokenId].endTime);
  }

  function resetPromotedPool(uint256 _tokenId) public onlyOwner {
    proposedPools[_tokenId].approvedPool = address(0);
    emit PromotedPoolReset(_tokenId);
  }

  function getPromotedPool() public returns (address) {
    return proposedPools[_activeTokenId].approvedPool;
  }

  function setPromotedPool() public {
    require(_currentTokenId > _activeTokenId, "Mint new token first.");
    if (now >= promotionPeriods[_activeTokenId].endTime) {
      ++_activeTokenId;
      emit ActiveTokenUpdated(_activeTokenId);
    }
  }

  /**
    * @dev calculates the next token ID based on value of _currentTokenId 
    * @return uint256 for the next token ID
    */
  function _getNextTokenId() private view returns (uint256) {
    return _currentTokenId.add(1);
  }

  /**
    * @dev increments the value of _currentTokenId 
    */
  function _incrementTokenId() private  {
    _currentTokenId++;
  }

  function baseTokenURI() public view returns (string memory) {
    return "https://promoted-pools.herokuapp.com/";
  }

  function tokenURI(uint256 _tokenId) external view returns (string memory) {
    return Strings.strConcat(
        baseTokenURI(),
        Strings.uint2str(_tokenId)
    );
  }

  /**
   * Override isApprovedForAll to whitelist user's OpenSea proxy accounts to enable gas-less listings.
   */
  function isApprovedForAll(
    address owner,
    address operator
  )
    public
    view
    returns (bool)
  {
    // Whitelist OpenSea proxy contract for easy trading.
    ProxyRegistry proxyRegistry = ProxyRegistry(proxyRegistryAddress);
    if (address(proxyRegistry.proxies(owner)) == operator) {
        return true;
    }

    return super.isApprovedForAll(owner, operator);
  }
}
