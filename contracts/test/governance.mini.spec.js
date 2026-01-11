const { expect } = require("chai");
const { ethers, network } = require("hardhat");

async function mineBlocks(n) {
  for (let i = 0; i < n; i++) {
    await network.provider.send("evm_mine");
  }
}

describe("Governance MVP (PAS on-chain voting, CLOB-only)", function () {
  it("propose -> vote -> execute: list market, create market gated, update params, allow matcher op", async function () {
    const [deployer, alice, bob, operator] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy("Base", "BASE", ethers.parseUnits("1000000", 18));
    const quote = await TestERC20.deploy("Quote", "QUOTE", ethers.parseUnits("1000000", 18));

    const votingPeriodBlocks = 5;
    const executionDelayBlocks = 0;
    const quorumBps = 0;
    const proposalThreshold = ethers.parseEther("1");
    const defaultFeeBps = 50;

    const PasGovernor = await ethers.getContractFactory("PasGovernor");
    const gov = await PasGovernor.deploy(
      votingPeriodBlocks,
      executionDelayBlocks,
      quorumBps,
      proposalThreshold,
      defaultFeeBps,
      deployer.address
    );

    const ClobMatcherProxy = await ethers.getContractFactory("ClobMatcherProxy");
    const matcherProxy = await ClobMatcherProxy.deploy(gov.target);

    const OrderBookFactory = await ethers.getContractFactory("OrderBookFactory");
    const factory = await OrderBookFactory.deploy(gov.target, matcherProxy.target);

    // stake voting power (native PAS on testnet; ETH on hardhat)
    await gov.connect(alice).stake({ value: ethers.parseEther("2") });
    await gov.connect(bob).stake({ value: ethers.parseEther("1") });

    const listData = gov.interface.encodeFunctionData("listMarket", [base.target, quote.target]);
    const actions = [{ target: gov.target, value: 0, data: listData }];

    const tx = await gov.connect(alice).propose(actions);
    const rc = await tx.wait();
    const proposalId = rc.logs.find((l) => l.fragment && l.fragment.name === "ProposalCreated").args.proposalId;

    // move into voting
    await mineBlocks(1);

    await gov.connect(alice).vote(proposalId, true);
    await gov.connect(bob).vote(proposalId, true);

    // finish voting
    await mineBlocks(votingPeriodBlocks + 1);

    await gov.execute(proposalId);

    const mid = await gov.marketId(base.target, quote.target);
    expect(await gov.marketListed(mid)).to.equal(true);

    // can now create market
    const createTx = await factory.createMarket(base.target, quote.target);
    const createRc = await createTx.wait();
    const created = createRc.logs.find((l) => l.fragment && l.fragment.name === "MarketCreated").args.orderBook;

    const OrderBook = await ethers.getContractFactory("OrderBook");
    const ob = OrderBook.attach(created);

    expect(await ob.owner()).to.equal(gov.target);

    // update matcher operator via governance
    const opData = gov.interface.encodeFunctionData("setMatcherOperator", [operator.address, true]);
    const p2tx = await gov.connect(alice).propose([{ target: gov.target, value: 0, data: opData }]);
    const p2rc = await p2tx.wait();
    const p2 = p2rc.logs.find((l) => l.fragment && l.fragment.name === "ProposalCreated").args.proposalId;

    await mineBlocks(1);
    await gov.connect(alice).vote(p2, true);
    await mineBlocks(votingPeriodBlocks + 1);
    await gov.execute(p2);

    expect(await gov.matcherOperators(operator.address)).to.equal(true);

    // simple trade matched through proxy (orderbook matcher is proxy contract)
    await base.transfer(alice.address, ethers.parseUnits("100", 18));
    await quote.transfer(alice.address, ethers.parseUnits("1000", 18));

    await base.transfer(bob.address, ethers.parseUnits("100", 18));
    await quote.transfer(bob.address, ethers.parseUnits("1000", 18));

    await quote.connect(alice).approve(ob.target, ethers.parseUnits("100", 18));
    await ob.connect(alice).deposit(quote.target, ethers.parseUnits("100", 18));

    await base.connect(bob).approve(ob.target, ethers.parseUnits("10", 18));
    await ob.connect(bob).deposit(base.target, ethers.parseUnits("10", 18));

    const buyPrice = ethers.parseUnits("2", 18);
    const sellPrice = ethers.parseUnits("1.5", 18);
    const baseAmount = ethers.parseUnits("10", 18);

    const btx = await ob.connect(alice).placeBuy(buyPrice, baseAmount);
    const brc = await btx.wait();
    const buyOrderId = brc.logs.find((l) => l.fragment && l.fragment.name === "OrderPlaced").args.orderId;

    const stx = await ob.connect(bob).placeSell(sellPrice, baseAmount);
    const src = await stx.wait();
    const sellOrderId = src.logs.find((l) => l.fragment && l.fragment.name === "OrderPlaced").args.orderId;

    // operator calls proxy, proxy calls orderbook.matchOrders
    await matcherProxy.connect(operator).matchOrders(ob.target, buyOrderId, sellOrderId, baseAmount, sellPrice);

    expect(await ob.available(alice.address, base.target)).to.equal(baseAmount);

    // update fee on the orderbook via governance
    const feeData = ob.interface.encodeFunctionData("setFeeBps", [100]);
    const p3tx = await gov.connect(alice).propose([{ target: ob.target, value: 0, data: feeData }]);
    const p3rc = await p3tx.wait();
    const p3 = p3rc.logs.find((l) => l.fragment && l.fragment.name === "ProposalCreated").args.proposalId;

    await mineBlocks(1);
    await gov.connect(alice).vote(p3, true);
    await mineBlocks(votingPeriodBlocks + 1);
    await gov.execute(p3);

    expect(await ob.feeBps()).to.equal(100);
  });
});
