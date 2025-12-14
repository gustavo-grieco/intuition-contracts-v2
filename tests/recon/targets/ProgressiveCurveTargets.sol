// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/protocol/curves/ProgressiveCurve.sol";
import {IBaseCurve} from "src/interfaces/IBaseCurve.sol";
import {UD60x18, unwrap} from "@prb/math/src/UD60x18.sol";

abstract contract ProgressiveCurveTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    /*function progressiveCurve_initialize(string memory _name, uint256 slope18) public asActor {
        progressiveCurve.initialize(_name, slope18);
    }*/

    function progressiveCurve_previewDeposit(uint256 assetMultiplier, uint256 totalShares) public {
        // Bound totalShares to reasonable range
        totalShares = between(totalShares, 0, 1e19);

        // Bound asset multiplier to create proportional assets
        assetMultiplier = between(assetMultiplier, 1, 1000);

        // Calculate assets that will definitely return non-zero shares
        uint256 assets;
        if (totalShares == 0) {
            assets = assetMultiplier * 1e18; // When no shares exist, any assets work
        } else {
            // Need assets large enough that sqrt(s^2 + 2a/m) > s
            // This means 2a/m > 2s (approximately), so a > s*m
            uint256 currentPrice = progressiveCurve.currentPrice(totalShares, 0);
            assets = (currentPrice * assetMultiplier) / 100; // Assets as percentage of current price
            assets = assets > 0 ? assets : 1;
        }

        uint256 shares = progressiveCurve.previewDeposit(assets, 0, totalShares);
        gt(shares, 0, "progressiveCurve_previewDeposit: shares should be > 0");
    }

    function progressiveCurve_currentPrice(uint256 totalShares) public {
        totalShares = between(totalShares, 0, progressiveCurve.maxShares());

        uint256 price = progressiveCurve.currentPrice(totalShares, 0);

        // Read slope
        uint256 slope = unwrap(progressiveCurve.SLOPE());

        // wad-mul: (SLOPE * totalShares) / 1e18
        uint256 expectedPrice = (slope * totalShares) / 1e18;
        eq(price, expectedPrice, "progressiveCurve_currentPrice: mismatch");
    }
}
