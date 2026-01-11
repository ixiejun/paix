const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deployer:", deployer.address);
  console.log("Network:", hre.network.name);

  const votingPeriodBlocks = process.env.GOV_VOTING_PERIOD_BLOCKS
    ? Number(process.env.GOV_VOTING_PERIOD_BLOCKS)
    : 20;
  const executionDelayBlocks = process.env.GOV_EXECUTION_DELAY_BLOCKS
    ? Number(process.env.GOV_EXECUTION_DELAY_BLOCKS)
    : 0;
  const quorumBps = process.env.GOV_QUORUM_BPS ? Number(process.env.GOV_QUORUM_BPS) : 0;
  const proposalThreshold = process.env.GOV_PROPOSAL_THRESHOLD_WEI
    ? BigInt(process.env.GOV_PROPOSAL_THRESHOLD_WEI)
    : 0n;

  const defaultFeeBps = process.env.GOV_DEFAULT_FEE_BPS ? Number(process.env.GOV_DEFAULT_FEE_BPS) : 50;
  const defaultFeeRecipient = process.env.GOV_DEFAULT_FEE_RECIPIENT || deployer.address;

  const PasGovernor = await hre.ethers.getContractFactory("PasGovernor");
  const gov = await PasGovernor.deploy(
    votingPeriodBlocks,
    executionDelayBlocks,
    quorumBps,
    proposalThreshold,
    defaultFeeBps,
    defaultFeeRecipient
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

  console.log("votingPeriodBlocks:", votingPeriodBlocks);
  console.log("executionDelayBlocks:", executionDelayBlocks);
  console.log("quorumBps:", quorumBps);
  console.log("proposalThresholdWei:", proposalThreshold.toString());
  console.log("defaultFeeBps:", defaultFeeBps);
  console.log("defaultFeeRecipient:", defaultFeeRecipient);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
