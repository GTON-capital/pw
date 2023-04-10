//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interfaces/IPWPegger.sol";
import "./interfaces/ICalibratorProxy.sol";
import "./interfaces/IEACAggregatorProxy.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV2Pair.sol";

import "./libraries/PWLibrary.sol";
import "./libraries/PWConfig.sol";

// import "hardhat/console.sol";


struct PoolData {
    uint g; // Quote token
    uint u; // Base token - OGXT
    uint p1; 
    uint lp;
}

contract PWPegger is IPWPegger {

    PWConfig private pwconfig;
    bool statusPause;
    uint round;

    modifier onlyAdmin() {
        require(msg.sender == pwconfig.admin, "Error: not admin");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == pwconfig.admin || msg.sender == pwconfig.keeper, 
            "Error: not admin or keeper");
        _;
    }

    modifier onlyNotPaused() {
        require(!statusPause, "PWPeggerMock in on Pause now");
        _;
    }

    constructor(PWConfig memory _pwconfig) {
        uint _dec = _pwconfig.decimals;

        require(
            _dec > 0 &&
            _pwconfig.frontrunth > 0 && 
            _pwconfig.volatilityth > _pwconfig.frontrunth &&
            _pwconfig.emergencyth > _pwconfig.volatilityth,
            "Error: wrong config parameters. Check th params and decimals"
        );
        // require(msg.sender != _pwconfig.admin, "Error: deployer cannot be an admin");
        pwconfig = _pwconfig;
        statusPause = false;
        round = 0;
    }

    function updPWConfig(PWConfig memory _pwconfig) external onlyAdmin() {
        pwconfig = _pwconfig;
    }

    function updAdmin(address _newAdmin) external override onlyAdmin() {
        pwconfig.admin = _newAdmin;
    }

    function updKeeper(address _newKeeper) external override onlyAdmin() {
        pwconfig.keeper = _newKeeper;
    }

    function updCalibratorProxyRef(address _newCalibrator) external override onlyAdmin() {
        pwconfig.calibrator = _newCalibrator;
    }

    function updVaultRef(address _newVault) external override onlyAdmin() {
        pwconfig.vault = _newVault;
    }

    function setPauseOn() external override onlyKeeper() onlyNotPaused() {
        statusPause = true;
    }

    function setPauseOff() external override onlyAdmin() {
        statusPause = false;
    }

    function getPauseStatus() external override view returns (bool) {
        return statusPause;
    }

    function updPoolRef(address _pool) external override onlyAdmin() {
        pwconfig.pool = _pool;
    }

    function updTokenRef(address _token) external override onlyAdmin() {
        pwconfig.token = _token;
    }

    function updEmergencyTh(uint _newEmergencyth) external override onlyAdmin() {
        pwconfig.emergencyth = _newEmergencyth;
    }

    function updVolatilityTh(uint _newVolatilityth) external override onlyAdmin() {
        pwconfig.volatilityth = _newVolatilityth;
    }

    function updFrontRunProtectionTh(uint _newFrontrunth) external override onlyAdmin() {
        pwconfig.frontrunth = _newFrontrunth;
    }

    function _checkThConditionsOrRaiseException(uint _currPrice, uint _pwPrice) view internal {
        // _currPrice and _pwPrice must be same decimals
        uint n = 10**pwconfig.decimals;
        uint priceDiff = _currPrice > _pwPrice ? n*(_currPrice - _pwPrice)/_currPrice : n*(_pwPrice - _currPrice)/_currPrice;
        require(priceDiff < pwconfig.emergencyth, 
            "Th Emergency Error: price diff exceeds emergency threshold");
        require(priceDiff >= pwconfig.volatilityth, 
            "Th Volatility Error: price diff exceeds volatility threshold");
    }

    // Unused for now but might add the price check given current liquidity in the pool - 
    // for this we'd need additional parameter in callIntervention call
    function _checkThFrontrunOrRaiseException(uint _currPrice, uint _keeperPrice) view internal {
        // _currPrice and _keeperPrice must be same decimals
        uint n = 10**pwconfig.decimals;
        uint priceDiff = _currPrice > _keeperPrice ? n*(_currPrice - _keeperPrice)/_keeperPrice : n*(_keeperPrice - _currPrice)/_keeperPrice;

        require(priceDiff <= pwconfig.frontrunth, 
            "Th FrontRun Error: current price is much higher than keeperPrice");
        require(priceDiff < pwconfig.emergencyth, 
            "Th Emergency Error: current price is much higher than keeperPrice");
    }

    function callIntervention(uint newQuotePrice) external override onlyKeeper() onlyNotPaused() {
        require(newQuotePrice > 0, 'Call Error: newQuotePrice must be higher than 0');

        IUniswapV2Pair pool = IUniswapV2Pair(pwconfig.pool);

        PoolData memory poolData = getPoolData(pool, pwconfig.token);

        _checkThConditionsOrRaiseException(poolData.p1, newQuotePrice);

        if (newQuotePrice == poolData.p1) {
            revert("no price diff");
        }

        // Step-I: what to do - up or down
        PWLibrary.EAction act = PWLibrary.findDirection(poolData.p1, newQuotePrice); //p1 - prev price, pPrice - peg price

        // console.log("computing PWLibrary.computeXLPForDirection");
        // console.log("poolData.g %s", poolData.g);
        // console.log("poolData.u %s", poolData.u);
        // console.log("poolData.p1 %s", poolData.p1);
        // console.log("pPrice %s", pPrice);
        // console.log("isUp?: %s", pPrice > poolData.p1);
        // console.log("poolData.lp, %s", poolData.lp);
        // console.log("pwconfig.decimals, %s", pwconfig.decimals);

        // Step-II: how many LPs
        uint xLPs = PWLibrary.computeXLPForDirection(
            poolData.g, 
            poolData.u, 
            poolData.p1, 
            newQuotePrice,
            act, 
            poolData.lp,
            pwconfig.decimals
        );

        // console.log("xLPs, %s", xLPs);
        // console.log("pwconfig.vault, %s", pwconfig.vault);

        // Step-II: execute:
        pool.transferFrom(pwconfig.vault, address(this), xLPs);
        pool.approve(address(pwconfig.calibrator), xLPs);

        ICalibratorProxy calibrator = ICalibratorProxy(pwconfig.calibrator);

        if (act == PWLibrary.EAction.Up) {
            calibrator.calibratePurelyViaPercentOfLPs_UP(
                pool,
                xLPs,
                1,
                1,
                pwconfig.vault
            );
        } else if (act == PWLibrary.EAction.Down) {
            calibrator.calibratePurelyViaPercentOfLPs_DOWN(
                pool,
                xLPs,
                1,
                1,
                pwconfig.vault
            );
        } else {
            revert("invalid pw action");
        }
    }
    
    function getLastRoundNumber() external override view onlyKeeper() returns (uint) {
        return round;
    }
    
    function getPoolData(IUniswapV2Pair _pool, address _tokenGRef) public view onlyKeeper() returns (PoolData memory) {
        (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        ) = _pool.getReserves();
        
        IERC20 tokenG = IERC20(_pool.token0() == _tokenGRef ? _pool.token0() : _pool.token1());
        IERC20 tokenU = IERC20(!(_pool.token0() == _tokenGRef) ? _pool.token0() : _pool.token1());
        
        uint decimalsG = uint(tokenG.decimals());
        uint decimalsU = uint(tokenU.decimals());
        
        uint n = 10**pwconfig.decimals;
        
        uint g = n*uint(_pool.token0() == _tokenGRef ? reserve0 : reserve1)/(10**decimalsG);
        uint u = n*uint(!(_pool.token0() == _tokenGRef) ? reserve0 : reserve1)/(10**decimalsU);
        
        return PoolData(
            g,
            u,
            n*u/g,
            _pool.totalSupply()
        );
    }

    function getPWConfig() external override view onlyKeeper() returns (PWConfig memory) {
        return pwconfig;
    }
}
