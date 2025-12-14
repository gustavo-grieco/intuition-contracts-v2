// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

import {BaseTargetFunctions} from "@chimera/BaseTargetFunctions.sol";
import {BeforeAfter} from "../BeforeAfter.sol";
import {Properties} from "../Properties.sol";
// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

import "src/protocol/curves/LinearCurve.sol";
import {IBaseCurve} from "src/interfaces/IBaseCurve.sol";

abstract contract LinearCurveTargets is
    BaseTargetFunctions,
    Properties
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///

    /*function linearCurve_initialize(string memory _name) public asActor {
        linearCurve.initialize(_name);
    }

    function linearCurve_convertToShares(uint256 assets, uint256 totalAssets, uint256 totalShares) public {
        precondition(totalAssets > 0 && totalShares > 0);
        assets = between(assets, 1, type(uint128).max);
        totalAssets = between(totalAssets, 1, type(uint128).max);
        totalShares = between(totalShares, 1, type(uint128).max);

        uint256 shares = linearCurve.convertToShares(assets, totalAssets, totalShares);
        eq(shares, assets * totalShares / totalAssets, "linearCurve_convertToShares: mismatch");
    }

    function linearCurve_convertToAssets(uint256 shares, uint256 totalShares, uint256 totalAssets) public {
        precondition(totalShares > 0 && totalAssets > 0);
        shares = between(shares, 1, type(uint128).max);
        totalShares = between(totalShares, shares, type(uint128).max);
        totalAssets = between(totalAssets, 1, type(uint128).max);

        uint256 assets = linearCurve.convertToAssets(shares, totalShares, totalAssets);
        eq(assets, shares * totalAssets / totalShares, "linearCurve_convertToAssets: mismatch");
    }

    function linearCurve_convertToAssets_reverts(uint256 totalShares, uint256 totalAssets) public {
        totalShares = between(totalShares, 0, type(uint128).max);
        totalAssets = between(totalAssets, 0, type(uint128).max);

        uint256 shares = totalShares + 1; // strictly greater

        try linearCurve.convertToAssets(shares, totalShares, totalAssets) {
            t(false, "linearCurve_convertToAssets_reverts: should have reverted");
        } catch (bytes memory lowLevelData) {
            bytes4 selector = bytes4(lowLevelData);
            eq(
                uint256(uint32(selector)),
                uint256(uint32(IBaseCurve.BaseCurve_SharesExceedTotalShares.selector)),
                "linearCurve_convertToAssets_reverts: wrong revert selector"
            );
        }
    }*/
}
