import { ethers } from "hardhat"
import { BigNumberish } from "ethers"

import { PWPegger__factory } from "./../typechain/factories/PWPegger__factory"
import { PWPegger } from "./../typechain/PWPegger.d"

export type PWPeggerConfig = {
  admin: string
  keeper: string
  calibrator: string
  vault: string
  pool: string
  token: string
  emergencyth: BigNumberish
  volatilityth: BigNumberish
  frontrunth: BigNumberish
  decimals: BigNumberish
}


export async function preparePWPeggerEnvironment(
  pwPeggerCfg: PWPeggerConfig
): Promise<PWPeggerContext> {
  const [wallet] = await ethers.getSigners()

  const pwPeggerFactory = (await await ethers.getContractFactory(
    "PWPegger"
  )) as PWPegger__factory
  const pwPeggerContract = await pwPeggerFactory
    .connect(wallet)
    .deploy(pwPeggerCfg)

  return {
    pwPeggerContract,
  }
}

export type PWPeggerContext = {
  pwPeggerContract: PWPegger
}

export type PWPeggerContextExtended<T> = T & PWPeggerContext

export async function preparePWPeggerWithEACAggregatorProxy(): Promise<PWPeggerContextExtended<{
}> | null> {
  return null
}
