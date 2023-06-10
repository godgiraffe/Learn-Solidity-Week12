// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {MyErc20} from "src/MyErc20.sol";

import {Unitroller} from "lib/compound-protocol/contracts/Unitroller.sol"; // proxy
import {Comptroller} from "lib/compound-protocol/contracts/Comptroller.sol"; // implementation
import {ComptrollerInterface} from "lib/compound-protocol/contracts/ComptrollerInterface.sol";

import {SimplePriceOracle} from "lib/compound-protocol/contracts/SimplePriceOracle.sol";
import {CToken} from "lib/compound-protocol/contracts/CToken.sol";

import {WhitePaperInterestRateModel} from "lib/compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegator} from "lib/compound-protocol/contracts/CErc20Delegator.sol"; // proxy
import {CErc20Delegate} from "lib/compound-protocol/contracts/CErc20Delegate.sol"; // implementation

contract CompoundTest is Test {
    /**
    * 1. 撰寫一個 Foundry 的 Script，該 Script 要能夠部署一個 CErc20Delegator(CErc20Delegator.sol，以下簡稱 cERC20)
         一個 Unitroller(Unitroller.sol) 以及他們的 Implementation 合約和合約初始化時相關必要合約。請遵循以下細節：
    *    - [x] cERC20 的 decimals 皆為 18
    *    - [x] 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
    *    - [x] 使用 SimplePriceOracle 作為 Oracle
    *    - [x] 使用 WhitePaperInterestRateModel 作為利率模型，利率模型合約中的借貸利率設定為 0%
    *    - [x] 初始 exchangeRate 為 1:1
   */

    /// ===== Compound =====
    Comptroller public _comptroller;
    MyErc20 public _underlyingA;
    MyErc20 public _underlyingB;
    CErc20Delegator public _cTokenA;
    CErc20Delegator public _cTokenB;
    uint8 public _decimals;
    struct RateInfo {
        uint baseRatePerYear;
        uint multiplierPerYear;
    }
    RateInfo public _rateInfoA;
    RateInfo public _rateInfoB;

    /// ===== User =====
    address public _admin;
    address public _user1;
    address public _user2;

    function setUp() public {
        _admin = makeAddr("admin");
        _user1 = makeAddr("user1");
        _user2 = makeAddr("user2");

        vm.startPrank(_admin);

        _comptroller = new Comptroller();
        _decimals = 18;
        _underlyingA = create_ERC20("LL", "LL", _decimals);
        _rateInfoA = RateInfo(0, 0);
        _cTokenA = create_cERC20(
            _comptroller,
            _underlyingA,
            _rateInfoA,
            1e18,
            _decimals,
            "0x0"
        );
        _comptroller._supportMarket(CToken(address(_cTokenA)));
        vm.stopPrank();
    }

    /*
     * 2. 讓 User1 mint/redeem cERC20，請透過 Foundry test case (你可以繼承上題的 script 或是用其他方式實現部署) 實現以下場景：
     *    - [x] User1 使用 100 顆（100 * 10^18） ERC20 去 mint 出 100 cERC20 token
     *    - [x] 再用 100 cERC20 token redeem 回 100 顆 ERC20
     */

    function testMint() public {
        vm.startPrank(_user1);
        uint amount = 100 * 10 ** _decimals;
        // mint underlying token
        assertEq(_underlyingA.balanceOf(_user1), 0);
        assertEq(_cTokenA.balanceOf(_user1), 0);
        _underlyingA.mint(amount);
        assertEq(_underlyingA.balanceOf(_user1), amount);
        assertEq(_cTokenA.balanceOf(_user1), 0);

        // mint cToken
        _underlyingA.approve(address(_cTokenA), amount);
        _cTokenA.mint(amount);
        assertEq(_underlyingA.balanceOf(_user1), 0);
        assertEq(_cTokenA.balanceOf(_user1), amount);

        // redeem cToken to underlying token
        _cTokenA.approve(address(_cTokenA), amount);
        _cTokenA.redeem(amount);
        assertEq(_underlyingA.balanceOf(_user1), amount);
        assertEq(_cTokenA.balanceOf(_user1), 0);
        vm.stopPrank();
    }

    /**
     * 3. 讓 User1 borrow/repay
     *    - [ ] 部署第二份 cERC20 合約，以下稱它們的 underlying tokens 為 token A 與 token B。
     *    - [ ] 在 Oracle 中設定一顆 token A 的價格為 $1，一顆 token B 的價格為 $100
     *    - [ ] Token B 的 collateral factor 為 50%
     *    - [ ] User1 使用 1 顆 token B 來 mint cToken
     *    - [ ] User1 使用 token B 作為抵押品來借出 50 顆 token A
     */
    // function testBorrowAndRepay() public {
    //     vm.startPrank(_user1);
    //     // deploy cTokenB
    //     vm.stopPrank();
    // }

    //////////////////////////////////
    // helper functions
    //////////////////////////////////

    function create_ERC20(
        string memory name,
        string memory symbol,
        uint8 decimals
    ) public returns (MyErc20) {
        MyErc20 _erc20 = new MyErc20(name, symbol, decimals);
        return _erc20;
    }

    function create_cERC20(
        Comptroller comptroller,
        MyErc20 underlyingToken,
        RateInfo memory rateInfo,
        uint initialExchangeRateMantissa,
        uint8 decimals,
        bytes memory becomeImplementationData
    ) public returns (CErc20Delegator) {
        // depoly rate model & set rate
        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(
                rateInfo.baseRatePerYear,
                rateInfo.multiplierPerYear
            );

        CErc20Delegate cERC20Delegate = new CErc20Delegate();
        CErc20Delegator cERC20 = new CErc20Delegator(
            address(underlyingToken),
            comptroller,
            interestRateModel,
            initialExchangeRateMantissa,
            string.concat("c", underlyingToken.name()),
            string.concat("c", underlyingToken.symbol()),
            decimals,
            payable(msg.sender),
            address(cERC20Delegate),
            becomeImplementationData
        );

        Unitroller unitroller = new Unitroller();
        // set unitroller's implementation to comptroller
        unitroller._setPendingImplementation(address(comptroller));
        // _become 裡面會 1. 驗證 msg.sender 是否為 admin, 2. 執行 _acceptImplementation
        // 有打算把 _become 裡的東西，拆出來這邊執行，但是失敗 XD
        // 發現是 https://github.com/foundry-rs/foundry/issues/4556 問題
        // 但先搞作業ㄅ
        comptroller._become(unitroller);

        // depoly price oracle
        SimplePriceOracle priceOracle = new SimplePriceOracle();
        // set price oracle to comptroller
        // 注意：function 是要對 implementation contract 執行，不是對 proxy contract 執行
        // 設定 Orace price
        comptroller._setPriceOracle(priceOracle);

        return cERC20;
    }
}
