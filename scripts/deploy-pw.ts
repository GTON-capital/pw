import Big from "big.js"
import { ethers } from "hardhat"

import { PWPegger__factory } from "./../typechain/factories/PWPegger__factory"
import { PWPeggerConfig } from "./../test/pegger"

async function mutatePWConfig(addr: string, config: PWPeggerConfig) {
  const factory = (await ethers.getContractFactory(
    "PWPegger"
  )) as PWPegger__factory

  const pwpegger = factory.attach(addr)

  const r = await pwpegger.updPWConfig(config)
  const resp = await r.wait()

  return resp
}

async function mn() {
  const hre = require("hardhat")

  const [wallet] = await ethers.getSigners()

  const factory = (await ethers.getContractFactory(
    "PWPegger"
  )) as PWPegger__factory

  const pworacle = "0x548A2b214493290bB45D516f16176Be01dbf1674"
  // const shamil = "0x3718eCd4E97f4332F9652D0Ba224f228B55ec543"

  const calibratorProxy = "0xF3ca94706164ca970B649CE72F7e424ad18cd850"

  const pwpegbasedon = "0x828761B78E22f5A24240d3EFBA04D1f0b25f4EFE"

  const config: PWPeggerConfig = {
    // admin: string
    admin: "0xEab9ff1625eD15E88fb2bCdbb4f325AA4742972d",
    // keeper: string
    keeper: pworacle,
    // pwpegdonRef: string
    pwpegdonRef: pwpegbasedon,
    // calibrator: string
    calibrator: calibratorProxy,
    // vault: string
    vault: "0xB3D22267E7260ec6c3931d50D215ABa5Fd54506a",
    // pool: string
    pool: "0x25f5b3840d414a21c4fc46d21699e54d48f75fdd",
    // token: string
    token: "0xc1be9a4d5d45beeacae296a7bd5fadbfc14602c4",
    /*
      uint emergencyth - 10% (0.1 * 10^6)
      uint volatilityth - 3% (0.03 * 10^6)
      uint frontrunth - 2% (0.02 * 10^6);
    */
    // emergencyth: BigNumberish
    emergencyth: new Big(0.1).mul(1e6).toFixed(),
    // volatilityth: BigNumberish
    volatilityth: new Big(0.03).mul(1e6).toFixed(),
    // frontrunth: BigNumberish
    frontrunth: new Big(0.02).mul(1e6).toFixed(),
    // decimals: BigNumberish
    decimals: 6,
  }

  const response = await factory.connect(wallet).deploy(config, {
    gasLimit: 5_000_000,
    gasPrice: new Big(400).mul(1e9).toNumber(),
  })
  const r = await response.deployed()

  console.log({ config, pwpegger: r.address })

  console.log("verifying...")
  await hre.run("verify:verify", {
    address: r.address,
    constructorArguments: [config],
  })
}

mn()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error)
    process.exit(1)
  })
