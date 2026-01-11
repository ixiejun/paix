const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Gas Sponsor / AA MVP", function () {
  async function signMetaTx({ signer, forwarder, to, value, data, deadline }) {
    const network = await ethers.provider.getNetwork();
    const chainId = Number(network.chainId);

    const nonce = await forwarder.nonces(signer.address);

    const domain = {
      name: "GasSponsorForwarder",
      version: "1",
      chainId,
      verifyingContract: forwarder.target,
    };

    const types = {
      MetaTx: [
        { name: "from", type: "address" },
        { name: "to", type: "address" },
        { name: "value", type: "uint256" },
        { name: "dataHash", type: "bytes32" },
        { name: "nonce", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    };

    const message = {
      from: signer.address,
      to,
      value,
      dataHash: ethers.keccak256(data),
      nonce,
      deadline,
    };

    return signer.signTypedData(domain, types, message);
  }

  it("executes meta-tx deposit and credits escrow to original user", async function () {
    const [deployer, user, relayer] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy("Base", "BASE", ethers.parseUnits("1000000", 18));
    const quote = await TestERC20.deploy("Quote", "QUOTE", ethers.parseUnits("1000000", 18));

    const GasSponsorForwarder = await ethers.getContractFactory("GasSponsorForwarder");
    const forwarder = await GasSponsorForwarder.deploy();

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const ob = await OrderBook.deploy(base.target, quote.target, deployer.address, deployer.address, 0);

    await ob.setTrustedForwarder(forwarder.target);

    // fund + approve
    await base.transfer(user.address, ethers.parseUnits("100", 18));
    await base.connect(user).approve(ob.target, ethers.parseUnits("10", 18));

    const amount = ethers.parseUnits("10", 18);
    const data = ob.interface.encodeFunctionData("deposit", [base.target, amount]);
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    const sig = await signMetaTx({ signer: user, forwarder, to: ob.target, value: 0n, data, deadline });

    await forwarder.connect(relayer).executeMetaTx(
      { from: user.address, to: ob.target, value: 0, data, deadline },
      sig
    );

    expect(await ob.available(user.address, base.target)).to.equal(amount);
    expect(await ob.available(relayer.address, base.target)).to.equal(0);
  });

  it("rejects replay via nonce mismatch", async function () {
    const [deployer, user, relayer] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy("Base", "BASE", ethers.parseUnits("1000000", 18));
    const quote = await TestERC20.deploy("Quote", "QUOTE", ethers.parseUnits("1000000", 18));

    const GasSponsorForwarder = await ethers.getContractFactory("GasSponsorForwarder");
    const forwarder = await GasSponsorForwarder.deploy();

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const ob = await OrderBook.deploy(base.target, quote.target, deployer.address, deployer.address, 0);

    await ob.setTrustedForwarder(forwarder.target);

    await base.transfer(user.address, ethers.parseUnits("100", 18));
    await base.connect(user).approve(ob.target, ethers.parseUnits("10", 18));

    const amount = ethers.parseUnits("10", 18);
    const data = ob.interface.encodeFunctionData("deposit", [base.target, amount]);
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    const sig = await signMetaTx({ signer: user, forwarder, to: ob.target, value: 0n, data, deadline });

    await forwarder.connect(relayer).executeMetaTx(
      { from: user.address, to: ob.target, value: 0, data, deadline },
      sig
    );

    await expect(
      forwarder.connect(relayer).executeMetaTx(
        { from: user.address, to: ob.target, value: 0, data, deadline },
        sig
      )
    ).to.be.revertedWith("GasSponsorForwarder: BAD_SIG");
  });

  it("rejects expired meta-tx", async function () {
    const [deployer, user, relayer] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy("Base", "BASE", ethers.parseUnits("1000000", 18));
    const quote = await TestERC20.deploy("Quote", "QUOTE", ethers.parseUnits("1000000", 18));

    const GasSponsorForwarder = await ethers.getContractFactory("GasSponsorForwarder");
    const forwarder = await GasSponsorForwarder.deploy();

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const ob = await OrderBook.deploy(base.target, quote.target, deployer.address, deployer.address, 0);

    await ob.setTrustedForwarder(forwarder.target);

    const amount = ethers.parseUnits("10", 18);
    const data = ob.interface.encodeFunctionData("deposit", [base.target, amount]);
    const deadline = 1n;

    const sig = await signMetaTx({ signer: user, forwarder, to: ob.target, value: 0n, data, deadline });

    await expect(
      forwarder.connect(relayer).executeMetaTx(
        { from: user.address, to: ob.target, value: 0, data, deadline },
        sig
      )
    ).to.be.revertedWith("GasSponsorForwarder: EXPIRED");
  });

  it("rejects invalid signature", async function () {
    const [deployer, user, other, relayer] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy("Base", "BASE", ethers.parseUnits("1000000", 18));
    const quote = await TestERC20.deploy("Quote", "QUOTE", ethers.parseUnits("1000000", 18));

    const GasSponsorForwarder = await ethers.getContractFactory("GasSponsorForwarder");
    const forwarder = await GasSponsorForwarder.deploy();

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const ob = await OrderBook.deploy(base.target, quote.target, deployer.address, deployer.address, 0);

    await ob.setTrustedForwarder(forwarder.target);

    const amount = ethers.parseUnits("10", 18);
    const data = ob.interface.encodeFunctionData("deposit", [base.target, amount]);
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    // sign with 'other' but claim signer is 'user'
    const sig = await signMetaTx({ signer: other, forwarder, to: ob.target, value: 0n, data, deadline });

    await expect(
      forwarder.connect(relayer).executeMetaTx(
        { from: user.address, to: ob.target, value: 0, data, deadline },
        sig
      )
    ).to.be.revertedWith("GasSponsorForwarder: BAD_SIG");
  });

  it("enforces relayer allowlist when enabled", async function () {
    const [deployer, user, relayer, allowedRelayer] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy("Base", "BASE", ethers.parseUnits("1000000", 18));
    const quote = await TestERC20.deploy("Quote", "QUOTE", ethers.parseUnits("1000000", 18));

    const GasSponsorForwarder = await ethers.getContractFactory("GasSponsorForwarder");
    const forwarder = await GasSponsorForwarder.deploy();

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const ob = await OrderBook.deploy(base.target, quote.target, deployer.address, deployer.address, 0);

    await ob.setTrustedForwarder(forwarder.target);

    await forwarder.setRequireRelayerAllowed(true);
    await forwarder.setRelayerAllowed(allowedRelayer.address, true);

    await base.transfer(user.address, ethers.parseUnits("100", 18));
    await base.connect(user).approve(ob.target, ethers.parseUnits("10", 18));

    const amount = ethers.parseUnits("10", 18);
    const data = ob.interface.encodeFunctionData("deposit", [base.target, amount]);
    const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

    const sig = await signMetaTx({ signer: user, forwarder, to: ob.target, value: 0n, data, deadline });

    await expect(
      forwarder.connect(relayer).executeMetaTx(
        { from: user.address, to: ob.target, value: 0, data, deadline },
        sig
      )
    ).to.be.revertedWith("GasSponsorForwarder: RELAYER_NOT_ALLOWED");

    await forwarder.connect(allowedRelayer).executeMetaTx(
      { from: user.address, to: ob.target, value: 0, data, deadline },
      sig
    );
    expect(await ob.available(user.address, base.target)).to.equal(amount);
  });
});
