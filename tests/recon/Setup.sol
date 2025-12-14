// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.0;

// Chimera deps
import {BaseSetup} from "@chimera/BaseSetup.sol";
import {vm} from "@chimera/Hevm.sol";
import {Vm} from "forge-std/src/Vm.sol";

// Managers
import {ActorManager} from "@recon/ActorManager.sol";
import {AssetManager} from "@recon/AssetManager.sol";

// Helpers
import {Utils} from "@recon/Utils.sol";

// Your deps
import "src/protocol/curves/LinearCurve.sol";
import "src/protocol/curves/OffsetProgressiveCurve.sol";
import "src/protocol/curves/ProgressiveCurve.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "src/external/curve/VotingEscrow.sol";
import {ERC20Mock} from "tests/mocks/ERC20Mock.sol";

/// @dev Test harness to expose internal VotingEscrow initializer function
contract VotingEscrowHarness is VotingEscrow {
    function initialize(address admin, address tokenAddress, uint256 minTime) external initializer {
        __VotingEscrow_init(admin, tokenAddress, minTime);
    }
}

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils {
    LinearCurve linearCurve;
    OffsetProgressiveCurve offsetProgressiveCurve;
    ProgressiveCurve progressiveCurve;
    VotingEscrow votingEscrow;
    ERC20Mock token;

    /// === Setup === ///
    /// This contains all calls to be performed in the tester constructor, both for Echidna and Foundry
    function setup() internal virtual override {
        token = new ERC20Mock("Test Token", "TEST", 18);

        VotingEscrowHarness votingEscrowImpl = new VotingEscrowHarness();
        TransparentUpgradeableProxy votingEscrowProxy = new TransparentUpgradeableProxy(
            address(votingEscrowImpl),
            address(this),
            abi.encodeWithSelector(VotingEscrowHarness.initialize.selector, address(this), address(token), 2 weeks)
        );
        votingEscrow = VotingEscrow(address(votingEscrowProxy));
        votingEscrow.add_to_whitelist(address(this));

        LinearCurve linearCurveImpl = new LinearCurve();
        TransparentUpgradeableProxy linearCurveProxy = new TransparentUpgradeableProxy(
            address(linearCurveImpl),
            address(this),
            abi.encodeWithSelector(LinearCurve.initialize.selector, "Linear Curve")
        );
        linearCurve = LinearCurve(address(linearCurveProxy));

        OffsetProgressiveCurve offsetProgressiveCurveImpl = new OffsetProgressiveCurve();
        TransparentUpgradeableProxy offsetProgressiveCurveProxy = new TransparentUpgradeableProxy(
            address(offsetProgressiveCurveImpl),
            address(this),
            abi.encodeWithSelector(
                OffsetProgressiveCurve.initialize.selector,
                "Offset Progressive Curve",
                2e18, // SLOPE
                5e17 // OFFSET
            )
        );
        offsetProgressiveCurve = OffsetProgressiveCurve(address(offsetProgressiveCurveProxy));

        ProgressiveCurve progressiveCurveImpl = new ProgressiveCurve();
        TransparentUpgradeableProxy progressiveCurveProxy = new TransparentUpgradeableProxy(
            address(progressiveCurveImpl),
            address(this),
            abi.encodeWithSelector(ProgressiveCurve.initialize.selector, "Progressive Curve", 2e18)
        );
        progressiveCurve = ProgressiveCurve(address(progressiveCurveProxy));
    }

    /// === MODIFIERS === ///
    /// Prank admin and actor

    modifier asAdmin {
        vm.prank(address(this));
        _;
    }

    modifier asActor {
        vm.prank(address(_getActor()));
        _;
    }
}
