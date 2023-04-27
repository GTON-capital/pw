//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "./interfaces/ICalibrator.sol";


import "hardhat/console.sol";

/// @title Calibrator
contract Calibrator is ICalibrator {

    address public owner;
    IERC20 public base;
    IUniswapV2Router02 public router;
    string public dex;

    struct Pool {
        uint256 reserveBase;
        uint256 reserveQuote;
        uint256 totalSupply;
        uint256 kLast;
    }

    struct Wallet {
        uint256 amountBase;
        uint256 amountQuote;
        uint256 liquidity;
    }

    constructor(
        IERC20 _base,
        IUniswapV2Router02 _router,
        string memory _dex
    ) {
        owner = msg.sender;
        base = _base;
        router = _router;
        dex = _dex;
    }

    function setOwner(address _owner) external {
        require(msg.sender == owner, "ACW");
        owner = _owner;
    }

    // **** CALIBRATE FUNCTIONS ****

    function calibrate3(
        IUniswapV2Pair pool1,
        uint256 liquidity1,
        uint256 amountBaseBuy1,
        IUniswapV2Pair pool2,
        uint256 liquidity2,
        uint256 amountBaseBuy2,
        IUniswapV2Pair pool3,
        uint256 liquidity3,
        uint256 amountBaseBuy3,
        address to
    ) external {
        calibrate(pool1, liquidity1, amountBaseBuy1, to);
        calibrate(pool2, liquidity2, amountBaseBuy2, to);
        calibrate(pool3, liquidity3, amountBaseBuy3, to);
    }

    function calibrate2(
        IUniswapV2Pair pool1,
        uint256 liquidity1,
        uint256 amountBaseBuy1,
        IUniswapV2Pair pool2,
        uint256 liquidity2,
        uint256 amountBaseBuy2,
        address to
    ) external {
        calibrate(pool1, liquidity1, amountBaseBuy1, to);
        calibrate(pool2, liquidity2, amountBaseBuy2, to);
    }

    function calibrateSafe(
        IUniswapV2Pair pool,
        uint256 liquidity,
        uint256 amountBuy,
        address to,
        uint256 price // price * 10000; 60.12 = 612000; 0.652 = 6520; 0.0632 = 632
    ) public {
        // remove `liquidity`
        (uint256 reserveBase, uint256 reserveQuote, , ) = estimateNow(
            pool,
            liquidity,
            amountBuy
        );
        require((reserveBase * 10000) / reserveQuote < price, "C1");
        IERC20 token = tokenFromPool(pool);
        remove(pool, token, liquidity);
        // buy base for `amountBuy`
        buy(token, amountBuy);
        // add liquidity for all quote token and have some base left
        add(pool, token);
        // send base and lp to `to`
        retrieve(pool, to, token);
    }

    function calibrateDown(
        IUniswapV2Pair pool,
        uint256 liquidity,
        uint256 amountSell,
        address to
    ) override public {
        IERC20 token = tokenFromPool(pool);
        remove(pool, token, liquidity);
        sell(token, amountSell);
        add(pool, token);
        retrieve(pool, to, token);
    }

    function calibrate(
        IUniswapV2Pair pool,
        uint256 liquidity,
        uint256 amountBuy,
        address to
    ) override public {
        // remove `liquidity`
        IERC20 token = tokenFromPool(pool);
        remove(pool, token, liquidity);
        // console.log("amountBuy: %s", amountBuy);
        // console.log("balance before - b: %s, q: %s", base.balanceOf(address(this)), token.balanceOf(address(this)));
        // buy base for `amountBuy`
        buy(token, amountBuy);
        // console.log("balance after - b: %s, q: %s", base.balanceOf(address(this)), token.balanceOf(address(this)));
        // add liquidity for all quote token and have some base left
        add(pool, token);
        // send base and lp to `to`
        retrieve(pool, to, token);
    }

    function removeThenBuy(
        IUniswapV2Pair pool,
        uint256 liquidity,
        uint256 amountBuy,
        address to
    ) public {
        // remove `liquidity`
        IERC20 token = tokenFromPool(pool);
        remove(pool, token, liquidity);
        // buy base for `amountBuy`
        buy(token, amountBuy);
        // send base and lp to `to`
        retrieve(pool, to, token);
    }

    function remove(
        IUniswapV2Pair pool,
        IERC20 token,
        uint256 liquidityRemove
    ) public {
        // transfer `liquidity` from msg.sender
        pool.transferFrom(msg.sender, address(this), liquidityRemove);
        // log(pool, "=========== before remove ===========");
        uint256 liquidity = pool.balanceOf(address(this));
        uint256 totalSupply = pool.totalSupply();
        uint256 kLast = pool.kLast();
        (uint256 reserveBase, uint256 reserveQuote) = getReserves(
            pool,
            address(base),
            address(token)
        );
        (
            ,
            ,
            ,
            ,
            uint256 amountBaseAfter,
            uint256 amountQuoteAfter
        ) = estimateRemove(
                reserveBase,
                reserveQuote,
                totalSupply,
                kLast,
                liquidity
            );
        uint256 deadline = block.timestamp + 86400;
        console.log("remove liquidity", amountBaseAfter, amountQuoteAfter, liquidity);
        pool.approve(address(router), liquidity);
        router.removeLiquidity(
            address(base),
            address(token),
            liquidity,
            amountBaseAfter,
            amountQuoteAfter,
            address(this),
            deadline
        );
        // log(pool, "===========  after remove ===========");
    }

    function sell(
        IERC20 token,
        uint256 amountSell
    ) public {
        base.approve(address(router), base.balanceOf(address(this)));
        token.approve(address(router), token.balanceOf(address(this)));
        address[] memory pathToBase = new address[](2);
        pathToBase[0] = address(base);
        pathToBase[1] = address(token);
        uint256 deadline = block.timestamp + 86400;
        uint256[] memory amounts = router.getAmountsOut(amountSell, pathToBase);
        router.swapTokensForExactTokens(
            amountSell,
            amounts[0],
            pathToBase,
            address(this),
            deadline
        );
        // log(pool, "===========   after buy   ===========");
    }

    function buy(
        IERC20 token,
        uint256 amountBuy
    ) public {
        // log(pool, "===========   before buy  ===========");
        base.approve(address(router), base.balanceOf(address(this)));
        token.approve(address(router), token.balanceOf(address(this)));
        address[] memory pathToBase = new address[](2);
        pathToBase[0] = address(token);
        pathToBase[1] = address(base);
        uint256 deadline = block.timestamp + 86400;
        uint256[] memory amounts = router.getAmountsIn(amountBuy, pathToBase);
        // console.log("swap base for token", amountBuy, amounts[0]);
        router.swapTokensForExactTokens(
            amountBuy,
            amounts[0],
            pathToBase,
            address(this),
            deadline
        );
        // log(pool, "===========   after buy   ===========");
    }

    function add(IUniswapV2Pair pool, IERC20 token) public {
        // log(pool, "===========   before add  ===========");
        uint256 balanceOfToken = token.balanceOf(address(this));
        uint256 balanceOfBase = base.balanceOf(address(this));

        base.approve(address(router), balanceOfBase);
        token.approve(address(router), balanceOfToken);

        uint256 amountQuoteAdd = balanceOfToken;
        uint256 amountBaseAdd = balanceOfBase;

        if (amountBaseAdd == 0 || amountQuoteAdd == 0) {
            return;
        }

        address[] memory pathToBase = new address[](2);
        pathToBase[0] = address(token);
        pathToBase[1] = address(base);
        uint256 deadline = block.timestamp + 86400;
        (uint256 reserveBase, uint256 reserveQuote) = getReserves(
            pool,
            address(base),
            address(token)
        );
        amountBaseAdd = quote(
            amountQuoteAdd,
            reserveQuote,
            reserveBase
        );
        if (amountBaseAdd == 0) {
            return;
        }

        // console.log("balances base and token", balanceOfBase, balanceOfToken);
        // console.log("add liquidity", amountBaseAdd, amountQuoteAdd);
        /**
         * Due to a fact that after swap amountBaseAdd may be much more than balanceOfBase
         * this `if` statement handles the case of `base` token disbalance
         * with further recalculations.
         *
         * Moreover, case of `amountBaseAdd <= balanceOfBase` is handled by default.
         */
        if (amountBaseAdd > balanceOfBase) {
            amountBaseAdd = balanceOfBase;
            amountQuoteAdd = quote(
                amountBaseAdd,
                reserveBase,
                reserveQuote
            );
            // recalculate because base is taken first into consideration on `addLiquidity`
            amountBaseAdd = quote(
                amountQuoteAdd,
                reserveQuote,
                reserveBase
            );
        }

        (uint256 amountA, uint256 amountB, uint256 liq) = router.addLiquidity(
            address(token),
            address(base),
            amountQuoteAdd,
            amountBaseAdd,
            amountQuoteAdd,
            amountBaseAdd,
            address(this),
            deadline
        );
        console.log("add liquidity", amountA, amountB, liq);
        // log(pool, "===========   after add   ===========");
    }

    function retrieve(IUniswapV2Pair pool, address to, IERC20 token) internal {
        require(to != address(0), "can't send to 0");
        pool.transfer(to, pool.balanceOf(address(this)));
        base.transfer(to, base.balanceOf(address(this)));
        token.transfer(to, token.balanceOf(address(this)));
    }

    // **** ESTIMATE FUNCTIONS ****
    function estimateNow(
        IUniswapV2Pair pool,
        uint256 liquidityRemove,
        uint256 amountBuy
    )
        public
        view
        returns (
            uint256 reserveBase,
            uint256 reserveQuote,
            uint256 amountBase,
            uint256 liquidityAfter
        )
    {
        Pool memory pBefore;

        IERC20 token = tokenFromPool(pool);
        (pBefore.reserveBase, pBefore.reserveQuote) = getReserves(
            pool,
            address(base),
            address(token)
        );
        pBefore.totalSupply = pool.totalSupply();
        pBefore.kLast = pool.kLast();

        (Pool memory pAfter, Wallet memory wAfter) = estimate(
            pBefore,
            liquidityRemove,
            amountBuy
        );

        return (
            pAfter.reserveBase,
            pAfter.reserveQuote,
            wAfter.amountBase,
            wAfter.liquidity
        );
    }

    function estimateBuyNow(IUniswapV2Pair pool, uint256 amountBaseBuy)
        external
        view
        returns (
            uint256 reserveBase,
            uint256 reserveQuote,
            uint256 amountTokenSell
        )
    {
        IERC20 token = tokenFromPool(pool);
        (uint256 reserveBaseBefore, uint256 reserveQuoteBefore) = getReserves(
            pool,
            address(base),
            address(token)
        );

        (reserveBase, reserveQuote, amountTokenSell) = estimateBuy(
            reserveBaseBefore,
            reserveQuoteBefore,
            amountBaseBuy
        );

        return (reserveBase, reserveQuote, amountTokenSell);
    }

    function estimateSellNow(IUniswapV2Pair pool, uint256 amountBaseSell)
        external
        view
        returns (
            uint256 reserveBase,
            uint256 reserveQuote,
            uint256 amountTokenBuy
        )
    {
        IERC20 token = tokenFromPool(pool);
        (uint256 reserveBaseBefore, uint256 reserveQuoteBefore) = getReserves(
            pool,
            address(base),
            address(token)
        );

        (reserveBase, reserveQuote, amountTokenBuy) = estimateSell(
            reserveBaseBefore,
            reserveQuoteBefore,
            amountBaseSell
        );

        return (reserveBase, reserveQuote, amountTokenBuy);
    }

    function estimate(
        Pool memory pBefore,
        uint256 liquidityRemove,
        uint256 amountBaseBuy
    ) public view returns (Pool memory pAfter, Wallet memory wAfter) {
        (Pool memory pAfterRemove, Wallet memory wAfterRemove) = estimateRemove(
            pBefore,
            liquidityRemove
        );

        (Pool memory pAfterBuy, Wallet memory wAfterBuy, ) = estimateBuy(
            pAfterRemove,
            wAfterRemove,
            amountBaseBuy
        );

        (Pool memory pAfterAdd, Wallet memory wAfterAdd) = estimateAdd(
            pAfterBuy,
            wAfterBuy
        );

        pAfter = pAfterAdd;
        wAfter = wAfterAdd;
    }

    function estimateRemove(Pool memory pBefore, uint256 liquidityRemove)
        public
        pure
        returns (Pool memory pAfter, Wallet memory wAfter)
    {
        pAfter = pBefore;

        uint256 reserveBase = pBefore.reserveBase;
        uint256 reserveQuote = pBefore.reserveQuote;
        uint256 totalSupply = pBefore.totalSupply;
        uint256 kLast = pBefore.kLast;

        totalSupply = mintFee(reserveBase, reserveQuote, totalSupply, kLast);

        uint256 amountBase = (liquidityRemove * reserveBase) / totalSupply;
        uint256 amountQuote = (liquidityRemove * reserveQuote) / totalSupply;

        pAfter.totalSupply = totalSupply - liquidityRemove;

        wAfter.amountBase = amountBase;
        wAfter.amountQuote = amountQuote;

        pAfter.reserveBase = reserveBase - amountBase;
        pAfter.reserveQuote = reserveQuote - amountQuote;

        pAfter.kLast = pAfter.reserveBase * pAfter.reserveQuote;
    }

    function estimateBuy(
        Pool memory pBefore,
        Wallet memory wBefore,
        uint256 amountBaseBuy
    )
        public
        pure
        returns (
            Pool memory pAfter,
            Wallet memory wAfter,
            uint256 amountTokenSell
        )
    {
        pAfter = pBefore;
        wAfter = wBefore;

        amountTokenSell = getAmountIn(
            amountBaseBuy,
            pBefore.reserveQuote,
            pBefore.reserveBase
        );
        // console.log("swap base for token", amountBaseBuy, amountTokensell);

        wAfter.amountBase = wBefore.amountBase + amountBaseBuy;
        wAfter.amountQuote = wBefore.amountQuote - amountTokenSell;
        pAfter.reserveBase = pBefore.reserveBase - amountBaseBuy;
        pAfter.reserveQuote = pBefore.reserveQuote + amountTokenSell;
        // console.log("reserves after buy", pAfter.reserveBase, pAfter.reserveQuote);
    }

    function estimateAdd(Pool memory pBefore, Wallet memory wBefore)
        public
        pure
        returns (Pool memory pAfter, Wallet memory wAfter)
    {
        pAfter = pBefore;
        wAfter = wBefore;

        uint256 reserveBase = pBefore.reserveBase;
        uint256 reserveQuote = pBefore.reserveQuote;
        uint256 totalSupply = pBefore.totalSupply;
        uint256 kLast = pBefore.kLast;
        uint256 amountQuoteAdd = wBefore.amountQuote;

        uint256 amountBaseAdd = quote(
            amountQuoteAdd,
            reserveQuote,
            reserveBase
        );
        wAfter.amountBase = wBefore.amountBase - amountBaseAdd;
        wAfter.amountQuote = wBefore.amountQuote - amountQuoteAdd;

        totalSupply = mintFee(reserveBase, reserveQuote, totalSupply, kLast);

        uint256 liquidity = min(
            (amountBaseAdd * totalSupply) / reserveBase,
            (amountQuoteAdd * totalSupply) / reserveQuote
        );

        wAfter.liquidity = liquidity;
        pAfter.totalSupply = totalSupply + liquidity;

        pAfter.reserveBase = reserveBase + amountBaseAdd;
        pAfter.reserveQuote = reserveQuote + amountQuoteAdd;

        pAfter.kLast = pAfter.reserveBase * pAfter.reserveQuote;
    }

    // **** PICK FUNCTIONS ****
    function pickBuyNow(
        IUniswapV2Pair pool,
        uint256 price, // 2 decimals
        uint256 start,
        uint256 end
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        IERC20 token = tokenFromPool(pool);
        (uint256 reserveBaseBefore, uint256 reserveQuoteBefore) = getReserves(
            pool,
            address(base),
            address(token)
        );
        return
            pickBuy(reserveBaseBefore, reserveQuoteBefore, price, start, end);
    }

    function pickSellNow(
        IUniswapV2Pair pool,
        uint256 price, // 2 decimals
        uint256 start,
        uint256 end
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        IERC20 token = tokenFromPool(pool);
        (uint256 reserveBaseBefore, uint256 reserveQuoteBefore) = getReserves(
            pool,
            address(base),
            address(token)
        );
        return
            pickSell(reserveBaseBefore, reserveQuoteBefore, price, start, end);
    }

    function pickBuy(
        uint256 reserveBaseBefore,
        uint256 reserveQuoteBefore,
        uint256 price, // 2 decimals
        uint256 start,
        uint256 end
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 ds = 100;
        if ((reserveQuoteBefore * ds) / reserveBaseBefore == price) {
            // console.log(
            //     // "--",
            //     reserveBaseBefore,
            //     reserveQuoteBefore,
            //     (reserveQuoteBefore * ds) / reserveBaseBefore,
            //     0
            // );
            return (reserveBaseBefore, reserveQuoteBefore, 0);
        }
        uint256 amountBaseBuy = (start + end) / 2;
        if (start > end) {
            return (reserveBaseBefore, reserveQuoteBefore, amountBaseBuy);
        }
        (
            uint256 reserveBaseAfter,
            uint256 reserveQuoteAfter,
            uint256 amountQuoteSell
        ) = estimateBuy(reserveBaseBefore, reserveQuoteBefore, amountBaseBuy);
        if ((reserveQuoteAfter * ds) / reserveBaseAfter == price) {
            // console.log(
            //     // "eq",
            //     reserveBaseAfter,
            //     reserveQuoteAfter,
            //     (reserveQuoteAfter * ds) / reserveBaseAfter,
            //     amountBaseBuy
            // );
            return (reserveBaseAfter, reserveQuoteAfter, amountBaseBuy);
        }
        if ((reserveQuoteAfter * ds) / reserveBaseAfter < price) {
            // console.log(
            //     // "lt",
            //     reserveBaseAfter,
            //     reserveQuoteAfter,
            //     (reserveQuoteAfter * ds) / reserveBaseAfter,
            //     amountBaseBuy
            // );
            return
                pickBuy(
                    reserveBaseBefore,
                    reserveQuoteBefore,
                    price,
                    amountBaseBuy + 1,
                    end
                );
        }
        if ((reserveQuoteAfter * ds) / reserveBaseAfter > price) {
            // console.log(
            //     // "gt",
            //     reserveBaseAfter,
            //     reserveQuoteAfter,
            //     (reserveQuoteAfter * ds) / reserveBaseAfter,
            //     amountBaseBuy
            // );
            return
                pickBuy(
                    reserveBaseBefore,
                    reserveQuoteBefore,
                    price,
                    start,
                    amountBaseBuy - 1
                );
        }
    }

    function pickSell(
        uint256 reserveBaseBefore,
        uint256 reserveQuoteBefore,
        uint256 price, // 2 decimals
        uint256 start,
        uint256 end
    )
        public
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 ds = 100;
        if ((reserveQuoteBefore * ds) / reserveBaseBefore == price) {
            // console.log(
            //     // "--",
            //     reserveBaseBefore,
            //     reserveQuoteBefore,
            //     (reserveQuoteBefore * ds) / reserveBaseBefore,
            //     0
            // );
            return (reserveBaseBefore, reserveQuoteBefore, 0);
        }
        uint256 amountBaseSell = (start + end) / 2;
        if (start > end) {
            return (reserveBaseBefore, reserveQuoteBefore, amountBaseSell);
        }
        (
            uint256 reserveBaseAfter,
            uint256 reserveQuoteAfter,
            uint256 amountQuoteSell
        ) = estimateSell(reserveBaseBefore, reserveQuoteBefore, amountBaseSell);
        if ((reserveQuoteAfter * ds) / reserveBaseAfter == price) {
            // console.log(
            //     // "eq",
            //     reserveBaseAfter,
            //     reserveQuoteAfter,
            //     (reserveQuoteAfter * ds) / reserveBaseAfter,
            //     amountBaseSell
            // );
            return (reserveBaseAfter, reserveQuoteAfter, amountBaseSell);
        }
        if ((reserveQuoteAfter * ds) / reserveBaseAfter > price) {
            // console.log(
            //     // "lt",
            //     reserveBaseAfter,
            //     reserveQuoteAfter,
            //     (reserveQuoteAfter * ds) / reserveBaseAfter,
            //     amountBaseSell
            // );
            return
                pickSell(
                    reserveBaseBefore,
                    reserveQuoteBefore,
                    price,
                    amountBaseSell + 1,
                    end
                );
        }
        if ((reserveQuoteAfter * ds) / reserveBaseAfter < price) {
            // console.log(
            //     // "gt",
            //     reserveBaseAfter,
            //     reserveQuoteAfter,
            //     (reserveQuoteAfter * ds) / reserveBaseAfter,
            //     amountBaseSell
            // );
            return
                pickSell(
                    reserveBaseBefore,
                    reserveQuoteBefore,
                    price,
                    start,
                    amountBaseSell - 1
                );
        }
    }

    // **** STEP FUNCTIONS ****
    function estimateRemove(
        uint256 reserveBaseBefore,
        uint256 reserveQuoteBefore,
        uint256 totalSupplyBefore,
        uint256 kLastBefore,
        uint256 liquidityRemove
    )
        override
        public
        pure
        returns (
            uint256 reserveBaseAfter,
            uint256 reserveQuoteAfter,
            uint256 totalSupplyAfter,
            uint256 kLastAfter,
            uint256 amountBaseAfter,
            uint256 amountQuoteAfter
        )
    {
        uint256 totalSupply = mintFee(
            reserveBaseBefore,
            reserveQuoteBefore,
            totalSupplyBefore,
            kLastBefore
        );

        amountBaseAfter = (liquidityRemove * reserveBaseBefore) / totalSupply;
        amountQuoteAfter = (liquidityRemove * reserveQuoteBefore) / totalSupply;

        totalSupplyAfter = totalSupplyBefore - liquidityRemove;

        reserveBaseAfter = reserveBaseBefore - amountBaseAfter;
        reserveQuoteAfter = reserveQuoteBefore - amountQuoteAfter;

        kLastAfter = reserveBaseAfter * reserveQuoteAfter;
    }

    function estimateBuy(
        uint256 reserveBaseBefore,
        uint256 reserveQuoteBefore,
        uint256 amountBaseBuy
    )
        override
        public
        pure
        returns (
            uint256 reserveBaseAfter,
            uint256 reserveQuoteAfter,
            uint256 amountQuoteSell
        )
    {
        amountQuoteSell = getAmountIn(
            amountBaseBuy,
            reserveQuoteBefore,
            reserveBaseBefore
        );

        reserveBaseAfter = reserveBaseBefore - amountBaseBuy;
        reserveQuoteAfter = reserveQuoteBefore + amountQuoteSell;
    }

    function estimateSell(
        uint256 reserveBaseBefore,
        uint256 reserveQuoteBefore,
        uint256 amountBaseSell
    )
        override
        public
        pure
        returns (
            uint256 reserveBaseAfter,
            uint256 reserveQuoteAfter,
            uint256 amountQuoteBuy
        )
    {
        amountQuoteBuy = getAmountOut(
            amountBaseSell,
            reserveBaseBefore,
            reserveQuoteBefore
        );
        reserveBaseAfter = reserveBaseBefore + amountBaseSell;
        reserveQuoteAfter = reserveQuoteBefore - amountQuoteBuy;
    }

    function estimateAdd(
        uint256 reserveBaseBefore,
        uint256 reserveQuoteBefore,
        uint256 totalSupplyBefore,
        uint256 kLastBefore,
        uint256 amountQuoteAdd
    )
        public
        pure
        returns (
            uint256 reserveBaseAfter,
            uint256 reserveQuoteAfter,
            uint256 totalSupplyAfter,
            uint256 kLastAfter,
            uint256 amountBaseAdd,
            uint256 liquidity
        )
    {
        amountBaseAdd = quote(
            amountQuoteAdd,
            reserveQuoteBefore,
            reserveBaseBefore
        );

        uint256 totalSupply = mintFee(
            reserveBaseBefore,
            reserveQuoteBefore,
            totalSupplyBefore,
            kLastBefore
        );

        liquidity = min(
            (amountBaseAdd * totalSupplyAfter) / reserveBaseBefore,
            (amountQuoteAdd * totalSupplyAfter) / reserveQuoteBefore
        );

        totalSupplyAfter = totalSupply + liquidity;

        reserveBaseAfter = reserveBaseBefore + amountBaseAdd;
        reserveQuoteAfter = reserveQuoteBefore + amountQuoteAdd;

        kLastAfter = reserveBaseAfter * reserveQuoteAfter;
    }

    // **** LIBRARY FUNCTIONS ****
    function sqrt(uint256 a) internal pure returns (uint256 b) {
        if (a > 3) {
            b = a;
            uint256 x = a / 2 + 1;
            while (x < b) {
                b = x;
                x = (a / x + x) / 2;
            }
        } else if (a != 0) {
            b = 1;
        }
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a <= b ? a : b;
    }

    function equal(string memory a, string memory b)
        public
        pure
        returns (bool)
    {
        return keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b));
    }

    /**
     * returns quote token
     */
    function tokenFromPool(IUniswapV2Pair pool)
        override
        public
        view
        returns (IERC20 token)
    {
        address token0 = pool.token0();
        address token1 = pool.token1();
        token = token0 == address(base) ? IERC20(token1) : IERC20(token0);
    }

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }
    
    function getRouter() override public view returns (address rtr) {
        rtr = address(router);
    }
    // fetches and sorts the reserves for a pair
    // uses getPair instead of pairFor because init code hashes can be different for amms
    function getReserves(
        IUniswapV2Pair pool,
        address tokenA,
        address tokenB
    ) override public view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = pool.getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) public pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        amountB = (amountA * reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) override public pure returns (uint256 amountOut) {
        // require(amountIn > 0, 'UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        // require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');

        // Default Uniswap V2 params, might need changing if DEX has different fees
        uint256 amountInWithFee = amountIn * 997;
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountIn) {
        // require(amountOut > 0, 'UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        // require(reserveIn > 0 && reserveOut > 0, 'UniswapV2Library: INSUFFICIENT_LIQUIDITY');

        // Default Uniswap V2 params, might need changing if DEX has different fees
        uint256 numerator = reserveIn * amountOut * 1000;
        uint256 denominator = (reserveOut - amountOut) * 997;
        amountIn = (numerator / denominator) + 1;
    }

    function mintFee(
        uint256 reserve0,
        uint256 reserve1,
        uint256 totalSupply,
        uint256 kLast
    ) internal pure returns (uint256 totalSupplyNew) {
        
        // Default Uniswap V2 params, might need changing if DEX has different fees
        if (kLast != 0) {
            uint256 rootK = sqrt(reserve0 * reserve1);
            uint256 rootKLast = sqrt(kLast);
            if (rootK > rootKLast) {
                uint256 numerator = totalSupply * (rootK - rootKLast);
                uint256 denominator = (rootK * 5) + rootKLast;
                uint256 liquidityFee = numerator / denominator;
                if (liquidityFee > 0) {
                    totalSupply += liquidityFee;
                }
            }
        }
        return totalSupply;
    }

    // **** RECLAIM FUNCTION ****
    function reclaimERC20(IERC20 token, uint256 amount) external {
        require(msg.sender == owner, "ACW");
        token.transfer(msg.sender, amount);
    }

    function reclaimNative(uint256 amount) external {
        require(msg.sender == owner, "ACW");
        payable(msg.sender).transfer(amount);
    }

    // **** LOG FUNCTION ****
    // function log(IUniswapV2Pair pool, string memory s) internal {
    //     IERC20 token = tokenFromPool(pool);
    //     console.log(s);
    //     console.log(
    //         "balances",
    //         base.balanceOf(address(this)),
    //         token.balanceOf(address(this))
    //     );
    //     console.log(
    //         "reserves",
    //         base.balanceOf(address(pool)),
    //         token.balanceOf(address(pool))
    //     );
    //     address[] memory pathToQuote = new address[](2);
    //     pathToQuote[0] = address(base);
    //     pathToQuote[1] = address(token);
    //     uint[] memory tokens = router.getAmountsOut(1e4, pathToQuote);
    //     console.log("for 10000 base", tokens[1], "token");
    //     console.log(tokens[1], "/", tokens[0], tokens[1]/tokens[0]);
    //     console.log(tokens[0], "/", tokens[1], tokens[1]==0 ? 0 : tokens[0]/tokens[1]);
    //     console.log("=====================================");
    // }
}
