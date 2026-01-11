const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("CLOB MVP OrderBook", function () {
  it("deposit/withdraw + place/cancel + match + fees", async function () {
    const [owner, alice, bob, matcher, feeRecipient] = await ethers.getSigners();

    const TestERC20 = await ethers.getContractFactory("TestERC20");
    const base = await TestERC20.deploy("Base", "BASE", ethers.parseUnits("1000000", 18));
    const quote = await TestERC20.deploy("Quote", "QUOTE", ethers.parseUnits("1000000", 18));

    const feeBps = 50; // 0.50%
    const OrderBook = await ethers.getContractFactory("OrderBook");
    const ob = await OrderBook.deploy(base.target, quote.target, matcher.address, feeRecipient.address, feeBps);

    // fund users
    await base.transfer(alice.address, ethers.parseUnits("100", 18));
    await quote.transfer(alice.address, ethers.parseUnits("1000", 18));
    await base.transfer(bob.address, ethers.parseUnits("100", 18));
    await quote.transfer(bob.address, ethers.parseUnits("1000", 18));

    // deposit
    const depositBase = ethers.parseUnits("50", 18);
    const depositQuote = ethers.parseUnits("500", 18);

    await base.connect(alice).approve(ob.target, depositBase);
    await ob.connect(alice).deposit(base.target, depositBase);

    await quote.connect(alice).approve(ob.target, depositQuote);
    await ob.connect(alice).deposit(quote.target, depositQuote);

    // withdraw
    const withdrawQuote = ethers.parseUnits("10", 18);
    await ob.connect(alice).withdraw(quote.target, withdrawQuote);

    const availableQuoteAfterWithdraw = await ob.available(alice.address, quote.target);
    expect(availableQuoteAfterWithdraw).to.equal(depositQuote - withdrawQuote);

    // Bob deposits base for selling
    const bobDepositBase = ethers.parseUnits("20", 18);
    await base.connect(bob).approve(ob.target, bobDepositBase);
    await ob.connect(bob).deposit(base.target, bobDepositBase);

    // Place orders
    // Alice places buy: price=2 quote/base, amount=10 base => locks 20 quote
    const buyPrice = ethers.parseUnits("2", 18);
    const buyAmount = ethers.parseUnits("10", 18);
    const txBuy = await ob.connect(alice).placeBuy(buyPrice, buyAmount);
    const receiptBuy = await txBuy.wait();
    const buyOrderId = receiptBuy.logs.find((l) => l.fragment && l.fragment.name === "OrderPlaced").args.orderId;

    // Bob places sell: price=1.5 quote/base, amount=10 base => locks 10 base
    const sellPrice = ethers.parseUnits("1.5", 18);
    const sellAmount = ethers.parseUnits("10", 18);
    const txSell = await ob.connect(bob).placeSell(sellPrice, sellAmount);
    const receiptSell = await txSell.wait();
    const sellOrderId = receiptSell.logs.find((l) => l.fragment && l.fragment.name === "OrderPlaced").args.orderId;

    // Match at executionPrice=1.5, fill=10
    const execPrice = sellPrice;
    const fill = buyAmount;

    await ob.connect(matcher).matchOrders(buyOrderId, sellOrderId, fill, execPrice);

    // Balances:
    // Buyer receives 10 base
    const buyerBaseAvail = await ob.available(alice.address, base.target);
    expect(buyerBaseAvail).to.equal(depositBase + fill);

    // Seller receives 15 quote
    const quoteAmount = (fill * execPrice) / ethers.parseUnits("1", 18);
    const sellerQuoteAvail = await ob.available(bob.address, quote.target);
    expect(sellerQuoteAvail).to.equal(quoteAmount);

    // Fee recipient receives fee on quote
    const feeAmount = (quoteAmount * BigInt(feeBps)) / 10000n;
    const feeRecipientQuoteAvail = await ob.available(feeRecipient.address, quote.target);
    expect(feeRecipientQuoteAvail).to.equal(feeAmount);

    // Buyer refund due to price improvement: lockedQuote(20) - (quoteAmount + feeAmount)
    const lockedAtLimit = (fill * buyPrice) / ethers.parseUnits("1", 18);
    const refund = lockedAtLimit - (quoteAmount + feeAmount);

    const buyerQuoteAvail = await ob.available(alice.address, quote.target);
    // Started with (depositQuote-withdrawQuote), then locked 20, then refund
    const expectedBuyerQuoteAvail = (depositQuote - withdrawQuote) - lockedAtLimit + refund;
    expect(buyerQuoteAvail).to.equal(expectedBuyerQuoteAvail);

    // Cancel already filled order should revert
    await expect(ob.connect(alice).cancel(buyOrderId)).to.be.reverted;
  });
});
