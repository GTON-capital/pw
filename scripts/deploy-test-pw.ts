import { valueToDecimaled } from "../test/utils"
import { EACAggregatorProxy } from "./../typechain/EACAggregatorProxy.d"
import { EACAggregatorProxy__factory } from "./../typechain/factories/EACAggregatorProxy__factory"
import { CalibratorProxy } from "./../typechain/CalibratorProxy.d"
import { PWPegger } from "./../typechain/PWPegger.d"
import Big from "big.js"

import {
  prepareTokensAndPoolsForProxy,
  CalibrateDirection,
  ProxyCalibrateInput,
} from "../test/pool"
import { BigNumber } from "ethers"
import { ethers } from "hardhat"
import { Calibrator } from "~/typechain/Calibrator"
import { ERC20PresetFixedSupply } from "~/typechain/ERC20PresetFixedSupply"
import { OGXFactory } from "~/typechain/OGXFactory"
import { OGXPair } from "~/typechain/OGXPair"
import { OGXRouter02 } from "~/typechain/OGXRouter02"
import { PWPegger__factory } from "~/typechain/factories/PWPegger__factory"
import { PWPeggerConfig } from "../test/pegger"

type Context = {
  pwpegger: PWPegger
  pwpeggerConfig: PWPeggerConfig
  proxyContext: {
    calibratorProxy: CalibratorProxy
    calibrator: Calibrator
    builtPoolResponse: {
      pair: OGXPair
      factory: OGXFactory
      router: OGXRouter02
      lpOwnerHoldings: BigNumber
    }
    baseToken: ERC20PresetFixedSupply
    quoteToken: ERC20PresetFixedSupply
  }
}
let context: Context

const updateContext = async (
  {
    overrideProxyCalibrateInput,
    overridePWPeggerConfig,
  }: {
    overrideProxyCalibrateInput?: Partial<ProxyCalibrateInput>
    overridePWPeggerConfig?: Partial<PWPeggerConfig>
  } = {
    overrideProxyCalibrateInput: {},
    overridePWPeggerConfig: {},
  }
) => {
  const pwpeggerFactory = (await ethers.getContractFactory(
    "PWPegger"
  )) as PWPegger__factory

  const [deployer, keeper, pwpegdonRef_admin, vault, feegetter] =
    await ethers.getSigners()

  const proxyContext = await prepareTokensAndPoolsForProxy({
    direction: CalibrateDirection.Up,
    mintA: new Big(1_000_000_000).mul(1e18).toFixed(),
    mintB: new Big(1_000_000_000).mul(1e18).toFixed(),
    // Imitating Fantom
    liqA: new Big(100_000).mul(1e18).toFixed(),
    liqB: new Big(200_000).mul(1e18).toFixed(),
    base: {
      name: "Graviton",
      symbol: "GTON",
    },
    quote: {
      name: "USD Coin",
      symbol: "USDC",
    },
    deployer: vault,
    feeGetter: feegetter.address,
    ...overrideProxyCalibrateInput,
  })

  const config: PWPeggerConfig = {
    // admin: string
    admin: deployer.address,
    // keeper: string
    keeper: keeper.address,
    // calibrator: string
    calibrator: proxyContext.calibratorProxy.address,
    // vault: string
    vault: vault.address,
    // pool: string
    pool: proxyContext.builtPoolResponse.pair.address,
    // token: string
    token: proxyContext.baseToken.address,
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
    ...overridePWPeggerConfig,
  }

  const pwpeggerResp = await pwpeggerFactory.deploy(config)
  const pwpegger = await pwpeggerResp.deployed()

  return {
    pwpegger,
    pwpeggerConfig: config,
    proxyContext,
  }
}

// beforeEach(async () => {
//   context = await updateContext()
// })

const priceToPWPegRepr = (price: number, dec = 6): string => {
  const str = valueToDecimaled(price, dec)
  return str.slice(0, str.indexOf("."))
}

const checkDiff = (a: number, b: number): number => {
  const max = Math.max(a, b)
  const min = Math.min(a, b)
  return min / max
}

async function main() {
  const [deployer, keeper, pwpegdonRef_admin, vault] = await ethers.getSigners()

  const innerContext = {
    pwPegPrice: 2.0, //
    p1PoolPrice: 2.1,
  }

  //
  // I. Imitate current pool price 1.5
  //
  context = await updateContext({
    overrideProxyCalibrateInput: {
      liqA: new Big(100_000).mul(1e18).toFixed(), //A - G
      liqB: new Big(100_000).mul(innerContext.p1PoolPrice).mul(1e18).toFixed(), //B - means U
    },
    overridePWPeggerConfig: {
      emergencyth: new Big(0.5).mul(1e6).toFixed(), //50% th
      volatilityth: new Big(0.05).mul(1e6).toFixed(),
      frontrunth: new Big(0.04).mul(1e6).toFixed(),
    },
  })

  //
  // II. Call intervention from keeper
  //

  // give approve from vault (approve all in that case)
  await context.proxyContext.builtPoolResponse.pair
    .connect(vault)
    .approve(
      context.pwpegger.address,
      await context.proxyContext.builtPoolResponse.pair.balanceOf(vault.address)
    )

  const getPoolReserves = async () =>
    await context.proxyContext.calibrator.getReserves(
      context.proxyContext.builtPoolResponse.pair.address,
      context.proxyContext.baseToken.address,
      context.proxyContext.quoteToken.address
    )
  const poolReserves_before = await getPoolReserves()

  const LPs_supplyBefore =
    await context.proxyContext.builtPoolResponse.pair.totalSupply()

  await context.pwpegger
    .connect(keeper)
    .callIntervention(priceToPWPegRepr(innerContext.pwPegPrice)) //must be current pool price

  const LPs_supplyAfter =
    await context.proxyContext.builtPoolResponse.pair.totalSupply()

  const poolReserves = await getPoolReserves()

  const price_before =
    new Big(poolReserves_before[1].toString()).div(1e18).toNumber() /
    new Big(poolReserves_before[0].toString()).div(1e18).toNumber()
  const price_after =
    new Big(poolReserves[1].toString()).div(1e18).toNumber() /
    new Big(poolReserves[0].toString()).div(1e18).toNumber()

  console.log({
    tag: "resultsAfter",
    r0_before: new Big(poolReserves_before[0].toString()).div(1e18).toNumber(),
    r1_before: new Big(poolReserves_before[1].toString()).div(1e18).toNumber(),
    r0_after: new Big(poolReserves[0].toString()).div(1e18).toNumber(),
    r1_after: new Big(poolReserves[1].toString()).div(1e18).toNumber(),
    LPs_supplyBefore: new Big(LPs_supplyBefore.toString()).div(1e18).toNumber(),
    LPs_supplyAfter: new Big(LPs_supplyAfter.toString()).div(1e18).toNumber(),

    price_before,
    price_after,
    pwpegprice_raw: innerContext.pwPegPrice,
    pwpegprice_fmt: priceToPWPegRepr(innerContext.pwPegPrice),
    price_diff_with_peg: innerContext.pwPegPrice / price_after,
  })
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.log(err)
    process.exit(1)
  })
