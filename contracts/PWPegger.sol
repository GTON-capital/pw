//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./interfaces/IPWPegger.sol";
import "./interfaces/ICalibratorProxy.sol";
import "./interfaces/lib/PWConfig.sol";
import "./interfaces/dependencies/IEACAggregatorProxy.sol";
import "./interfaces/dependencies/IERC20.sol";
import "./interfaces/dependencies/IUniswapV2Pair.sol";

import "./libraries/PWLibrary.sol";


enum EAction {
    Up,
    Down
}

struct PoolData {
    uint g;
    uint u; 
    uint p1; 
    uint lp;
}

contract PWPegger is IPWPegger {
    PWConfig private pwconfig;
    bool statusPause;
    uint round;

    modifier onlyAdmin() {
        require(msg.sender == pwconfig.admin, "Error: must be admin EOA or multisig only");
        _;
    }

    modifier onlyKeeper() {
        require(msg.sender == pwconfig.admin || msg.sender == pwconfig.keeper, 
            "Error: must be admin or keeper EOA/multisig only");
        _;
    }

    modifier onlyNotPaused() {
        require(!statusPause, "PWPeggerMock in on Pause now");
        _;
    }

    constructor(PWConfig memory _pwconfig) {
        uint _dec = _pwconfig.decimals;
        require(
            _dec > 0 && (
                _pwconfig.frontrunth % _dec +
                _pwconfig.volatilityth % _dec +
                _pwconfig.emergencyth % _dec == 0
            ) &&
            _pwconfig.frontrunth > 0 && 
            _pwconfig.volatilityth > _pwconfig.frontrunth &&
            _pwconfig.emergencyth > _pwconfig.volatilityth,
            "Error: wrong config parameters. Check th params and decimals"
            );
        require(msg.sender != _pwconfig.admin, "Error: deployer cannot be an admin");
        pwconfig = _pwconfig;
        statusPause = false;
        round = 0;
    }

    function updAdmin(address _newAdmin) external override onlyAdmin() {
        pwconfig.admin = _newAdmin;
    }

    function updKeeper(address _newKeeper) external override onlyAdmin() {
        pwconfig.keeper = _newKeeper;
    }

    function updPathwayDONRef(address _newPwpegdonRef) external override onlyAdmin() {
        pwconfig.pwpegdonRef = _newPwpegdonRef;
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
        if (_currPrice >= _pwPrice) {
            require(_currPrice - _pwPrice < pwconfig.emergencyth, 
                "Th Emergency Error: current price is much higher than pwPrice");
            require(_currPrice - _pwPrice >= pwconfig.volatilityth, 
                "Th Volatility Error: current price is not enough higher than pwPrice");
        } else {
            require(_pwPrice - _currPrice < pwconfig.emergencyth, 
                "Th Emergency Error: pwPrice price is much higher than current");
            require(_pwPrice - _currPrice >= pwconfig.volatilityth, 
                "Th Volatility Error: pwPrice price is not enough higher than current");
        }
    }

    function _checkThFrontrunOrRaiseException(uint _currPrice, uint _keeperPrice) view internal {
        // additional logic to prevent frontrun attack can be added here: VRF check as an example
        if (_currPrice >= _keeperPrice) {
            require(_currPrice - _keeperPrice <= pwconfig.frontrunth,
                "Th FrontRun Error: current price is much higher than keeperPrice");
        } else {
            require(_keeperPrice - _currPrice <= pwconfig.emergencyth, 
                "Th Emergency Error: current price is much higher than keeperPrice");
        }
    }

    // those functions are reading and convert data to the correct decimals for price data
    function _readDONPrice(address _refDON) view internal returns (uint) {
        IEACAggregatorProxy priceFeed = IEACAggregatorProxy(_refDON);
        (            
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        uint decimals = priceFeed.decimals();
        require(decimals >= 0 && answer > 0, 'DON Error: price data and decimals must be higher than 0');
        uint n = 10**pwconfig.decimals;
        uint d = 10**decimals;
        return (uint(answer)*n/d);
    }

    function _computeXLPProxy(uint _g, uint _u, uint _p1, uint _pG2, EAction _type, uint _lpsupply) view internal returns (uint) {
        uint n = 10*pwconfig.decimals;
        uint pRatio;

        if (_type == EAction.Up) {
            pRatio = (n - _p1*n/_pG2)/n;
        } else {
            uint p1 = n*_g/_u;
            uint p2 = n/_pG2;
            pRatio = (n - p1*n/p2)/n;
        }
        return PWLibrary.computeXLP(_g, pRatio, _lpsupply, pwconfig.decimals);
    }

    function _preparePWData(IUniswapV2Pair _pool, address _tokenGRef) view internal returns (PoolData memory) {
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
            _pool.totalSupply());
    }

    function callIntervention(uint _keeperCurrentPrice) external override onlyKeeper() onlyNotPaused() {
        require(_keeperCurrentPrice > 0, 'Call Error: _keeperCurrentPrice must be higher than 0');

        IUniswapV2Pair pool = IUniswapV2Pair(pwconfig.pool);
        uint pPrice = _readDONPrice(pwconfig.pwpegdonRef);

        PoolData memory poolData = _preparePWData(pool, pwconfig.token);

        _checkThConditionsOrRaiseException(poolData.p1, pPrice);
        _checkThFrontrunOrRaiseException(poolData.p1, _keeperCurrentPrice);


        // Step-I: what to do - up or down
        EAction act = pPrice > poolData.p1 ? EAction.Up : EAction.Down;

        // Step-II: how many LPs
        
        uint xLPs = _computeXLPProxy(
            poolData.g, 
            poolData.u, 
            poolData.p1, 
            pPrice,
            act, 
            poolData.lp
        );

        // Step-II: execute:
        
        pool.transferFrom(pwconfig.vault, address(this), xLPs);
        pool.approve(address(pwconfig.calibrator), xLPs);

        ICalibratorProxy calibrator = ICalibratorProxy(pwconfig.calibrator);

        if (act == EAction.Up) {
            calibrator.calibratePurelyViaPercentOfLPs_UP(
                pool,
                xLPs,
                1,
                1,
                pwconfig.vault
            );
        } else {
            calibrator.calibratePurelyViaPercentOfLPs_DOWN(
                pool,
                xLPs,
                1,
                1,
                pwconfig.vault
            );
        }
    }

    function getPWConfig() external override view returns (PWConfig memory) {
        return pwconfig;
    }

    function getLastRoundNumber() external override view returns (uint) {
        return round;
    }
}
