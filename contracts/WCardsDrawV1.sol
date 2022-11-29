//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;
// Imported OZ helper contracts
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

import "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";

interface IWCardsNFTOnClaim {
    function mint(
        address _user,
        uint256[] memory winningNumbers,
        uint256 roundId,
        uint256 tokenBuyId,
        uint256[] memory roundNumbers
    ) external;
}

interface IWCardsNFTOnBuy {
    function claimWCard(address _user, uint256 _wcardID, uint256 _drawId) external;

    function wcardMint(
        address _to,
        uint256 _drawId,
        uint256[] memory _numbers,
        string memory _newURI
    ) external returns (uint256);

    function getOwnerOfWCard(uint256 _wcardID) external view returns (address);

    function getTotalSupply() external view returns (uint256);
}

contract WCardsDrawV1 is VRFConsumerBaseV2, Ownable, Initializable {
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    using Address for address;

    bytes32 public keyHash = 0x79d3d8832d904592c0bf9818b621522c988bb8b0c05cdc3b15aea1b6e8db0c15;
    uint32 public callbackGasLimit = 2000000;
    uint16 public requestConfirmations = 3;
    uint32 public numWords = 2;
    uint64 public subscriptionId;

    address public _charityWallet = address(0x123);
    address public _distributionWallet = address(0x456);
    address public _teamWallet = address(0x789);

    mapping(uint256 => uint256) internal requestToDraw;
    mapping(address => bool) internal isRelay;
    mapping(uint256 => EnumerableSet.UintSet) internal idToNumbers;

    VRFCoordinatorV2Interface public coordinator;

    // State variables
    // Instance of WBlock token (collateral currency for draw)
    IERC20 internal wBlock;
    // Storing of the NFT
    IWCardsNFTOnBuy internal nftOnBuy;
    IWCardsNFTOnClaim internal nftOnClaim;
    // Counter for draw IDs
    uint256 private drawIdCounter;

    // Represents the status of the draw
    enum Status {
        NotStarted, // The draw has not started yet
        Open, // The draw is open for WCards purchases
        Completed // The draw has been closed and the numbers drawn
    }
    // All the needed info around a draw
    struct DrawInfo {
        Status drawStatus; // Status for draw
        uint256 drawType; // Type of draw
        uint256 prizePoolInWBlock; // The amount of WBlock for prize money
        uint256 costPerWCard; // Cost per WCard in $WBLOCK
        uint32[] prizeDistribution; // The distribution for prize money
        uint256 startingTimestamp; // Block timestamp for start of draw
        uint256 closingTimestamp; // Block timestamp for end of entries
        uint256[] winningNumbers; // The winning numbers
        uint256[] winnerCount;
        uint256[] tokenIds;
    }

    struct CurrentValues {
        uint8 sizeOfDraw;
        uint16 maxValidRange;
        uint32[] prizeDistribution;
        uint32 duration;
        uint256 costPerWCard;
    }

    // Draw ID's to info
    mapping(uint256 => DrawInfo) internal allDraws_;
    mapping(uint256 => uint256[]) internal allDrawsByType;
    CurrentValues[3] public values;

    mapping(uint256 => uint256) public currentDrawId;

    //-------------------------------------------------------------------------
    // EVENTS
    //-------------------------------------------------------------------------

    event NewMint(address indexed minter, uint256 wcardID, uint256[] numbers, uint256 cost);

    event RequestNumbers(uint256 drawId, uint256 requestId);

    event UpdatedValues(
        uint8 drawType,
        uint8 sizeOfDraw,
        uint16 maxValidRange,
        uint32[] prizeDistribution,
        uint32 duration,
        uint256 costPerWCard
    );

    event JackpotDistributed(
        uint256 drawId,
        address charityWallet,
        address distributionWallet,
        address teamWallet,
        uint256 jackpotShare,
        uint256 eachJackpotShare
    );

    event DrawOpen(uint256 drawId, uint256 wcardSupply);

    event DrawClose(uint256 drawId, uint256[] winningNumbers, uint256[] winnerCount);

    //-------------------------------------------------------------------------
    // MODIFIERS
    //-------------------------------------------------------------------------

    modifier notContract() {
        require(!address(msg.sender).isContract(), "contract not allowed");
        //solhint-disable-next-line
        require(msg.sender == tx.origin, "proxy contract not allowed");
        _;
    }

    //-------------------------------------------------------------------------
    // CONSTRUCTOR
    //-------------------------------------------------------------------------

    constructor(
        address _wBlock,
        uint8 _sizeOfDrawNumbers,
        uint16 _maxValidNumberRange
    ) VRFConsumerBaseV2(0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D) {
        require(_wBlock != address(0), "Contracts cannot be 0 address");
        require(_sizeOfDrawNumbers != 0 && _maxValidNumberRange != 0, "Draw setup cannot be 0");
        wBlock = IERC20(_wBlock);
        coordinator = VRFCoordinatorV2Interface(
            0x2Ca8E0C643bDe4C2E08ab1fA0da3401AdAD7734D
        );

        for (uint8 i = 0; i < 3; i++) {
            values[i] = CurrentValues({
                sizeOfDraw: _sizeOfDrawNumbers,
                maxValidRange: _maxValidNumberRange,
                prizeDistribution: new uint32[](0),
                duration: 10 minutes,
                costPerWCard: 1 * 10 ** 18
            });

            values[i].prizeDistribution.push(5);
            values[i].prizeDistribution.push(10);
            values[i].prizeDistribution.push(100);
            values[i].prizeDistribution.push(10000);
            values[i].prizeDistribution.push(50000);
        }

        isRelay[msg.sender] = true;
    }

    function initialize(
        address _wCardsNFTBuy,
        address _wCardsNFTClaim,
        uint64 _subscriptionId
    ) external initializer onlyOwner {
        require(
            _wCardsNFTBuy != address(0) && _wCardsNFTClaim != address(0) && _subscriptionId != 0,
            "Contracts cannot be 0 address"
        );

        nftOnClaim = IWCardsNFTOnClaim(_wCardsNFTClaim);
        nftOnBuy = IWCardsNFTOnBuy(_wCardsNFTBuy);
        subscriptionId = _subscriptionId;

        createNewDraw(0);
        createNewDraw(1);
        createNewDraw(2);
    }

    //-------------------------------------------------------------------------
    // VIEW FUNCTIONS
    //-------------------------------------------------------------------------

    function getBasicDrawInfo(uint256 _drawId) external view returns (DrawInfo memory) {
        return (allDraws_[_drawId]);
    }

    function getMaxRange(uint8 _drawtype) external view returns (uint16) {
        return values[_drawtype].maxValidRange;
    }

    function getDrawsPerDrawType(uint256 _drawType) external view returns (uint256[] memory){
        return allDrawsByType[_drawType];
    }

    //-------------------------------------------------------------------------
    // STATE MODIFYING FUNCTIONS
    //-------------------------------------------------------------------------

    //-------------------------------------------------------------------------
    // Restricted Access Functions (onlyOwner)

    function setValues(
        uint8 drawType,
        uint8 sizeOfDraw,
        uint16 maxValidRange,
        uint32[] calldata prizeDistribution,
        uint32 duration,
        uint256 costPerWCard
    ) external onlyOwner {
        require(prizeDistribution.length == sizeOfDraw, "Invalid prize distribution");

        values[drawType].sizeOfDraw = sizeOfDraw;
        values[drawType].maxValidRange = maxValidRange;
        values[drawType].prizeDistribution = prizeDistribution;
        values[drawType].duration = duration;
        values[drawType].costPerWCard = costPerWCard;

        emit UpdatedValues(drawType, sizeOfDraw, maxValidRange, prizeDistribution, duration, costPerWCard);
    }

    function setWallets(address charityWallet, address distributionWallet, address teamWallet) external onlyOwner {
        _charityWallet = charityWallet;
        _distributionWallet = distributionWallet;
        _teamWallet = teamWallet;
    }

    function requestRandomWords() internal returns (uint256 requestId) {
        requestId = coordinator.requestRandomWords(
            keyHash,
            subscriptionId,
            requestConfirmations,
            callbackGasLimit,
            numWords
        );
        return requestId;
    }

    function drawWinningNumbers(uint256 _drawId) external {
        require(isRelay[msg.sender], "Not authorized");
        require(allDraws_[_drawId].closingTimestamp <= block.timestamp, "Cannot set winning numbers during draw");
        require(allDraws_[_drawId].drawStatus == Status.Open, "Draw State incorrect for draw");
        uint256 requestId = requestRandomWords();
        requestToDraw[requestId] = _drawId;

        uint256 jackpotShare = (allDraws_[_drawId].prizePoolInWBlock * 30) / 100;
        uint256 eachJackpotShare = jackpotShare / 3;
        wBlock.safeTransfer(address(_charityWallet), eachJackpotShare);
        wBlock.safeTransfer(address(_distributionWallet), eachJackpotShare);
        wBlock.safeTransfer(address(_teamWallet), eachJackpotShare);
        allDraws_[_drawId].prizePoolInWBlock = allDraws_[_drawId].prizePoolInWBlock - jackpotShare;

        createNewDraw(0);
        createNewDraw(1);
        createNewDraw(2);

        emit JackpotDistributed(
            _drawId,
            _charityWallet,
            _distributionWallet,
            _teamWallet,
            jackpotShare,
            eachJackpotShare
        );

        emit RequestNumbers(_drawId, requestId);
    }

    function createNewDraw(uint256 _drawType) internal returns (uint256 drawId) {
        drawIdCounter++;
        drawId = drawIdCounter;

        uint256 _start = nftOnBuy.getTotalSupply();

        DrawInfo memory newDraw = DrawInfo(
            Status.Open,
            _drawType,
            0,
            values[_drawType].costPerWCard,
            values[_drawType].prizeDistribution,
            block.timestamp,
            block.timestamp + values[_drawType].duration,
            new uint256[](values[_drawType].sizeOfDraw),
            new uint256[](values[_drawType].sizeOfDraw),
            new uint256[](0)
        );

        allDraws_[drawId] = newDraw;
        emit DrawOpen(drawId, _start);

        currentDrawId[_drawType] = drawId;
        allDrawsByType[_drawType].push(drawId);
    }

    function withdrawWBlock(uint256 _amount) external onlyOwner {
        wBlock.transfer(msg.sender, _amount);
    }

    //-------------------------------------------------------------------------
    // General Access Functions

    function buyWCard(uint256 _drawId, uint256[] calldata _chosenNumbers, string calldata _uri) external notContract {
        require(block.timestamp >= allDraws_[_drawId].startingTimestamp, "Invalid time for mint:start");
        require(block.timestamp < allDraws_[_drawId].closingTimestamp, "Invalid time for mint:end");
        if (allDraws_[_drawId].drawStatus == Status.NotStarted) {
            if (allDraws_[_drawId].startingTimestamp <= block.timestamp) {
                allDraws_[_drawId].drawStatus = Status.Open;
            }
        }
        uint256 _drawType = allDraws_[_drawId].drawType;
        require(allDraws_[_drawId].drawStatus == Status.Open, "Draw not in state for mint");
        require(bytes(_uri).length != 0, "Invalid ipfsURI");
        require(_chosenNumbers.length == values[_drawType].sizeOfDraw, "Invalid chosen numbers");

        wBlock.transferFrom(msg.sender, address(this), allDraws_[_drawId].costPerWCard);
        allDraws_[_drawId].prizePoolInWBlock = allDraws_[_drawId].prizePoolInWBlock + allDraws_[_drawId].costPerWCard;
        uint256 wcardId = nftOnBuy.wcardMint(msg.sender, _drawId, _chosenNumbers, _uri);

        for (uint256 i = 0; i < values[_drawType].sizeOfDraw; i++) {
            require(_chosenNumbers[i] <= values[_drawType].maxValidRange, "Invalid chosen numbers");
            require(!idToNumbers[wcardId].contains(_chosenNumbers[i]), "Duplicate numbers");
            idToNumbers[wcardId].add(_chosenNumbers[i]);
        }

        allDraws_[_drawId].tokenIds.push(wcardId);
        emit NewMint(msg.sender, wcardId, _chosenNumbers, allDraws_[_drawId].costPerWCard);
    }

    function claimBatchReward(uint256[] memory _drawIds, uint256[] memory _tokenIds) external notContract {
        uint256 len = _drawIds.length;
        require(len == _tokenIds.length, "Invalid input");

        for (uint256 i = 0; i < len; i++) {
            uint256 _drawId = _drawIds[i];
            uint256 _tokenId = _tokenIds[i];
            DrawInfo memory draw = allDraws_[_drawId];

            require(draw.closingTimestamp <= block.timestamp, "Wait till end to claim");
            require(draw.drawStatus == Status.Completed, "Winning Numbers not chosen yet");
            require(nftOnBuy.getOwnerOfWCard(_tokenId) == msg.sender, "Only the owner can claim");
            nftOnBuy.claimWCard(msg.sender, _tokenId, _drawId);

            uint8 matchingNumbers = _getNumberOfMatching(idToNumbers[_tokenId], draw.winningNumbers);
            uint256 prizeAmount = _prizeForMatching(matchingNumbers, _drawId);
            wBlock.safeTransfer(address(msg.sender), prizeAmount);

            nftOnClaim.mint(msg.sender, draw.winningNumbers, _drawId, _tokenId, idToNumbers[_tokenId].values());
        }
    }

    //-------------------------------------------------------------------------
    // INTERNAL FUNCTIONS
    //-------------------------------------------------------------------------

    function _getNumberOfMatching(
        EnumerableSet.UintSet storage _usersNumbers,
        uint256[] memory _winningNumbers
    ) internal view returns (uint8 noOfMatching) {
        for (uint256 i = 0; i < _winningNumbers.length; i++) {
            if (_usersNumbers.contains(_winningNumbers[i])) {
                noOfMatching += 1;
            }
        }
    }

    /**
     * @param   _noOfMatching: The number of matching numbers the user has
     * @param   _drawId: The ID of the draw the user is claiming on
     * @return  uint256: The prize amount in WBlock the user is entitled to
     */
    function _prizeForMatching(uint8 _noOfMatching, uint256 _drawId) internal view returns (uint256) {
        uint256 prize = 0;
        if (_noOfMatching == 0) {
            return 0;
        }
        uint256 perOfPool = allDraws_[_drawId].prizeDistribution[_noOfMatching - 1];
        prize = (allDraws_[_drawId].prizePoolInWBlock * perOfPool) / allDraws_[_drawId].winnerCount[_noOfMatching - 1];
        return prize / 100000;
    }

    function _split(uint256 _drawType, uint256 _randomNumber) internal view returns (uint256[] memory) {
        uint256[] memory winningNumbers = new uint256[](values[_drawType].sizeOfDraw);
        for (uint256 i = 0; i < values[_drawType].sizeOfDraw; i++) {
            uint256 numberRepresentation = uint256(keccak256(abi.encodePacked(_randomNumber, i)));
            winningNumbers[i] = uint16(numberRepresentation % values[_drawType].maxValidRange);
        }
        return winningNumbers;
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        uint256 _drawId = requestToDraw[_requestId];
        DrawInfo storage draw = allDraws_[_drawId];
        draw.drawStatus = Status.Completed;
        draw.winningNumbers = _split(draw.drawType, _randomWords[0]);

        uint256 drawSize = values[draw.drawType].sizeOfDraw;
        uint256 counter;
        uint256 len = allDraws_[_drawId].tokenIds.length;

        uint256[] memory winnerCount = new uint256[](drawSize);
        uint256[] memory tokenIds = draw.tokenIds;

        for (uint256 i = 0; i < len; ) {
            unchecked {
                counter = 0;
                EnumerableSet.UintSet storage nums = idToNumbers[tokenIds[i]];
                for (uint256 j = 0; j < drawSize; j++) {
                    if (nums.contains(draw.winningNumbers[j])) {
                        counter++;
                    }
                }
                if (counter > 0) {
                    winnerCount[counter - 1]++;
                }
                delete allDraws_[_drawId].tokenIds[i];
                i++;
            }
        }

        draw.winnerCount = winnerCount;

        emit DrawClose(_drawId, draw.winningNumbers, winnerCount);
    }
}
