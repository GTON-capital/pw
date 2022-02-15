import Big from "big.js"
import { ethers, waffle } from "hardhat"

import { preparePWPeggerEnvironment, PWPeggerConfig } from "./pegger"

// actually rewrite of mock-test.js
describe("PW Pegger mock tests", () => {
  async function prepareMock(pwconfig: PWPeggerConfig) {
    const PWPeggerMock = await ethers.getContractFactory("PWPeggerMock")
    const pwpeggerMock = await PWPeggerMock.deploy(pwconfig)
    await pwpeggerMock.deployed()

    return {
      pwpeggerMock,
    }
  }

  const [deployer, admin, keeper, other] = waffle.provider.getWallets()

  const testCaseInputs = [
    {
      admin: admin.address,
      keeper: keeper.address,
      pwpegdonRef: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      calibrator: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      vault: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      pool: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      token: "0xbb652A9FAc95B5203f44aa3492200b6aE6aD84e0",
      emergencyth: parseInt(8 * 10 ** dec),
      volatilityth: parseInt(4 * 10 ** dec),
      frontrunth: parseInt(1 * 10 ** dec),
      decimals: dec,
    },
  ]

  it("", async () => {
    console.log("PWPeggerMock deployed...")

    const { pwpeggerMock } = await prepareMock(config)
    const currentConfig = await pwpeggerMock.getPWConfig()

    expect(parseInt(currentConfig["decimals"])).to.equal(parseInt(dec))

    await pwpeggerMock.connect(keeper).callIntervention(price)

    const rnd = await pwpeggerMock.getLastRoundNumber()

    console.log(rnd)

    await expect(
      pwpeggerMock.connect(other).callIntervention(price)
    ).to.be.revertedWith("Error: must be admin or keeper EOA/multisig only")

    await expect(
      pwpeggerMock.connect(deployer).callIntervention(price)
    ).to.be.revertedWith("Error: must be admin or keeper EOA/multisig only")
  })
})
