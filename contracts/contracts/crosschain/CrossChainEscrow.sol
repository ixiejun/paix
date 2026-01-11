pragma solidity =0.8.20;

import "../interfaces/IERC20.sol";

contract CrossChainEscrow {
    enum IntentState {
        None,
        Pending,
        Settled,
        Failed,
        Cancelled,
        Refunded
    }

    address public owner;
    address public inbound;

    struct Intent {
        address user;
        address token;
        uint256 amount;
        IntentState state;
    }

    mapping(bytes32 => Intent) public intents;
    mapping(bytes32 => bool) public processedMessage;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event InboundUpdated(address indexed inbound);

    event IntentOpened(bytes32 indexed intentId, address indexed user, address indexed token, uint256 amount);
    event IntentStateUpdated(bytes32 indexed intentId, IntentState oldState, IntentState newState, bytes32 indexed messageId);
    event Refunded(bytes32 indexed intentId, address indexed user, address indexed token, uint256 amount);

    modifier onlyOwner() {
        require(msg.sender == owner, "CrossChainEscrow: NOT_OWNER");
        _;
    }

    modifier onlyInbound() {
        require(msg.sender == inbound, "CrossChainEscrow: NOT_INBOUND");
        _;
    }

    constructor() {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CrossChainEscrow: ZERO_OWNER");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setInbound(address newInbound) external onlyOwner {
        inbound = newInbound;
        emit InboundUpdated(newInbound);
    }

    function openIntentERC20(bytes32 intentId, address token, uint256 amount) external {
        require(intentId != bytes32(0), "CrossChainEscrow: ZERO_INTENT");
        require(token != address(0), "CrossChainEscrow: ZERO_TOKEN");
        require(amount > 0, "CrossChainEscrow: ZERO_AMOUNT");

        Intent storage it = intents[intentId];
        require(it.state == IntentState.None, "CrossChainEscrow: INTENT_EXISTS");

        require(IERC20(token).transferFrom(msg.sender, address(this), amount), "CrossChainEscrow: TRANSFER_FROM_FAILED");

        intents[intentId] = Intent({user: msg.sender, token: token, amount: amount, state: IntentState.Pending});
        emit IntentOpened(intentId, msg.sender, token, amount);
    }

    function cancelIntent(bytes32 intentId) external {
        Intent storage it = intents[intentId];
        require(it.state == IntentState.Pending, "CrossChainEscrow: NOT_PENDING");
        require(msg.sender == it.user, "CrossChainEscrow: NOT_USER");

        IntentState oldState = it.state;
        it.state = IntentState.Cancelled;
        emit IntentStateUpdated(intentId, oldState, it.state, bytes32(0));

        require(IERC20(it.token).transfer(it.user, it.amount), "CrossChainEscrow: REFUND_TRANSFER_FAILED");
        emit Refunded(intentId, it.user, it.token, it.amount);
    }

    function refundFailedIntent(bytes32 intentId) external {
        Intent storage it = intents[intentId];
        require(it.state == IntentState.Failed, "CrossChainEscrow: NOT_FAILED");
        require(msg.sender == it.user, "CrossChainEscrow: NOT_USER");

        IntentState oldState = it.state;
        it.state = IntentState.Refunded;
        emit IntentStateUpdated(intentId, oldState, it.state, bytes32(0));

        require(IERC20(it.token).transfer(it.user, it.amount), "CrossChainEscrow: REFUND_TRANSFER_FAILED");
        emit Refunded(intentId, it.user, it.token, it.amount);
    }

    function applyInbound(bytes32 messageId, bytes32 intentId, IntentState newState) external onlyInbound {
        require(messageId != bytes32(0), "CrossChainEscrow: ZERO_MESSAGE");
        require(!processedMessage[messageId], "CrossChainEscrow: MESSAGE_ALREADY_PROCESSED");
        processedMessage[messageId] = true;

        Intent storage it = intents[intentId];
        require(it.state != IntentState.None, "CrossChainEscrow: INTENT_NOT_FOUND");

        IntentState oldState = it.state;

        if (oldState == IntentState.Settled || oldState == IntentState.Cancelled || oldState == IntentState.Refunded) {
            emit IntentStateUpdated(intentId, oldState, oldState, messageId);
            return;
        }

        if (newState == IntentState.Settled || newState == IntentState.Failed) {
            it.state = newState;
        }

        emit IntentStateUpdated(intentId, oldState, it.state, messageId);
    }
}
