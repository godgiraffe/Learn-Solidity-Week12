// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

import {Unitroller} from "lib/compound-protocol/contracts/Unitroller.sol"; // proxy
import {Comptroller} from "lib/compound-protocol/contracts/Comptroller.sol"; // implementation
import {WhitePaperInterestRateModel} from "lib/compound-protocol/contracts/WhitePaperInterestRateModel.sol";
import {CErc20Delegator} from "lib/compound-protocol/contracts/CErc20Delegator.sol"; // proxy
import {CErc20Delegate} from "lib/compound-protocol/contracts/CErc20Delegate.sol"; // implementation

contract Compound is Script {
    address private _ADMIN_ADDR;
    uint private _PRIVATE_KEY = vm.envUint("PRIVATE_KEY");

    function run() external {
        vm.startBroadcast(_PRIVATE_KEY);
        /**
         * 撰寫一個 Foundry 的 Script，該 Script 要能夠部署
         * [x] 一個 CErc20Delegator(CErc20Delegator.sol，以下簡稱 cERC20)
         * [x] 一個 Unitroller(Unitroller.sol)
         * [x] 以及他們的 Implementation 合約和合約初始化時相關必要合約。請遵循以下細節：
         *
         * [x] cERC20 的 decimals 皆為 18
         * [x] 自行部署一個 cERC20 的 underlying ERC20 token，decimals 為 18
         * [x] 使用 SimplePriceOracle 作為 Oracle
         * [x] 使用 WhitePaperInterestRateModel 作為利率模型，利率模型合約中的借貸利率設定為 0%
         * [x] 初始 exchangeRate 為 1:1
         */

        // depoly underlying ERC20 token
        ERC20 underlying = new ERC20("LLToken", "LL"); // 1. address underlying_

        // depoly unitroller and comptroller
        Unitroller unitroller = new Unitroller();
        Comptroller comptroller = new Comptroller(); // 2. ComptrollerInterface comptroller_
        // set comptroller to unitroller
        unitroller._setPendingImplementation(address(comptroller));
        unitroller._acceptImplementation();

        /*
         * WhitePaperInterestRateModel - constructor(uint baseRatePerYear, uint multiplierPerYear)
         * blocksPerYear 預設是 = 2102400 (15秒出一塊)
         * baseRatePerBlock = baseRatePerYear / blocksPerYear;
         * multiplierPerBlock = multiplierPerYear / blocksPerYear;
         */
        // 使用 WhitePaperInterestRateModel 作為利率模型，利率模型合約中的借貸利率設定為 0%
        WhitePaperInterestRateModel interestRateModel = new WhitePaperInterestRateModel(
                0,
                0
            ); // 3. InterestRateModel interestRateModel_

        /**
         * [x] cErc20
         * @notice Construct a new money market
         * [x] @param underlying_ The address of the underlying asset
         * [x] @param comptroller_ The address of the Comptroller
         * [x] @param interestRateModel_ The address of the interest rate model
         * [x] @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
         * [x] @param name_ ERC-20 name of this token
         * [x] @param symbol_ ERC-20 symbol of this token
         * [x] @param decimals_ ERC-20 decimal precision of this token
         * [x] @param admin_ Address of the administrator of this token
         * [x] @param implementation_ The address of the implementation the contract delegates to
         * [x] @param becomeImplementationData The encoded args for becomeImplementation
         *     constructor(
                address underlying_,
                ComptrollerInterface comptroller_,
                InterestRateModel interestRateModel_,
                uint initialExchangeRateMantissa_,
                string memory name_,
                string memory symbol_,
                uint8 decimals_,
                address payable admin_,
                address implementation_,
                bytes memory becomeImplementationData)
         */
        CErc20Delegate cErc20Delegate = new CErc20Delegate(); // 4. address implementation_
        CErc20Delegator cErc20 = new CErc20Delegator(
            address(underlying),
            comptroller,
            interestRateModel,
            1e18,
            "cLL",
            "cLL",
            18,
            payable(msg.sender),
            address(cErc20Delegate),
            ""
        );

        vm.stopBroadcast();
    }
}
