// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract WCardsNFTOnClaim is ERC721Enumerable, Ownable, ReentrancyGuard {
    using Strings for uint256;

    struct WinnerInfo {
        uint256[] winningNumbers;
        uint256[] roundNumbers;
        uint256 roundId;
        uint256 tokenBuyId;
    }

    string public baseURI = "";
    string public baseExtension = ".json";
    uint256 public numTokens = 0;

    mapping(uint256 => WinnerInfo) public nftInfo;

    address public wCardsGame;
    uint256 public tokenIdCounter;

    constructor(address _wCardsGame) ERC721("NFTToken", "NFT") {
        wCardsGame = _wCardsGame;
        tokenIdCounter++;
    }

    function setBaseURI(string memory _uri) external onlyOwner {
        baseURI = _uri;
    }

    function setWCardsGame(address _newCards) external onlyOwner {
        wCardsGame = _newCards;
    }

    function mint(
        address user,
        uint256[] calldata winningNumbers,
        uint256 roundId,
        uint256 tokenBuyId,
        uint256[] calldata roundNumbers
    ) external {
        require(msg.sender == wCardsGame, "Not authorized");
        uint256 tokenId = tokenIdCounter;
        _safeMint(user, tokenId);
        tokenIdCounter++;

        WinnerInfo storage nft = nftInfo[tokenId];

        nft.roundId = roundId;
        nft.roundNumbers = roundNumbers;
        nft.tokenBuyId = tokenBuyId;
        nft.winningNumbers = winningNumbers;
    }

    function walletOfOwner(address _owner) external view returns (uint256[] memory) {
        uint256 tokenCount = balanceOf(_owner);

        uint256[] memory tokensId = new uint256[](tokenCount);
        for (uint256 i; i < tokenCount; i++) {
            tokensId[i] = tokenOfOwnerByIndex(_owner, i);
        }
        return tokensId;
    }

    function getNFTInfo(uint256 tokenId) public view returns (WinnerInfo memory) {
        return nftInfo[tokenId];
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721: URI query for nonexistent token");

        string memory currentBaseURI = _baseURI();
        return
            bytes(currentBaseURI).length > 0
                ? string(abi.encodePacked(currentBaseURI, tokenId.toString(), baseExtension))
                : "";
    }

    function supportsInterface(bytes4 interfaceId) public view override returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId, uint256 batchSize) internal override {
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    // ----- ERC721 functions -----
    function _baseURI() internal view override(ERC721) returns (string memory) {
        return baseURI;
    }
}
