// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.0;

import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";

import "./interfaces/ITazos.sol";

contract StakingArena is ERC1155HolderUpgradeable, AccessControlUpgradeable {
    using SafeMathUpgradeable for uint256;

    // keccak256("ADMIN_ROLE");
    bytes32 internal constant ADMIN_ROLE =
        0xa49807205ce4d355092ef5a8a18f56e8913cf4a201fbe287825b095693c21775;
    uint256 public constant PERIOD_DURATION = 1 minutes;
    uint256 public constant REWARD_PER_PERIOD = 1;

    bool public finalized;
    uint256 public availableReward;

    uint8 public counter;
    uint256 public totalAllocPoint;
    uint256 public startTime;
    uint256 public currentPeriod;

    ITazos public tazos;

    enum TokenTypes {
        ERC1155,
        ERC721
    }

    struct Pool {
        uint256 tokenId;
        address tokenAddress;
        TokenTypes tokenType;
        uint256 allocPoint;
        uint256 lastRewardPeriod;
    }

    mapping(uint8 => Pool) public poolInfo;
    mapping(address => mapping(uint256 => uint8)) public poolIdByAddress;
    mapping(address => mapping(uint256 => address)) public ownerInfo;

    modifier isFinalized() {
        require(finalized, "StakingArena: Yet to be Finalized");
        _;
    }

    function initialize(ITazos _tazos) external initializer {
        tazos = _tazos;
        startTime = block.timestamp;
        availableReward = 5**10;
        _setupRole(ADMIN_ROLE, _msgSender());
    }

    function finalize() external onlyRole(ADMIN_ROLE) {
        require(!finalized, "StakingArena: Already Finalized");
        finalized = true;
        tazos.mint(address(this), 2 * availableReward);
    }

    function createPool(
        uint256 _tokenId,
        address _tokenAddress,
        string calldata _tokenType,
        uint256 _allocPoint
    ) external onlyRole(ADMIN_ROLE) {
        require(
            poolIdByAddress[_tokenAddress][_tokenId] == 0,
            "StakingArena: Pool already exists"
        );
        counter++;

        TokenTypes tokenType = keccak256(abi.encodePacked(_tokenType)) ==
            keccak256(abi.encodePacked("ERC721"))
            ? TokenTypes.ERC721
            : TokenTypes.ERC1155;

        Pool memory pool = Pool({
            tokenId: _tokenId,
            tokenAddress: _tokenAddress,
            tokenType: tokenType,
            allocPoint: _allocPoint,
            lastRewardPeriod: currentPeriod
        });

        poolInfo[counter] = pool;
        poolIdByAddress[_tokenAddress][_tokenId] = counter;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
    }

    function deposit(uint8 _pid) external isFinalized {
        Pool memory pool = poolInfo[_pid];
        address _tokenAddress = pool.tokenAddress;
        uint256 _tokenId = pool.tokenId;
        pool.lastRewardPeriod = getCurrentPeriod();

        pool.tokenType == TokenTypes.ERC1155
            ? _pullERC1155(_tokenAddress, _tokenId)
            : _pullERC721(_tokenAddress, _tokenId);

        ownerInfo[_tokenAddress][_tokenId] = _msgSender();
    }

    function withdraw(uint8 _pid) external isFinalized {
        Pool memory pool = poolInfo[_pid];
        address _tokenAddress = pool.tokenAddress;
        uint256 _tokenId = pool.tokenId;
        uint256 _currentPeriod = getCurrentPeriod();
        uint256 _noOfPeriods = _currentPeriod - pool.lastRewardPeriod;
        pool.lastRewardPeriod = _currentPeriod;
        poolInfo[_pid] = pool;
        ownerInfo[_tokenAddress][_tokenId] = address(0);

        pool.tokenType == TokenTypes.ERC1155
            ? _pushERC1155(_tokenAddress, _tokenId)
            : _pushERC721(_tokenAddress, _tokenId);

        _issueReward(_noOfPeriods);
    }

    function getCurrentPeriod() public view returns (uint256) {
        return (block.timestamp - startTime) / PERIOD_DURATION;
    }

    function _issueReward(uint256 _noOfPeriods) internal {
        uint256 rewardAmount = (_noOfPeriods * REWARD_PER_PERIOD);
        require(
            rewardAmount < availableReward,
            "StakingArena: Rewards Limit Reached"
        );
        availableReward -= rewardAmount;
        tazos.transfer(_msgSender(), rewardAmount);
    }

    function _pullERC1155(address _tokenContract, uint256 _tokenId) internal {
        IERC1155Upgradeable(_tokenContract).safeTransferFrom(
            _msgSender(),
            address(this),
            _tokenId,
            1,
            bytes("")
        );
    }

    function _pullERC721(address _tokenContract, uint256 _tokenId) internal {
        IERC721Upgradeable(_tokenContract).safeTransferFrom(
            _msgSender(),
            address(this),
            _tokenId
        );
    }

    function _pushERC1155(address _tokenContract, uint256 _tokenId) internal {
        IERC1155Upgradeable(_tokenContract).safeTransferFrom(
            address(this),
            _msgSender(),
            _tokenId,
            1,
            bytes("")
        );
    }

    function _pushERC721(address _tokenContract, uint256 _tokenId) internal {
        IERC721Upgradeable(_tokenContract).safeTransferFrom(
            address(this),
            _msgSender(),
            _tokenId
        );
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        virtual
        override(ERC1155ReceiverUpgradeable, AccessControlUpgradeable)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
