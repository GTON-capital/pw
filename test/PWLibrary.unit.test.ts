import { PWLibraryMock, PWLibraryMock__factory } from "~/typechain"
import { assert } from "chai"
import { BigNumberish } from "ethers"
import { ethers } from "hardhat"

import Big from "big.js"

import { TestCase, TestContext } from "./unit"

enum Direction {
  Up,
  Down,
}

describe("PW Library unit tests", () => {
  type Context = {
    pwlibrary: PWLibraryMock
  }

  async function deploy(): Promise<Context> {
    const factory = (await ethers.getContractFactory(
      "PWLibraryMock"
    )) as PWLibraryMock__factory

    const pwlibrary = await factory.deploy()

    return { pwlibrary }
  }

  /**
   *
   * General note:
   *
   * 1. Output must be encoded if it's anything rather that number
   * 2. If output is uint you have to expect output value as string (overflow prevent)
   * 3. `validate` fn in test case context can check for any behaviour (events emit, dependent contracts state change, etc.)
   *
   */

  it("test computeXLP function", async () => {
    const context = await deploy()
    const { pwlibrary } = context
    // (uint _w, uint _pRatio, uint _lps, uint decimals): uint
    type Input = {
      w: BigNumberish
      pRatio: BigNumberish
      LPs: BigNumberish
      d: BigNumberish
    }
    type Output = BigNumberish
    const testContext: TestContext<Input, Output> = {
      //g and pRatio must be same decimaled (d), LPs - any decimals
      // //interv up 1 - p1/p2 or p1/p2 - 1 inerv down
      testCases: [
        {
          input: { // UP (+25%)
            w: new Big(100).mul(1e6).toFixed(), //100 in 6 decimals
            pRatio: new Big(0.2).mul(1e6).toFixed(), // p1 = 2 p2 = 2.5 => 1 - 2/2.5 = 0.2 => 0.2*10^6 = 200k
            LPs: 100000, //any decimals let's set 3 decimal and 100 LPs
            d: 6,
          },
          output: "10000", //w == g, 0.2 means to extract we need 0.2*100/2 => 10, 10/100 is 10% of LPs so 10k
        },
        {
          input: { // DOWN (-25%)
            w: new Big(100).mul(1e6).toFixed(), //100 in 6 decimals
            pRatio: new Big(0.25).mul(1e6).toFixed(), // p1 = 2 p2 = 1.5 => Pu1 = 1/2, Pu2 = 1/1.5; 1 - ((1/2)/(1/1.5))
            LPs: 100000, //any decimals let's set 3 decimal and 100 LPs
            d: 6,
          },
          output: "12500", //w == u, 0.25 means to extract we need 0.25*100/2 = 12.5 which is 12.5/100 12.5% of LPs
        }
      ],
      validate: (x: TestCase<Input, Output>, got: Output) => {
        assert.equal(x.output, got, "expected output must match got values")
      },
    }

    for (const testcase of testContext.testCases) {
      const { input } = testcase
      const gotOutput = await pwlibrary.computeXLP(
        input.w,
        input.pRatio,
        input.LPs,
        input.d
      )

      testContext.validate(testcase, gotOutput)
    }
  })

  it("test computePRatio function", async () => {
    const context = await deploy()
    const { pwlibrary } = context
    // (uint n, uint p1, uint p2): uint
    type Input = {
      n: BigNumberish
      p1: BigNumberish
      p2: BigNumberish
    }
    type Output = BigNumberish
    const testContext: TestContext<Input, Output> = {
      testCases: [
        {
          input: {
            n:  new Big(1).mul(1e6).toFixed(),
            p1: new Big(2).mul(1e6).toFixed(),
            p2: new Big(2.5).mul(1e6).toFixed(),
          },
          output: "200000",
        },
        {
          input: {
            n: new Big(1).mul(1e6).toFixed(),
            p1: new Big(0.5).mul(1e6).toFixed(), //p1 = 2 => 0.5
            p2: new Big(0.67).mul(1e6).toFixed(), //p2 = 1.5 => 1/1.5
          },
          output: "253732", //~0.25
        },
      ],
      validate: (x: TestCase<Input, Output>, got: Output) => {
        assert.equal(x.output, got, "expected output must match got values")
      },
    }

    for (const testcase of testContext.testCases) {
      const { input } = testcase
      const gotOutput = await pwlibrary.computePRatio(
        input.n,
        input.p1,
        input.p2,
      )

      testContext.validate(testcase, gotOutput)
    }
  })

  it("test direction function", async () => {
    // findDirection(uint p1, uint p2)
    const context = await deploy()
    const { pwlibrary } = context
    // (uint n, uint p1, uint p2): uint
    type Input = {
      n: BigNumberish
      p1: BigNumberish
      p2: BigNumberish
    }
    type Output = BigNumberish
    const testContext: TestContext<Input, Output> = {
      testCases: [
        {
          input: {
            n:  new Big(1).mul(1e6).toFixed(),
            p1: new Big(2).mul(1e6).toFixed(),
            p2: new Big(2.5).mul(1e6).toFixed(),
          },
          output: Direction.Up,
        },
        {
          input: {
            n: new Big(1).mul(1e6).toFixed(),
            p1: new Big(2).mul(1e6).toFixed(), //p1 = 2
            p2: new Big(1.5).mul(1e6).toFixed(), //p2 (peg) = 1.5
          },
          output: Direction.Down,
        },
      ],
      validate: (x: TestCase<Input, Output>, got: Output) => {
        assert.equal(x.output, got, "expected output must match got values")
      },
    }

    for (const testcase of testContext.testCases) {
      const { input } = testcase
      const gotOutput = await pwlibrary.findDirection(
        input.p1,
        input.p2,
      )

      testContext.validate(testcase, gotOutput)
    }
  })
})
