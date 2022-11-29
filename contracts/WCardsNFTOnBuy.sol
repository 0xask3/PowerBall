//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

contract WCardsNFTOnBuy is ERC1155, Ownable {
    using EnumerableSet for EnumerableSet.UintSet;
    // State variables
    address internal drawContract_;

    uint256 internal totalSupply_;
    // Storage for WCard information
    struct WCardInfo {
        address owner;
        EnumerableSet.UintSet numbers;
        bool claimed;
        uint256 drawId;
        string _newURI;
    }
    // Token ID => Token information
    mapping(uint256 => WCardInfo) internal wcardInfo_;
    // User address => Draw ID => WCard IDs
    mapping(address => mapping(uint256 => uint256[])) internal userWCards_;

    //-------------------------------------------------------------------------
    // EVENTS
    //-------------------------------------------------------------------------

    event InfoMint(address indexed receiving, uint256 drawId, uint256 tokenId);

    //-------------------------------------------------------------------------
    // MODIFIERS
    //-------------------------------------------------------------------------

    /**
     * @notice  Restricts minting of new tokens to only the draw contract.
     */
    modifier onlyDraw() {
        require(msg.sender == drawContract_, "Only Draw can mint");
        _;
    }

    //-------------------------------------------------------------------------
    // CONSTRUCTOR
    //-------------------------------------------------------------------------

    /**

     *          https://eips.ethereum.org/EIPS/eip-1155#metadata[defined in the EIP].
     * @param   _draw The address of the draw contract. The draw contract has
     *          elevated permissions on this contract. 
     */
    constructor(string memory _uri, address _draw) ERC1155(_uri) {
        // Only Draw contract will be able to mint new tokens
        drawContract_ = _draw;
    }

    //-------------------------------------------------------------------------
    // VIEW FUNCTIONS
    //-------------------------------------------------------------------------

    function getTotalSupply() external view returns (uint256) {
        return totalSupply_;
    }

    /**
     * @param   _wcardID: The unique ID of the WCard
     * @return  uint32[]: The chosen numbers for that WCard
     */
    function getWCardNumbers(uint256 _wcardID) external view returns (uint256[] memory) {
        return wcardInfo_[_wcardID].numbers.values();
    }

    /**
     * @param   _wcardID: The unique ID of the WCard
     * @return  address: Owner of WCard
     */
    function getOwnerOfWCard(uint256 _wcardID) external view returns (address) {
        return wcardInfo_[_wcardID].owner;
    }

    function getWCardClaimStatus(uint256 _wcardID) external view returns (bool) {
        return wcardInfo_[_wcardID].claimed;
    }

    function getUserWCards(uint256 _drawId, address _user) external view returns (uint256[] memory) {
        return userWCards_[_user][_drawId];
    }

    function getUserWCardsPagination(
        address _user,
        uint256 _drawId,
        uint256 cursor,
        uint256 size
    ) external view returns (uint256[] memory, uint256) {
        uint256 length = size;
        if (length > userWCards_[_user][_drawId].length - cursor) {
            length = userWCards_[_user][_drawId].length - cursor;
        }
        uint256[] memory values = new uint256[](length);
        for (uint256 i = 0; i < length; i++) {
            values[i] = userWCards_[_user][_drawId][cursor + i];
        }
        return (values, cursor + length);
    }

    //-------------------------------------------------------------------------
    // STATE MODIFYING FUNCTIONS
    //-------------------------------------------------------------------------

    /**
     * @param   _to The address being minted to
     * @notice  Only the draw contract is able to mint tokens. 
        // uint8[][] calldata _drawNumbers
     */
    function wcardMint(
        address _to,
        uint256 _drawId,
        uint256[] calldata _numbers,
        string calldata _newURI
    ) external onlyDraw returns (uint256) {
        // Incrementing the tokenId counter
        totalSupply_++;
        uint256 tokenId = totalSupply_;

        WCardInfo storage info = wcardInfo_[totalSupply_];

        info._newURI = _newURI;
        info.claimed = false;
        info.drawId = _drawId;
        info.owner = _to;

        for (uint256 i = 0; i < _numbers.length; i++) {
            info.numbers.add(_numbers[i]);
        }

        userWCards_[_to][_drawId].push(totalSupply_);
        _setURI(_newURI);
        _mint(_to, tokenId, 1, msg.data);
        emit InfoMint(_to, _drawId, tokenId);
        return tokenId;
    }

    function setWCardsGame(address _newCards) external onlyOwner {
        drawContract_ = _newCards;
    }

    function claimWCard(address _user, uint256 _wcardID, uint256 _drawId) external onlyDraw {
        require(wcardInfo_[_wcardID].claimed == false, "WCard already claimed");
        require(wcardInfo_[_wcardID].drawId == _drawId, "WCard not for this draw");

        wcardInfo_[_wcardID].claimed = true;
        _burn(_user, _wcardID, 1);
    }
}
