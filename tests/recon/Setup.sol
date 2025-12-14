// SPDX-License-Identifier: GPL-2.0
pragma solidity ^0.8.29;

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
import {VotingEscrowHarness} from "tests/mocks/VotingEscrowHarness.sol";

import { MultiVault } from "src/protocol/MultiVault.sol";
import { AtomWallet } from "src/protocol/wallet/AtomWallet.sol";
import { AtomWalletFactory } from "src/protocol/wallet/AtomWalletFactory.sol";
import { TrustBonding } from "src/protocol/emissions/TrustBonding.sol";
import { SatelliteEmissionsController } from "src/protocol/emissions/SatelliteEmissionsController.sol";
import { BondingCurveRegistry } from "src/protocol/curves/BondingCurveRegistry.sol";
import { Trust } from "src/Trust.sol";
import { WrappedTrust } from "src/WrappedTrust.sol";
import { UpgradeableBeacon } from "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";
import { GeneralConfig, AtomConfig, TripleConfig, WalletConfig, VaultFees, BondingCurveConfig } from "src/interfaces/IMultiVaultCore.sol";
import { MetaERC20DispatchInit, FinalityState } from "src/interfaces/IMetaLayer.sol";
import { CoreEmissionsControllerInit } from "src/interfaces/ICoreEmissionsController.sol";
import { MetalayerRouterMock, IIGPMock, MetaERC20HubOrSpokeMock } from "tests/mocks/MetalayerRouterMock.sol";

abstract contract Setup is BaseSetup, ActorManager, AssetManager, Utils {
    LinearCurve linearCurve;
    OffsetProgressiveCurve offsetProgressiveCurve;
    ProgressiveCurve progressiveCurve;
    VotingEscrowHarness votingEscrow;
    ERC20Mock token;

    // MultiVault System
    MultiVault multiVault;
    AtomWalletFactory atomWalletFactory;
    TrustBonding trustBonding;
    SatelliteEmissionsController satelliteEmissionsController;
    BondingCurveRegistry curveRegistry;
    Trust trust;
    WrappedTrust wrappedTrust;
    UpgradeableBeacon atomWalletBeacon;

    // Constants
    uint256 internal constant PROGRESSIVE_CURVE_SLOPE = 2e18;
    uint256 internal constant OFFSET_PROGRESSIVE_CURVE_SLOPE = 2e18;
    uint256 internal constant OFFSET_PROGRESSIVE_CURVE_OFFSET = 5e17;
    uint256 internal constant EMISSIONS_CONTROLLER_EPOCH_LENGTH = 14 days;
    uint256 internal constant EMISSIONS_CONTROLLER_EMISSIONS_PER_EPOCH = 1000 * 1e18;
    uint256 internal constant EMISSIONS_CONTROLLER_CLIFF = 26;
    uint256 internal constant EMISSIONS_CONTROLLER_REDUCTION_BP = 1000;

    uint256 internal constant TRUST_BONDING_EPOCH_LENGTH = 14 days;
    uint256 internal constant TRUST_BONDING_SYSTEM_UTILIZATION_LOWER_BOUND = 5000;
    uint256 internal constant TRUST_BONDING_PERSONAL_UTILIZATION_LOWER_BOUND = 3000;

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
        votingEscrow = VotingEscrowHarness(address(votingEscrowProxy));
        votingEscrow.add_to_whitelist(address(this));

        // Deploy Trust & WrappedTrust
        Trust trustImpl = new Trust();
        TransparentUpgradeableProxy trustProxy = new TransparentUpgradeableProxy(address(trustImpl), address(this), "");
        trust = Trust(address(trustProxy));
        trust.init();
        trust.reinitialize(address(this), address(this)); // admin, controller

        wrappedTrust = new WrappedTrust();

        // Deploy MultiVault
        MultiVault multiVaultImpl = new MultiVault();
        TransparentUpgradeableProxy multiVaultProxy = new TransparentUpgradeableProxy(address(multiVaultImpl), address(this), "");
        multiVault = MultiVault(address(multiVaultProxy));

        // Deploy AtomWallet
        AtomWallet atomWalletImpl = new AtomWallet();
        atomWalletBeacon = new UpgradeableBeacon(address(atomWalletImpl), address(this));

        AtomWalletFactory atomWalletFactoryImpl = new AtomWalletFactory();
        TransparentUpgradeableProxy atomWalletFactoryProxy = new TransparentUpgradeableProxy(address(atomWalletFactoryImpl), address(this), "");
        atomWalletFactory = AtomWalletFactory(address(atomWalletFactoryProxy));

        // Deploy TrustBonding
        TrustBonding trustBondingImpl = new TrustBonding();
        TransparentUpgradeableProxy trustBondingProxy = new TransparentUpgradeableProxy(address(trustBondingImpl), address(this), "");
        trustBonding = TrustBonding(address(trustBondingProxy));

        // Deploy SatelliteEmissionsController
        SatelliteEmissionsController satelliteEmissionsControllerImpl = new SatelliteEmissionsController();
        TransparentUpgradeableProxy satelliteEmissionsControllerProxy = new TransparentUpgradeableProxy(address(satelliteEmissionsControllerImpl), address(this), "");
        satelliteEmissionsController = SatelliteEmissionsController(payable(satelliteEmissionsControllerProxy));

        // Deploy BondingCurveRegistry
        BondingCurveRegistry bondingCurveRegistryImpl = new BondingCurveRegistry();
        TransparentUpgradeableProxy bondingCurveRegistryProxy = new TransparentUpgradeableProxy(
            address(bondingCurveRegistryImpl),
            address(this),
            abi.encodeWithSelector(BondingCurveRegistry.initialize.selector, address(this))
        );
        curveRegistry = BondingCurveRegistry(address(bondingCurveRegistryProxy));

        // Deploy Curves
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
                OFFSET_PROGRESSIVE_CURVE_SLOPE, // SLOPE
                OFFSET_PROGRESSIVE_CURVE_OFFSET // OFFSET
            )
        );
        offsetProgressiveCurve = OffsetProgressiveCurve(address(offsetProgressiveCurveProxy));

        ProgressiveCurve progressiveCurveImpl = new ProgressiveCurve();
        TransparentUpgradeableProxy progressiveCurveProxy = new TransparentUpgradeableProxy(
            address(progressiveCurveImpl),
            address(this),
            abi.encodeWithSelector(ProgressiveCurve.initialize.selector, "Progressive Curve", PROGRESSIVE_CURVE_SLOPE)
        );
        progressiveCurve = ProgressiveCurve(address(progressiveCurveProxy));

        // Configure Registry
        curveRegistry.addBondingCurve(address(linearCurve));
        curveRegistry.addBondingCurve(address(offsetProgressiveCurve));
        curveRegistry.addBondingCurve(address(progressiveCurve));

        // Configure SatelliteEmissionsController
        IIGPMock IIGP = new IIGPMock();
        MetalayerRouterMock metaERC20Router = new MetalayerRouterMock(address(IIGP));
        MetaERC20HubOrSpokeMock metaERC20HubOrSpoke = new MetaERC20HubOrSpokeMock(address(metaERC20Router));

        satelliteEmissionsController.initialize(
            address(this),
            address(1), // BaseEmissionsController placeholder
            MetaERC20DispatchInit({
                hubOrSpoke: address(metaERC20HubOrSpoke),
                recipientDomain: 1,
                gasLimit: 125_000,
                finalityState: FinalityState.INSTANT
            }),
            CoreEmissionsControllerInit({
                startTimestamp: block.timestamp,
                emissionsLength: EMISSIONS_CONTROLLER_EPOCH_LENGTH,
                emissionsPerEpoch: EMISSIONS_CONTROLLER_EMISSIONS_PER_EPOCH,
                emissionsReductionCliff: EMISSIONS_CONTROLLER_CLIFF,
                emissionsReductionBasisPoints: EMISSIONS_CONTROLLER_REDUCTION_BP
            })
        );
        satelliteEmissionsController.setTrustBonding(address(trustBonding));
        satelliteEmissionsController.grantRole(satelliteEmissionsController.CONTROLLER_ROLE(), address(trustBonding));

        // Initialize AtomWalletFactory
        atomWalletFactory.initialize(address(multiVault));

        // Initialize TrustBonding
        trustBonding.initialize(
            address(this), // owner
            address(this), // timelock
            address(wrappedTrust), // trustToken
            TRUST_BONDING_EPOCH_LENGTH,
            address(satelliteEmissionsController),
            TRUST_BONDING_SYSTEM_UTILIZATION_LOWER_BOUND,
            TRUST_BONDING_PERSONAL_UTILIZATION_LOWER_BOUND
        );
        trustBonding.setMultiVault(address(multiVault));
        trustBonding.add_to_whitelist(address(this)); // Whitelist deployer

        // Initialize MultiVault
        GeneralConfig memory generalConfig = GeneralConfig({
            admin: address(this),
            protocolMultisig: address(this),
            feeDenominator: 10_000,
            trustBonding: address(trustBonding),
            minDeposit: 1e17,
            minShare: 1e6,
            atomDataMaxLength: 1000,
            feeThreshold: 1e18
        });

        AtomConfig memory atomConfig = AtomConfig({
            atomCreationProtocolFee: 1e15,
            atomWalletDepositFee: 100
        });

        TripleConfig memory tripleConfig = TripleConfig({
            tripleCreationProtocolFee: 1e15,
            atomDepositFractionForTriple: 500
        });

        WalletConfig memory walletConfig = WalletConfig({
            entryPoint: 0x4337084D9E255Ff0702461CF8895CE9E3b5Ff108,
            atomWarden: address(1),
            atomWalletBeacon: address(atomWalletBeacon),
            atomWalletFactory: address(atomWalletFactory)
        });

        VaultFees memory vaultFees = VaultFees({
            entryFee: 100,
            exitFee: 100,
            protocolFee: 100
        });

        BondingCurveConfig memory bondingCurveConfig = BondingCurveConfig({
            registry: address(curveRegistry),
            defaultCurveId: 1
        });

        multiVault.initialize(
            generalConfig,
            atomConfig,
            tripleConfig,
            walletConfig,
            vaultFees,
            bondingCurveConfig
        );
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
