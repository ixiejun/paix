pragma solidity =0.8.20;

interface IERC20Minimal {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

library SafeTransfer {
    function safeTransfer(address token, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transfer.selector, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeTransfer: TRANSFER_FAILED");
    }

    function safeTransferFrom(address token, address from, address to, uint256 value) internal {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(IERC20Minimal.transferFrom.selector, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), "SafeTransfer: TRANSFER_FROM_FAILED");
    }
}

contract OrderBook {
    using SafeTransfer for address;

    uint256 public constant PRICE_SCALE = 1e18;

    address public immutable baseToken;
    address public immutable quoteToken;

    address public owner;
    address public matcher;

    address public trustedForwarder;

    uint16 public feeBps;
    address public feeRecipient;

    struct Order {
        address owner;
        bool isBuy;
        uint256 price; // quote per base, scaled by PRICE_SCALE
        uint256 amount; // base amount
        uint256 filled; // base filled
        uint256 lockedAmount; // remaining locked amount (quote for buy, base for sell)
        bool cancelled;
    }

    uint256 public nextOrderId;
    mapping(uint256 => Order) public orders;

    mapping(address => mapping(address => uint256)) public available;
    mapping(address => mapping(address => uint256)) public locked;

    event Deposit(address indexed user, address indexed token, uint256 amount);
    event Withdraw(address indexed user, address indexed token, uint256 amount);

    event OrderPlaced(
        uint256 indexed orderId,
        address indexed user,
        bool isBuy,
        uint256 price,
        uint256 amount,
        uint256 lockedAmount
    );

    event OrderCancelled(uint256 indexed orderId, address indexed user, uint256 remainingAmount, uint256 unlockedAmount);

    event Trade(
        uint256 indexed buyOrderId,
        uint256 indexed sellOrderId,
        address indexed matcher,
        address buyer,
        address seller,
        uint256 price,
        uint256 baseAmount,
        uint256 quoteAmount,
        uint256 feeAmount
    );

    event MatcherUpdated(address indexed oldMatcher, address indexed newMatcher);
    event FeeRecipientUpdated(address indexed oldRecipient, address indexed newRecipient);
    event FeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);
    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event TrustedForwarderUpdated(address indexed oldForwarder, address indexed newForwarder);

    modifier onlyOwner() {
        require(msg.sender == owner, "OrderBook: NOT_OWNER");
        _;
    }

    modifier onlyMatcher() {
        require(msg.sender == matcher, "OrderBook: NOT_MATCHER");
        _;
    }

    constructor(address _baseToken, address _quoteToken, address _matcher, address _feeRecipient, uint16 _feeBps) {
        require(_baseToken != address(0) && _quoteToken != address(0), "OrderBook: ZERO_TOKEN");
        require(_baseToken != _quoteToken, "OrderBook: IDENTICAL_TOKEN");
        require(_feeBps <= 10_000, "OrderBook: FEE_TOO_HIGH");

        baseToken = _baseToken;
        quoteToken = _quoteToken;

        owner = msg.sender;
        matcher = _matcher;
        feeRecipient = _feeRecipient;
        feeBps = _feeBps;

        nextOrderId = 1;

        emit OwnershipTransferred(address(0), owner);
        emit MatcherUpdated(address(0), matcher);
        emit FeeRecipientUpdated(address(0), feeRecipient);
        emit FeeUpdated(0, feeBps);
    }

    function setTrustedForwarder(address newForwarder) external onlyOwner {
        emit TrustedForwarderUpdated(trustedForwarder, newForwarder);
        trustedForwarder = newForwarder;
    }

    function isTrustedForwarder(address forwarder) public view returns (bool) {
        return forwarder != address(0) && forwarder == trustedForwarder;
    }

    function _msgSender() internal view returns (address sender) {
        if (isTrustedForwarder(msg.sender)) {
            assembly {
                sender := shr(96, calldataload(sub(calldatasize(), 20)))
            }
        } else {
            sender = msg.sender;
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "OrderBook: ZERO_OWNER");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setMatcher(address newMatcher) external onlyOwner {
        emit MatcherUpdated(matcher, newMatcher);
        matcher = newMatcher;
    }

    function setFeeRecipient(address newRecipient) external onlyOwner {
        emit FeeRecipientUpdated(feeRecipient, newRecipient);
        feeRecipient = newRecipient;
    }

    function setFeeBps(uint16 newFeeBps) external onlyOwner {
        require(newFeeBps <= 10_000, "OrderBook: FEE_TOO_HIGH");
        emit FeeUpdated(feeBps, newFeeBps);
        feeBps = newFeeBps;
    }

    function deposit(address token, uint256 amount) external {
        require(token == baseToken || token == quoteToken, "OrderBook: UNSUPPORTED_TOKEN");
        require(amount > 0, "OrderBook: ZERO_AMOUNT");

        address sender = _msgSender();
        token.safeTransferFrom(sender, address(this), amount);
        available[sender][token] += amount;
        emit Deposit(sender, token, amount);
    }

    function withdraw(address token, uint256 amount) external {
        require(token == baseToken || token == quoteToken, "OrderBook: UNSUPPORTED_TOKEN");
        require(amount > 0, "OrderBook: ZERO_AMOUNT");

        address sender = _msgSender();

        uint256 bal = available[sender][token];
        require(bal >= amount, "OrderBook: INSUFFICIENT_AVAILABLE");

        unchecked {
            available[sender][token] = bal - amount;
        }
        token.safeTransfer(sender, amount);
        emit Withdraw(sender, token, amount);
    }

    function placeBuy(uint256 price, uint256 baseAmount) external returns (uint256 orderId) {
        return _placeOrder(_msgSender(), true, price, baseAmount);
    }

    function placeSell(uint256 price, uint256 baseAmount) external returns (uint256 orderId) {
        return _placeOrder(_msgSender(), false, price, baseAmount);
    }

    function cancel(uint256 orderId) external {
        Order storage o = orders[orderId];
        require(o.owner != address(0), "OrderBook: ORDER_NOT_FOUND");

        address sender = _msgSender();
        require(sender == o.owner, "OrderBook: NOT_ORDER_OWNER");
        require(!o.cancelled, "OrderBook: ORDER_CANCELLED");

        uint256 remainingBase = o.amount - o.filled;
        require(remainingBase > 0, "OrderBook: ORDER_FILLED");

        o.cancelled = true;

        if (o.isBuy) {
            uint256 unlockQuote = o.lockedAmount;
            if (unlockQuote > 0) {
                _unlock(o.owner, quoteToken, unlockQuote);
                o.lockedAmount = 0;
            }
            emit OrderCancelled(orderId, o.owner, remainingBase, unlockQuote);
        } else {
            uint256 unlockBase = o.lockedAmount;
            if (unlockBase > 0) {
                _unlock(o.owner, baseToken, unlockBase);
                o.lockedAmount = 0;
            }
            emit OrderCancelled(orderId, o.owner, remainingBase, unlockBase);
        }
    }

    function matchOrders(uint256 buyOrderId, uint256 sellOrderId, uint256 maxBaseFill, uint256 executionPrice) external onlyMatcher {
        require(maxBaseFill > 0, "OrderBook: ZERO_FILL");
        require(executionPrice > 0, "OrderBook: ZERO_PRICE");

        Order storage buy = orders[buyOrderId];
        Order storage sell = orders[sellOrderId];

        require(buy.owner != address(0) && sell.owner != address(0), "OrderBook: ORDER_NOT_FOUND");
        require(buy.isBuy && !sell.isBuy, "OrderBook: SIDE_MISMATCH");
        require(!buy.cancelled && !sell.cancelled, "OrderBook: ORDER_CANCELLED");

        uint256 buyRemaining = buy.amount - buy.filled;
        uint256 sellRemaining = sell.amount - sell.filled;
        require(buyRemaining > 0 && sellRemaining > 0, "OrderBook: ORDER_FILLED");

        require(buy.price >= executionPrice, "OrderBook: BUY_PRICE_TOO_LOW");
        require(sell.price <= executionPrice, "OrderBook: SELL_PRICE_TOO_HIGH");

        uint256 fillBase = _min(_min(buyRemaining, sellRemaining), maxBaseFill);
        uint256 quoteAmount = _mulDivDown(fillBase, executionPrice, PRICE_SCALE);

        uint256 feeAmount = 0;
        if (feeBps > 0 && feeRecipient != address(0)) {
            feeAmount = (quoteAmount * uint256(feeBps)) / 10_000;
        }

        // buyer pays quote + fee from this order's locked quote
        uint256 buyerPay = quoteAmount + feeAmount;
        require(buy.lockedAmount >= buyerPay, "OrderBook: BUY_INSUFFICIENT_LOCKED");
        buy.lockedAmount -= buyerPay;
        _consumeLocked(buy.owner, quoteToken, buyerPay);

        // seller pays base from this order's locked base
        require(sell.lockedAmount >= fillBase, "OrderBook: SELL_INSUFFICIENT_LOCKED");
        sell.lockedAmount -= fillBase;
        _consumeLocked(sell.owner, baseToken, fillBase);

        // settlement
        available[buy.owner][baseToken] += fillBase;
        available[sell.owner][quoteToken] += quoteAmount;
        if (feeAmount > 0) {
            available[feeRecipient][quoteToken] += feeAmount;
        }

        buy.filled += fillBase;
        sell.filled += fillBase;

        // unlock per-order leftovers if fully filled
        if (buy.filled == buy.amount && buy.lockedAmount > 0) {
            uint256 refundQuote = buy.lockedAmount;
            buy.lockedAmount = 0;
            _unlock(buy.owner, quoteToken, refundQuote);
        }

        if (sell.filled == sell.amount && sell.lockedAmount > 0) {
            uint256 refundBase = sell.lockedAmount;
            sell.lockedAmount = 0;
            _unlock(sell.owner, baseToken, refundBase);
        }

        emit Trade(
            buyOrderId,
            sellOrderId,
            msg.sender,
            buy.owner,
            sell.owner,
            executionPrice,
            fillBase,
            quoteAmount,
            feeAmount
        );
    }

    function _placeOrder(address sender, bool isBuy, uint256 price, uint256 baseAmount) internal returns (uint256 orderId) {
        require(price > 0, "OrderBook: ZERO_PRICE");
        require(baseAmount > 0, "OrderBook: ZERO_AMOUNT");

        orderId = nextOrderId++;

        Order storage o = orders[orderId];
        o.owner = sender;
        o.isBuy = isBuy;
        o.price = price;
        o.amount = baseAmount;

        uint256 lockedAmount;
        if (isBuy) {
            lockedAmount = _mulDivDown(baseAmount, price, PRICE_SCALE);
            _lock(sender, quoteToken, lockedAmount);
        } else {
            lockedAmount = baseAmount;
            _lock(sender, baseToken, lockedAmount);
        }

        o.lockedAmount = lockedAmount;

        emit OrderPlaced(orderId, sender, isBuy, price, baseAmount, lockedAmount);
    }

    function _lock(address user, address token, uint256 amount) internal {
        require(amount > 0, "OrderBook: ZERO_LOCK");
        uint256 bal = available[user][token];
        require(bal >= amount, "OrderBook: INSUFFICIENT_AVAILABLE");
        unchecked {
            available[user][token] = bal - amount;
        }
        locked[user][token] += amount;
    }

    function _unlock(address user, address token, uint256 amount) internal {
        require(amount > 0, "OrderBook: ZERO_UNLOCK");
        uint256 bal = locked[user][token];
        require(bal >= amount, "OrderBook: INSUFFICIENT_LOCKED");
        unchecked {
            locked[user][token] = bal - amount;
        }
        available[user][token] += amount;
    }

    function _consumeLocked(address user, address token, uint256 amount) internal {
        require(amount > 0, "OrderBook: ZERO_CONSUME");
        uint256 bal = locked[user][token];
        require(bal >= amount, "OrderBook: INSUFFICIENT_LOCKED");
        unchecked {
            locked[user][token] = bal - amount;
        }
    }

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _mulDivDown(uint256 a, uint256 b, uint256 denom) internal pure returns (uint256) {
        require(denom != 0, "OrderBook: DIV_BY_ZERO");
        // Prevent overflow in a*b
        require(a == 0 || b <= type(uint256).max / a, "OrderBook: MUL_OVERFLOW");
        return (a * b) / denom;
    }
}
