pragma solidity =0.8.20;

interface IPasGovernorMatcher {
    function matcherOperators(address operator) external view returns (bool);
}

interface IOrderBookMatch {
    function matchOrders(uint256 buyOrderId, uint256 sellOrderId, uint256 maxBaseFill, uint256 executionPrice) external;
}

contract ClobMatcherProxy {
    address public immutable governor;

    constructor(address _governor) {
        require(_governor != address(0), "ClobMatcherProxy: ZERO_GOVERNOR");
        governor = _governor;
    }

    function matchOrders(address orderBook, uint256 buyOrderId, uint256 sellOrderId, uint256 maxBaseFill, uint256 executionPrice) external {
        require(IPasGovernorMatcher(governor).matcherOperators(msg.sender), "ClobMatcherProxy: NOT_OPERATOR");
        IOrderBookMatch(orderBook).matchOrders(buyOrderId, sellOrderId, maxBaseFill, executionPrice);
    }
}
