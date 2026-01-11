const hre = require("hardhat");

async function main() {
  const [deployer] = await hre.ethers.getSigners();

  console.log("Deployer:", deployer.address);
  console.log("Network:", hre.network.name);

  const WETH9 = await hre.ethers.getContractFactory("WETH9");
  const weth = await WETH9.deploy();
  await weth.waitForDeployment();

  const Factory = await hre.ethers.getContractFactory("UniswapV2Factory");
  const factory = await Factory.deploy(deployer.address);
  await factory.waitForDeployment();

  const Router = await hre.ethers.getContractFactory("UniswapV2Router02");
  const router = await Router.deploy(factory.target, weth.target);
  await router.waitForDeployment();

  console.log("WETH9:", weth.target);
  console.log("Factory:", factory.target);
  console.log("Router02:", router.target);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
