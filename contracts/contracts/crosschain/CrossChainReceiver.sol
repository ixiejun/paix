pragma solidity =0.8.20;

import "./CrossChainEscrow.sol";

contract CrossChainReceiver {
    address public owner;
    CrossChainEscrow public escrow;

    event OwnershipTransferred(address indexed oldOwner, address indexed newOwner);
    event EscrowUpdated(address indexed escrow);
    event InboundMessageHandled(bytes32 indexed messageId, bytes32 indexed intentId, CrossChainEscrow.IntentState state);

    modifier onlyOwner() {
        require(msg.sender == owner, "CrossChainReceiver: NOT_OWNER");
        _;
    }

    constructor(address escrowAddress) {
        owner = msg.sender;
        emit OwnershipTransferred(address(0), owner);
        escrow = CrossChainEscrow(escrowAddress);
        emit EscrowUpdated(escrowAddress);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "CrossChainReceiver: ZERO_OWNER");
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    function setEscrow(address escrowAddress) external onlyOwner {
        escrow = CrossChainEscrow(escrowAddress);
        emit EscrowUpdated(escrowAddress);
    }

    function handleInbound(bytes32 messageId, bytes32 intentId, CrossChainEscrow.IntentState newState) external {
        escrow.applyInbound(messageId, intentId, newState);
        emit InboundMessageHandled(messageId, intentId, newState);
    }
}
