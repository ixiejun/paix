const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Hyperliquid Aggregator Contract MVP", function () {
  async function signExecutionReport({ signer, aggregator, report }) {
    const network = await ethers.provider.getNetwork();
    const chainId = Number(network.chainId);

    const domain = {
      name: "HyperliquidAggregator",
      version: "1",
      chainId,
      verifyingContract: aggregator.target,
    };

    const types = {
      ExecutionReport: [
        { name: "reportId", type: "bytes32" },
        { name: "user", type: "address" },
        { name: "tokenIn", type: "address" },
        { name: "tokenOut", type: "address" },
        { name: "amountIn", type: "uint256" },
        { name: "amountOut", type: "uint256" },
        { name: "deadline", type: "uint256" },
      ],
    };

    return signer.signTypedData(domain, types, report);
  }

  it("deposit/withdraw happy path", async function () {
    const [deployer, user] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const token = await TestERC20.deploy("Token", "TKN", ethers.parseUnits("1000000", 18));

    const HyperliquidAggregator = await ethers.getContractFactory("HyperliquidAggregator");
    const agg = await HyperliquidAggregator.deploy();

    await token.transfer(user.address, ethers.parseUnits("100", 18));
    await token.connect(user).approve(agg.target, ethers.parseUnits("10", 18));

    await agg.connect(user).deposit(token.target, ethers.parseUnits("10", 18));
    expect(await agg.escrow(user.address, token.target)).to.equal(ethers.parseUnits("10", 18));

    await agg.connect(user).withdraw(token.target, ethers.parseUnits("4", 18));
    expect(await agg.escrow(user.address, token.target)).to.equal(ethers.parseUnits("6", 18));
  });

  it("valid report -> settlement", async function () {
    const [deployer, user, attestor] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const tokenIn = await TestERC20.deploy("TokenIn", "TIN", ethers.parseUnits("1000000", 18));
    const tokenOut = await TestERC20.deploy("TokenOut", "TOUT", ethers.parseUnits("1000000", 18));

    const HyperliquidAggregator = await ethers.getContractFactory("HyperliquidAggregator");
    const agg = await HyperliquidAggregator.deploy();

    await agg.setAttestorAllowed(attestor.address, true);

    await tokenIn.transfer(user.address, ethers.parseUnits("100", 18));
    await tokenIn.connect(user).approve(agg.target, ethers.parseUnits("10", 18));
    await agg.connect(user).deposit(tokenIn.target, ethers.parseUnits("10", 18));

    const report = {
      reportId: ethers.keccak256(ethers.toUtf8Bytes("report-1")),
      user: user.address,
      tokenIn: tokenIn.target,
      tokenOut: tokenOut.target,
      amountIn: ethers.parseUnits("3", 18),
      amountOut: ethers.parseUnits("5", 18),
      deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
    };

    const sig = await signExecutionReport({ signer: attestor, aggregator: agg, report });

    await agg.submitExecutionReport(report, sig);

    expect(await agg.escrow(user.address, tokenIn.target)).to.equal(ethers.parseUnits("7", 18));
    expect(await agg.escrow(user.address, tokenOut.target)).to.equal(ethers.parseUnits("5", 18));

    // For withdraw to work, the contract needs to actually have tokenOut balance.
    await tokenOut.mint(agg.target, ethers.parseUnits("5", 18));
    await agg.connect(user).withdraw(tokenOut.target, ethers.parseUnits("5", 18));
  });

  it("invalid report rejected", async function () {
    const [deployer, user, attestor, other] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const tokenIn = await TestERC20.deploy("TokenIn", "TIN", ethers.parseUnits("1000000", 18));
    const tokenOut = await TestERC20.deploy("TokenOut", "TOUT", ethers.parseUnits("1000000", 18));

    const HyperliquidAggregator = await ethers.getContractFactory("HyperliquidAggregator");
    const agg = await HyperliquidAggregator.deploy();

    await agg.setAttestorAllowed(attestor.address, true);

    const report = {
      reportId: ethers.keccak256(ethers.toUtf8Bytes("report-2")),
      user: user.address,
      tokenIn: tokenIn.target,
      tokenOut: tokenOut.target,
      amountIn: ethers.parseUnits("1", 18),
      amountOut: ethers.parseUnits("2", 18),
      deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
    };

    const sig = await signExecutionReport({ signer: other, aggregator: agg, report });

    await expect(agg.submitExecutionReport(report, sig)).to.be.revertedWith(
      "HyperliquidAggregator: ATTESTOR_NOT_ALLOWED"
    );
  });

  it("replay rejected", async function () {
    const [deployer, user, attestor] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const tokenIn = await TestERC20.deploy("TokenIn", "TIN", ethers.parseUnits("1000000", 18));
    const tokenOut = await TestERC20.deploy("TokenOut", "TOUT", ethers.parseUnits("1000000", 18));

    const HyperliquidAggregator = await ethers.getContractFactory("HyperliquidAggregator");
    const agg = await HyperliquidAggregator.deploy();

    await agg.setAttestorAllowed(attestor.address, true);

    await tokenIn.transfer(user.address, ethers.parseUnits("10", 18));
    await tokenIn.connect(user).approve(agg.target, ethers.parseUnits("2", 18));
    await agg.connect(user).deposit(tokenIn.target, ethers.parseUnits("2", 18));

    const report = {
      reportId: ethers.keccak256(ethers.toUtf8Bytes("report-3")),
      user: user.address,
      tokenIn: tokenIn.target,
      tokenOut: tokenOut.target,
      amountIn: ethers.parseUnits("2", 18),
      amountOut: ethers.parseUnits("1", 18),
      deadline: BigInt(Math.floor(Date.now() / 1000) + 3600),
    };

    const sig = await signExecutionReport({ signer: attestor, aggregator: agg, report });

    await agg.submitExecutionReport(report, sig);

    await expect(agg.submitExecutionReport(report, sig)).to.be.revertedWith(
      "HyperliquidAggregator: REPORT_ALREADY_PROCESSED"
    );
  });
});
