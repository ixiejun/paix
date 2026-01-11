const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Cross-Chain Interoperability MVP (Escrow + Receiver)", function () {
  it("openIntentERC20 + inbound settle + replay rejected", async function () {
    const [deployer, user] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const token = await TestERC20.deploy("Token", "TKN", ethers.parseUnits("1000000", 18));

    const Escrow = await ethers.getContractFactory("CrossChainEscrow");
    const escrow = await Escrow.deploy();

    const Receiver = await ethers.getContractFactory("CrossChainReceiver");
    const receiver = await Receiver.deploy(escrow.target);

    await escrow.setInbound(receiver.target);

    await token.transfer(user.address, ethers.parseUnits("10", 18));
    await token.connect(user).approve(escrow.target, ethers.parseUnits("3", 18));

    const intentId = ethers.keccak256(ethers.toUtf8Bytes("intent-1"));
    await escrow.connect(user).openIntentERC20(intentId, token.target, ethers.parseUnits("3", 18));

    const it = await escrow.intents(intentId);
    expect(it.user).to.equal(user.address);
    expect(it.token).to.equal(token.target);
    expect(it.amount).to.equal(ethers.parseUnits("3", 18));
    expect(it.state).to.equal(1n); // Pending

    const messageId = ethers.keccak256(ethers.toUtf8Bytes("msg-1"));
    await receiver.handleInbound(messageId, intentId, 2); // Settled

    const it2 = await escrow.intents(intentId);
    expect(it2.state).to.equal(2n);

    await expect(receiver.handleInbound(messageId, intentId, 2)).to.be.revertedWith(
      "CrossChainEscrow: MESSAGE_ALREADY_PROCESSED"
    );
  });

  it("cancelIntent refunds and blocks further state updates", async function () {
    const [deployer, user] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const token = await TestERC20.deploy("Token", "TKN", ethers.parseUnits("1000000", 18));

    const Escrow = await ethers.getContractFactory("CrossChainEscrow");
    const escrow = await Escrow.deploy();

    const Receiver = await ethers.getContractFactory("CrossChainReceiver");
    const receiver = await Receiver.deploy(escrow.target);
    await escrow.setInbound(receiver.target);

    await token.transfer(user.address, ethers.parseUnits("10", 18));
    await token.connect(user).approve(escrow.target, ethers.parseUnits("4", 18));

    const intentId = ethers.keccak256(ethers.toUtf8Bytes("intent-2"));
    await escrow.connect(user).openIntentERC20(intentId, token.target, ethers.parseUnits("4", 18));

    const balBefore = await token.balanceOf(user.address);
    await escrow.connect(user).cancelIntent(intentId);
    const balAfter = await token.balanceOf(user.address);
    expect(balAfter).to.be.gt(balBefore);

    const it = await escrow.intents(intentId);
    expect(it.state).to.equal(4n); // Cancelled

    const messageId = ethers.keccak256(ethers.toUtf8Bytes("msg-2"));
    await receiver.handleInbound(messageId, intentId, 2); // Settled ignored

    const it2 = await escrow.intents(intentId);
    expect(it2.state).to.equal(4n);
  });
});
