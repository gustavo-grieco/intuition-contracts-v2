// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/protocol/curves/OffsetProgressiveCurve.sol";
import {IBaseCurve} from "src/interfaces/IBaseCurve.sol";
import {UD60x18, unwrap} from "@prb/math/src/UD60x18.sol";

abstract contract OffsetProgressiveCurveTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    /*function offsetProgressiveCurve_initialize(string memory _name, uint256 slope18, uint256 offset18) public asActor {
        offsetProgressiveCurve.initialize(_name, slope18, offset18);
    }*/

    function checkApproxEqAbs(uint256 a, uint256 b, uint256 maxDelta, string memory reason) internal {
        uint256 delta = a > b ? a - b : b - a;
        lte(delta, maxDelta, reason);
    }

    function offsetProgressiveCurve_previewDeposit(uint256 assetMultiplier, uint256 totalShares) public {
        totalShares = between(totalShares, 0, 1e19);
        assetMultiplier = between(assetMultiplier, 1, 1000);

        uint256 assets;
        if (totalShares == 0) {
            assets = assetMultiplier * 1e18;
        } else {
            uint256 currentPrice = offsetProgressiveCurve.currentPrice(totalShares, 0);
            assets = (currentPrice * assetMultiplier) / 100;
            assets = assets > 0 ? assets : 1;
        }

        uint256 shares = offsetProgressiveCurve.previewDeposit(assets, 0, totalShares);
        gt(shares, 0, "offsetProgressiveCurve_previewDeposit: shares should be > 0");
    }

    function offsetProgressiveCurve_currentPrice_linearityProperty(uint256 totalShares, uint256 delta) public {
        uint256 maxShares = offsetProgressiveCurve.maxShares();
        totalShares = between(totalShares, 0, maxShares - 1e18);
        delta = between(delta, 1, 1e18);

        if (totalShares + delta > maxShares) {
            delta = maxShares - totalShares;
        }

        uint256 price1 = offsetProgressiveCurve.currentPrice(totalShares, 0);
        uint256 price2 = offsetProgressiveCurve.currentPrice(totalShares + delta, 0);

        uint256 slope = unwrap(offsetProgressiveCurve.SLOPE());
        uint256 expectedIncrease = (slope * delta) / 1e18;
        uint256 actualIncrease = price2 - price1;

        checkApproxEqAbs(actualIncrease, expectedIncrease, 1, "Price should increase linearly by SLOPE * delta");
    }

    function offsetProgressiveCurve_currentPrice_offsetEffect(uint256 totalShares) public {
        totalShares = between(totalShares, 0, offsetProgressiveCurve.maxShares());

        uint256 price = offsetProgressiveCurve.currentPrice(totalShares, 0);
        uint256 priceAtZero = offsetProgressiveCurve.currentPrice(0, 0);

        uint256 slope = unwrap(offsetProgressiveCurve.SLOPE());
        uint256 offset = unwrap(offsetProgressiveCurve.OFFSET());

        uint256 expectedDifference = (slope * totalShares) / 1e18;
        uint256 actualDifference = price - priceAtZero;

        checkApproxEqAbs(actualDifference, expectedDifference, 1, "Price difference should equal shares * slope");

        uint256 expectedPriceAtZero = (offset * slope) / 1e18;
        eq(priceAtZero, expectedPriceAtZero, "Price at zero should equal offset * slope");
    }

    function offsetProgressiveCurve_currentPrice_integrationWithMint(uint256 sharesToMint) public {
        sharesToMint = between(sharesToMint, 1e15, 1e18);
        uint256 totalShares = 10e18;

        uint256 price1 = offsetProgressiveCurve.currentPrice(totalShares, 0);
        uint256 price2 = offsetProgressiveCurve.currentPrice(totalShares + sharesToMint, 0);
        uint256 averagePrice = (price1 + price2) / 2;
        uint256 expectedCost = (averagePrice * sharesToMint) / 1e18;

        uint256 actualCost = offsetProgressiveCurve.previewMint(sharesToMint, totalShares, 0);

        uint256 tolerance = actualCost / 1000;
        checkApproxEqAbs(actualCost, expectedCost, tolerance, "Mint cost should match integral of price curve");
    }

    function offsetProgressiveCurve_currentPrice_monotonicIncrease(uint256 shares1, uint256 shares2) public {
        shares1 = between(shares1, 0, offsetProgressiveCurve.maxShares());
        shares2 = between(shares2, 0, offsetProgressiveCurve.maxShares());

        uint256 price1 = offsetProgressiveCurve.currentPrice(shares1, 0);
        uint256 price2 = offsetProgressiveCurve.currentPrice(shares2, 0);

        if (shares1 < shares2) {
            lte(price1, price2, "Price should be less than or equal when supply is lower");
            if (shares2 - shares1 >= 1e18) {
                lt(price1, price2, "Price should strictly increase for significant supply differences");
            }
        } else if (shares1 > shares2) {
            gte(price1, price2, "Price should be greater than or equal when supply is higher");
            if (shares1 - shares2 >= 1e18) {
                gt(price1, price2, "Price should strictly decrease for significant supply differences");
            }
        } else {
            eq(price1, price2, "Same supply should have same price");
        }
    }
}
