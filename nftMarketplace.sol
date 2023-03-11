// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract NFTMarketplace {
    using SafeERC20 for IERC20;

    address public owner;
    uint256 public fee;

    struct Listing {
        address seller;
        address nftContract;
        uint256 tokenId;
        uint256 price;
        uint256 auctionStartTime;
        uint256 auctionEndTime;
        uint256 minimumBid;
        address bidToken;
        uint256 highestBid;
        address highestBidder;
        bool isAuction;
    }

    mapping(uint256 => Listing) public listings;

    event NFTListed(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed nftContract,
        uint256 price,
        uint256 auctionStartTime,
        uint256 auctionEndTime,
        bool isAuction
    );
    event NFTSold(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        address nftContract,
        uint256 price
    );
    event NFTAuctionStarted(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed nftContract,
        uint256 minimumBid,
        uint256 auctionStartTime,
        uint256 auctionEndTime
    );
    event NFTAuctionEnded(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed highestBidder,
        address nftContract,
        uint256 price
    );

    constructor() {
        owner = msg.sender;
        fee = 100;
    }

    function listForSale(
        address _nftContract,
        uint256 _tokenId,
        uint256 _price,
        uint256 _auctionStartTime,
        uint256 _auctionEndTime,
        uint256 _minimumBid
    ) external {
        require(
            IERC721(_nftContract).ownerOf(_tokenId) == msg.sender,
            "Not the owner of this NFT"
        );
        IERC721(_nftContract).transferFrom(msg.sender, address(this), _tokenId);
        listings[_tokenId] = Listing({
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            price: 0,
            auctionStartTime: _auctionStartTime,
            auctionEndTime: _auctionEndTime,
            minimumBid: _minimumBid,
            isAuction: true,
            bidToken: address(0),
            highestBid: 0,
            highestBidder: address(0)
        });
        emit NFTListed(_tokenId, msg.sender, _nftContract, _price, 0, 0, false);
    }

    function listForAuction(
        address _nftContract,
        uint256 _tokenId,
        uint256 _minimumBid,
        uint256 _auctionStartTime,
        uint256 _auctionEndTime
    ) external {
        require(
            IERC721(_nftContract).ownerOf(_tokenId) == msg.sender,
            "Not the owner of this NFT"
        );
        require(_minimumBid > 0, "Minimum bid must be greater than zero");
        require(
            _auctionStartTime > block.timestamp,
            "Auction start time must be in the future"
        );
        require(
            _auctionEndTime > _auctionStartTime,
            "Auction end time must be after auction start time"
        );
        IERC721(_nftContract).transferFrom(msg.sender, address(this), _tokenId);
        listings[_tokenId] = Listing({
            seller: msg.sender,
            nftContract: _nftContract,
            tokenId: _tokenId,
            price: 0,
            auctionStartTime: _auctionStartTime,
            auctionEndTime: _auctionEndTime,
            minimumBid: _minimumBid,
            isAuction: true,
            bidToken: address(0),
            highestBid: 0,
            highestBidder: address(0)
        });
        emit NFTAuctionStarted(
            _tokenId,
            msg.sender,
            _nftContract,
            _minimumBid,
            _auctionStartTime,
            _auctionEndTime
        );
    }

    function buyNFT(uint256 _tokenId, uint256 _amount) external payable {
    Listing storage listing = listings[_tokenId];
    require(listing.price > 0, "NFT is not for sale");
    require(
        msg.value >= listing.price || IERC20(listing.bidToken).allowance(msg.sender, address(this)) >= listing.price,
        "Insufficient payment"
    );

    if (listing.bidToken == address(0)) {
        require(msg.value >= listing.price, "Insufficient payment");

        address payable seller = payable(listing.seller);
        uint256 salePrice = listing.price;
        uint256 feeAmount = (salePrice * fee) / 10000;
        uint256 sellerAmount = salePrice - feeAmount;

        IERC721(listing.nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            listing.tokenId
        );
        seller.transfer(sellerAmount);
        payable(owner).transfer(feeAmount);

        emit NFTSold(
            listing.tokenId,
            seller,
            msg.sender,
            listing.nftContract,
            salePrice
        );
    } else {
        require(IERC20(listing.bidToken).transferFrom(msg.sender, address(this), listing.price), "Payment failed");

        if (listing.highestBid == 0) {
            require(listing.price >= listing.minimumBid, "Bid too low");
            listing.highestBid = listing.price;
            listing.highestBidder = msg.sender;
        } else {
            require(_amount > listing.highestBid, "Bid too low");
            uint256 returnAmount = _amount - listing.highestBid;
            IERC20(listing.bidToken).transfer(listing.highestBidder, returnAmount);
            listing.highestBid = _amount;
            listing.highestBidder = msg.sender;
        }

        emit NFTAuctionEnded(
            listing.tokenId,
            listing.seller,
            listing.highestBidder,
            listing.nftContract,
            listing.highestBid
        );
    }

    delete listings[_tokenId];
}

    function placeBid(uint256 _tokenId, uint256 _amount) external {
        Listing storage listing = listings[_tokenId];
        require(listing.isAuction, "NFT is not on auction");
        require(
            block.timestamp >= listing.auctionStartTime &&
                block.timestamp <= listing.auctionEndTime,
            "Auction is not active"
        );
        require(_amount >= listing.minimumBid, "Bid is too low");

        if (listing.highestBidder != address(0)) {
            IERC20(listing.bidToken).safeTransfer(
                listing.highestBidder,
                listing.highestBid
            );
        }

        IERC20(listing.bidToken).safeTransferFrom(
            msg.sender,
            address(this),
            _amount
        );
        listing.highestBidder = msg.sender;
        listing.highestBid = _amount;
    }

    function endAuction(uint256 _tokenId) external {
        Listing storage listing = listings[_tokenId];
        require(listing.isAuction, "NFT is not on auction");
        require(
            block.timestamp > listing.auctionEndTime,
            "Auction is still active"
        );

        address payable seller = payable(listing.seller);
        IERC721(listing.nftContract).safeTransferFrom(
            address(this),
            listing.highestBidder,
            listing.tokenId
        );

        uint256 salePrice = listing.highestBid;
        uint256 feeAmount = (salePrice * fee) / 10000;
        uint256 sellerAmount = salePrice - feeAmount;

        IERC20(listing.bidToken).safeTransfer(seller, sellerAmount);
        payable(owner).transfer(feeAmount);

        emit NFTAuctionEnded(
            _tokenId,
            seller,
            listing.highestBidder,
            listing.nftContract,
            salePrice
        );
        delete listings[_tokenId];
    }

    function cancelListing(uint256 _tokenId) external {
        Listing storage listing = listings[_tokenId];
        require(msg.sender == listing.seller, "Not the seller of this NFT");

        IERC721(listing.nftContract).safeTransferFrom(
            address(this),
            msg.sender,
            listing.tokenId
        );

        delete listings[_tokenId];
    }

    function setFee(uint256 _fee) external {
        require(msg.sender == owner, "Only owner can change fee");
        require(_fee <= 1000, "Fee cannot be more than 10%");
        fee = _fee;
    }
}
