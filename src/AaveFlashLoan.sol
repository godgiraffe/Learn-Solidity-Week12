pragma solidity 0.8.19;

import "forge-std/Test.sol";

import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IFlashLoanSimpleReceiver, IPoolAddressesProvider, IPool } from "lib/aave-v3-core/contracts/flashloan/interfaces/IFlashLoanSimpleReceiver.sol";

import {CToken} from "lib/compound-protocol/contracts/CToken.sol";
import {CErc20Delegator} from "lib/compound-protocol/contracts/CErc20Delegator.sol"; // proxy
import {CTokenInterface} from "lib/compound-protocol/contracts/CTokenInterfaces.sol";

import { ISwapRouter } from '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import { SwapRouter } from '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

// TODO: Inherit IFlashLoanSimpleReceiver
contract AaveFlashLoan is IFlashLoanSimpleReceiver {
    address constant POOL_ADDRESSES_PROVIDER = 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e;
    SwapRouter swapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function execute(address asset, uint256 amount, address to, bytes calldata params) external {
        // TODO

        IERC20(asset).approve(msg.sender, amount);   // msg.sender 嗎?
        // 0.05% fee
        // function flashLoanSimple(address receiverAddress, address asset, uint256 amount, bytes calldata params, uint16 referralCode)
        POOL().flashLoanSimple(
            address(this),
            asset,
            amount,
            params,
            0
        );
    }

    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        // TODO
        // 確認有借到錢 - 1312 500000
        console.log('g1', IERC20(asset).balanceOf(address(this)));
        IERC20(asset).approve(msg.sender, amount + premium); // msg.sender = aave pool, 這邊先 approve, pool 自己會執行還錢
        (address liquidatedBorrower, address liquidationCToken, uint liquidationAmount, address cTokenCollateral, address liquidator) = abi.decode(params, (address, address, uint, address, address));
        // 執行清算 - liquidationAmount = 1250 000000
        IERC20(asset).approve(liquidationCToken, liquidationAmount);
        require(CErc20Delegator(payable(liquidationCToken)).liquidateBorrow(liquidatedBorrower, liquidationAmount, CTokenInterface(cTokenCollateral)) == 0, "liquidateBorrow failed");
        // 清算完，拿到的清算獎勵為 cUNI，先將其換回 UNI
        uint cTokenCollateralBalance =  CTokenInterface(cTokenCollateral).balanceOf(address(this));
        CErc20Delegator(payable(cTokenCollateral)).approve(cTokenCollateral, cTokenCollateralBalance);
        CErc20Delegator(payable(cTokenCollateral)).redeem(cTokenCollateralBalance);

        // 把 UNI swap to USDC, 才能還 aave 錢
        address UNI_ADDRESS = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
        address USDC_ADDRESS = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint uniAmount = IERC20(UNI_ADDRESS).balanceOf(address(this));
        IERC20(UNI_ADDRESS).approve(address(swapRouter), uniAmount);
        ISwapRouter.ExactInputSingleParams memory swapParams =
          ISwapRouter.ExactInputSingleParams({
            tokenIn: UNI_ADDRESS,
            tokenOut: USDC_ADDRESS,
            fee: 3000, // 0.3%
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: uniAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
          });

        // The call to `exactInputSingle` executes the swap.
        uint256 amountOut = swapRouter.exactInputSingle(swapParams);


        // 還完 aave, 還剩多少錢，打回去給清算者
        uint balance = IERC20(asset).balanceOf(address(this));
        console.log('profit', balance);
        IERC20(asset).transfer(liquidator, balance);
        return true;
    }



    function ADDRESSES_PROVIDER() public view returns (IPoolAddressesProvider) {
        return IPoolAddressesProvider(POOL_ADDRESSES_PROVIDER);
    }

    function POOL() public view returns (IPool) {
        return IPool(ADDRESSES_PROVIDER().getPool());
    }
}
