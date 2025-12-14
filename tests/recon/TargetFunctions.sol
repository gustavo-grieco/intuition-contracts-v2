// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {vm} from "@chimera/Hevm.sol";

// Helpers
import {Panic} from "@recon/Panic.sol";

// Targets
// NOTE: Always import and apply them in alphabetical order, so much easier to debug!
import { AdminTargets } from "./targets/AdminTargets.sol";
import { DoomsdayTargets } from "./targets/DoomsdayTargets.sol";
import { LinearCurveTargets } from "./targets/LinearCurveTargets.sol";
import { ManagersTargets } from "./targets/ManagersTargets.sol";
import { OffsetProgressiveCurveTargets } from "./targets/OffsetProgressiveCurveTargets.sol";
import { ProgressiveCurveTargets } from "./targets/ProgressiveCurveTargets.sol";

abstract contract TargetFunctions is
    AdminTargets,
    DoomsdayTargets,
    LinearCurveTargets,
    ManagersTargets,
    OffsetProgressiveCurveTargets,
    ProgressiveCurveTargets
{
    /// CUSTOM TARGET FUNCTIONS - Add your own target functions here ///


    /// AUTO GENERATED TARGET FUNCTIONS - WARNING: DO NOT DELETE OR MODIFY THIS LINE ///
}
