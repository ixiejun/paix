const hre = require("hardhat");

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function waitForBlock(targetBlock) {
  while (true) {
    const bn = await hre.ethers.provider.getBlockNumber();
    if (bn >= targetBlock) return;
    await sleep(4000);
  }
}

async function main() {
  const signers = await hre.ethers.getSigners();
  const deployer = signers[0];

  console.log("Network:", hre.network.name);
  console.log("Deployer:", deployer.address);

  const votingPeriodBlocks = 10;
  const executionDelayBlocks = 0;
  const quorumBps = 0;
  const proposalThreshold = 0n;
  const defaultFeeBps = 50;

  const PasGovernor = await hre.ethers.getContractFactory("PasGovernor");
  const gov = await PasGovernor.deploy(
    votingPeriodBlocks,
    executionDelayBlocks,
    quorumBps,
    proposalThreshold,
    defaultFeeBps,
    deployer.address
  );
  await gov.waitForDeployment();

  const ClobMatcherProxy = await hre.ethers.getContractFactory("ClobMatcherProxy");
  const matcherProxy = await ClobMatcherProxy.deploy(gov.target);
  await matcherProxy.waitForDeployment();

  const OrderBookFactory = await hre.ethers.getContractFactory("OrderBookFactory");
  const factory = await OrderBookFactory.deploy(gov.target, matcherProxy.target);
  await factory.waitForDeployment();

  console.log("PasGovernor:", gov.target);
  console.log("ClobMatcherProxy:", matcherProxy.target);
  console.log("OrderBookFactory:", factory.target);

  // Deploy sample tokens
  const TestERC20 = await hre.ethers.getContractFactory("TestERC20");
  const base = await TestERC20.deploy("Gov Smoke Base", "GS_BASE", hre.ethers.parseUnits("1000000", 18));
  await base.waitForDeployment();
  const quote = await TestERC20.deploy("Gov Smoke Quote", "GS_QUOTE", hre.ethers.parseUnits("1000000", 18));
  await quote.waitForDeployment();

  console.log("baseToken:", base.target);
  console.log("quoteToken:", quote.target);

  // Stake PAS (native token) to get voting power
  let tx = await gov.stake({ value: hre.ethers.parseEther("0.1") });
  console.log("stake tx:", tx.hash);
  await tx.wait();

  // Propose to list market
  const listData = gov.interface.encodeFunctionData("listMarket", [base.target, quote.target]);
  tx = await gov.propose([{ target: gov.target, value: 0, data: listData }]);
  console.log("propose listMarket tx:", tx.hash);
  const r1 = await tx.wait();
  const proposalId = r1.logs.find((l) => l.fragment && l.fragment.name === "ProposalCreated").args.proposalId;
  console.log("proposalId(listMarket):", proposalId.toString());

  const p = await gov.proposals(proposalId);
  await waitForBlock(Number(p.startBlock));

  tx = await gov.vote(proposalId, true);
  console.log("vote tx:", tx.hash);
  await tx.wait();

  await waitForBlock(Number(p.endBlock) + 1);

  tx = await gov.execute(proposalId);
  console.log("execute tx:", tx.hash);
  await tx.wait();

  const mid = await gov.marketId(base.target, quote.target);
  console.log("marketId:", mid);
  console.log("marketListed:", await gov.marketListed(mid));

  // Create market
  tx = await factory.createMarket(base.target, quote.target);
  console.log("createMarket tx:", tx.hash);
  const r2 = await tx.wait();
  const created = r2.logs.find((l) => l.fragment && l.fragment.name === "MarketCreated").args.orderBook;
  console.log("orderBook:", created);

  // Update fee on the created OrderBook via governance
  const OrderBook = await hre.ethers.getContractFactory("OrderBook");
  const ob = OrderBook.attach(created);

  const feeData = ob.interface.encodeFunctionData("setFeeBps", [100]);
  tx = await gov.propose([{ target: ob.target, value: 0, data: feeData }]);
  console.log("propose setFeeBps tx:", tx.hash);
  const r3 = await tx.wait();
  const p2 = r3.logs.find((l) => l.fragment && l.fragment.name === "ProposalCreated").args.proposalId;
  console.log("proposalId(setFeeBps):", p2.toString());

  const p2s = await gov.proposals(p2);
  await waitForBlock(Number(p2s.startBlock));

  tx = await gov.vote(p2, true);
  console.log("vote2 tx:", tx.hash);
  await tx.wait();

  await waitForBlock(Number(p2s.endBlock) + 1);

  tx = await gov.execute(p2);
  console.log("execute2 tx:", tx.hash);
  await tx.wait();

  console.log("feeBps:", (await ob.feeBps()).toString());

  console.log("Smoke test OK");
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
