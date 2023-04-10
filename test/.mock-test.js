const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("PWPeggerMock", function () {

    const [deployer, admin, keeper, other] = waffle.provider.getWallets()

    const dec = 8 //case from https://etherscan.io/address/0xdc3ea94cd0ac27d9a86c180091e7f78c683d3699#readContract
    const pwconfig = {
      admin: admin.address,
      keeper: keeper.address,
      calibrator: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      vault: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      pool: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      token: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      emergencyth: parseInt(8*(10**dec)),
      volatilityth: parseInt(4*(10**dec)),
      frontrunth: parseInt(1*(10**dec)),
      decimals: dec
    }
    var price = parseInt(2*(10**dec))

    it("Deploy PWPeggerMock and calls callIntervention and tests getPWConfig dec", async function () {

        const PWPeggerMock = await ethers.getContractFactory("PWPeggerMock");
        const pwpeggerMock = await PWPeggerMock.deploy(pwconfig);
        await pwpeggerMock.deployed();
        console.log("PWPeggerMock deployed...");
    
        const currentConfig = await pwpeggerMock.getPWConfig();


        expect(parseInt(currentConfig['decimals'])).to.equal(parseInt(dec));

        await pwpeggerMock.connect(keeper).callIntervention(price);

        const rnd = await pwpeggerMock.getLastRoundNumber();

        console.log(rnd);

        await expect(pwpeggerMock.connect(other).callIntervention(price))
            .to.be.revertedWith("Error: must be admin or keeper EOA/multisig only");

        await expect(pwpeggerMock.connect(deployer).callIntervention(price))
            .to.be.revertedWith("Error: must be admin or keeper EOA/multisig only");

    })

    it("Check pause on cases:", async function () {

        const PWPeggerMock = await ethers.getContractFactory("PWPeggerMock");
        const pwpeggerMock = await PWPeggerMock.deploy(pwconfig);
        await pwpeggerMock.deployed();

        await expect(pwpeggerMock.connect(deployer).setPauseOn())
            .to.be.revertedWith("Error: must be admin or keeper EOA/multisig only");

        await pwpeggerMock.connect(keeper).setPauseOn()

        expect(await pwpeggerMock.getPauseStatus()).to.equal(true);

        await expect(pwpeggerMock.connect(keeper).setPauseOff())
            .to.be.revertedWith("Error: must be admin EOA or multisig only");

        await expect(pwpeggerMock.connect(keeper).callIntervention(price))
            .to.be.revertedWith("PWPeggerMock in on Pause now");

        await pwpeggerMock.connect(admin).setPauseOff()

        expect(await pwpeggerMock.getPauseStatus()).to.equal(false);

        await pwpeggerMock.connect(keeper).callIntervention(price);

        const rnd = await pwpeggerMock.getLastRoundNumber();

        console.log(rnd);
    })
});
