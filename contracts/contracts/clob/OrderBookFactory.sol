pragma solidity =0.8.20;

import "./OrderBook.sol";

interface IPasGovernorMarkets {
    function marketListed(bytes32 marketId) external view returns (bool);
    function marketId(address base, address quote) external pure returns (bytes32);
    function defaultFeeBps() external view returns (uint16);
    function defaultFeeRecipient() external view returns (address);
}

contract OrderBookFactory {
    address public immutable governor;
    address public immutable matcherProxy;

    mapping(bytes32 => address) public getOrderBook;

    event MarketCreated(bytes32 indexed marketId, address indexed base, address indexed quote, address orderBook);

    constructor(address _governor, address _matcherProxy) {
        require(_governor != address(0), "OrderBookFactory: ZERO_GOVERNOR");
        require(_matcherProxy != address(0), "OrderBookFactory: ZERO_MATCHER");
        governor = _governor;
        matcherProxy = _matcherProxy;
    }

    function createMarket(address base, address quote) external returns (address orderBook) {
        bytes32 id = IPasGovernorMarkets(governor).marketId(base, quote);
        require(IPasGovernorMarkets(governor).marketListed(id), "OrderBookFactory: MARKET_NOT_LISTED");
        require(getOrderBook[id] == address(0), "OrderBookFactory: MARKET_EXISTS");

        orderBook = address(
            new OrderBook(
                base,
                quote,
                matcherProxy,
                IPasGovernorMarkets(governor).defaultFeeRecipient(),
                IPasGovernorMarkets(governor).defaultFeeBps()
            )
        );

        OrderBook(orderBook).transferOwnership(governor);

        getOrderBook[id] = orderBook;
        emit MarketCreated(id, base, quote, orderBook);
    }
}
