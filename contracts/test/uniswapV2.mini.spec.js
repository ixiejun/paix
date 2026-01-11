const { expect } = require("chai");
const { ethers } = require("hardhat");

async function mineBlock() {
  await ethers.provider.send("evm_mine", []);
}

describe("Uniswap V2 MVP (Factory/Pair/Router02)", function () {
  it("createPair + addLiquidity + swapExactTokensForTokens", async function () {
    const [deployer, user] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const tokenA = await TestERC20.deploy("TokenA", "TKA", ethers.parseUnits("1000000", 18));
    const tokenB = await TestERC20.deploy("TokenB", "TKB", ethers.parseUnits("1000000", 18));

    const WETH9 = await ethers.getContractFactory("WETH9");
    const weth = await WETH9.deploy();

    const Factory = await ethers.getContractFactory("UniswapV2Factory");
    const factory = await Factory.deploy(deployer.address);

    const Router = await ethers.getContractFactory("UniswapV2Router02");
    const router = await Router.deploy(factory.target, weth.target);

    // createPair via factory (router can also create on addLiquidity)
    await factory.createPair(tokenA.target, tokenB.target);
    const pairAddress = await factory.getPair(tokenA.target, tokenB.target);
    expect(pairAddress).to.properAddress;

    // Provide liquidity
    const amountA = ethers.parseUnits("1000", 18);
    const amountB = ethers.parseUnits("1000", 18);

    await tokenA.approve(router.target, amountA);
    await tokenB.approve(router.target, amountB);

    const deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;

    await router.addLiquidity(
      tokenA.target,
      tokenB.target,
      amountA,
      amountB,
      0,
      0,
      deployer.address,
      deadline
    );

    // Swap
    const swapIn = ethers.parseUnits("10", 18);
    await tokenA.transfer(user.address, swapIn);
    await tokenA.connect(user).approve(router.target, swapIn);

    const outBefore = await tokenB.balanceOf(user.address);
    await router.connect(user).swapExactTokensForTokens(
      swapIn,
      0,
      [tokenA.target, tokenB.target],
      user.address,
      deadline
    );
    const outAfter = await tokenB.balanceOf(user.address);

    expect(outAfter).to.be.gt(outBefore);

    // Ensure reserves updated (best-effort check)
    const Pair = await ethers.getContractFactory("UniswapV2Pair");
    const pair = Pair.attach(pairAddress);
    const reserves = await pair.getReserves();
    expect(reserves[0] + reserves[1]).to.be.gt(0n);

    // keep chain moving
    await mineBlock();
  });
});
