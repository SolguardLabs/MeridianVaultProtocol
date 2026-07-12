// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../../src/access/MeridianRoles.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract MeridianRolesHarness is MeridianRoles {
    uint256 public actionCount;

    constructor(address initialOwner) MeridianRoles(initialOwner) { }

    function ownerAction() external onlyOwner {
        actionCount += 1;
    }

    function keeperAction() external onlyRole(KEEPER_ROLE) {
        actionCount += 1;
    }

    function activeAction() external whenNotPaused {
        actionCount += 1;
    }

    function pausedAction() external whenPaused {
        actionCount += 1;
    }

    function guardedAction(bool callAgain) external nonReentrant {
        if (callAgain) {
            this.guardedAction(false);
        }
        actionCount += 1;
    }
}

contract MeridianRolesTest is TestBase {
    MeridianRolesHarness internal roles;

    address internal constant OWNER = address(0xA11CE);
    address internal constant PENDING_OWNER = address(0xB0B);
    address internal constant ADMIN = address(0xAD11);
    address internal constant KEEPER = address(0xC0FFEE);
    address internal constant GUARDIAN = address(0xCAFE);
    address internal constant OUTSIDER = address(0xD00D);

    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 internal constant KEEPER_ROLE = keccak256("KEEPER_ROLE");
    bytes32 internal constant ALLOCATOR_ROLE = keccak256("ALLOCATOR_ROLE");
    bytes32 internal constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");

    function setUp() public {
        roles = new MeridianRolesHarness(OWNER);
    }

    function testConstructorSetsOwnerAndInitialState() external view {
        assertEq(roles.owner(), OWNER);
        assertEq(roles.pendingOwner(), address(0));
        assertFalse(roles.paused());
        assertTrue(roles.hasRole(roles.DEFAULT_ADMIN_ROLE(), OWNER));
        assertTrue(roles.hasRole(roles.ADMIN_ROLE(), OWNER));
        assertTrue(roles.hasRole(roles.KEEPER_ROLE(), OWNER));
        assertTrue(roles.hasRole(roles.ALLOCATOR_ROLE(), OWNER));
        assertTrue(roles.hasRole(roles.GUARDIAN_ROLE(), OWNER));
    }

    function testConstructorRevertsForZeroOwner() external {
        vm.expectRevert(abi.encodeWithSelector(MeridianRoles.InvalidOwner.selector, address(0)));
        new MeridianRolesHarness(address(0));
    }

    function testRoleConstantsHaveExpectedValues() external view {
        assertEq(roles.DEFAULT_ADMIN_ROLE(), bytes32(0));
        assertEq(roles.ADMIN_ROLE(), keccak256("ADMIN_ROLE"));
        assertEq(roles.KEEPER_ROLE(), keccak256("KEEPER_ROLE"));
        assertEq(roles.ALLOCATOR_ROLE(), keccak256("ALLOCATOR_ROLE"));
        assertEq(roles.GUARDIAN_ROLE(), keccak256("GUARDIAN_ROLE"));
    }

    function testOwnerCanGrantAndRevokeRole() external {
        vm.prank(OWNER);
        roles.grantRole(KEEPER_ROLE, KEEPER);
        assertTrue(roles.hasRole(roles.KEEPER_ROLE(), KEEPER));

        vm.prank(OWNER);
        roles.revokeRole(KEEPER_ROLE, KEEPER);
        assertFalse(roles.hasRole(roles.KEEPER_ROLE(), KEEPER));
    }

    function testAdminCanManageRoles() external {
        vm.prank(OWNER);
        roles.grantRole(ADMIN_ROLE, ADMIN);

        vm.prank(ADMIN);
        roles.grantRole(KEEPER_ROLE, KEEPER);
        assertTrue(roles.hasRole(roles.KEEPER_ROLE(), KEEPER));

        vm.prank(ADMIN);
        roles.revokeRole(KEEPER_ROLE, KEEPER);
        assertFalse(roles.hasRole(roles.KEEPER_ROLE(), KEEPER));
    }

    function testGrantRoleIsIdempotent() external {
        vm.startPrank(OWNER);
        roles.grantRole(KEEPER_ROLE, KEEPER);
        roles.grantRole(KEEPER_ROLE, KEEPER);
        vm.stopPrank();

        assertTrue(roles.hasRole(roles.KEEPER_ROLE(), KEEPER));
    }

    function testRevokeMissingRoleIsIdempotent() external {
        vm.startPrank(OWNER);
        roles.revokeRole(KEEPER_ROLE, KEEPER);
        roles.revokeRole(KEEPER_ROLE, KEEPER);
        vm.stopPrank();

        assertFalse(roles.hasRole(roles.KEEPER_ROLE(), KEEPER));
    }

    function testRoleHolderCanRenounceRole() external {
        vm.prank(OWNER);
        roles.grantRole(KEEPER_ROLE, KEEPER);

        vm.prank(KEEPER);
        roles.renounceRole(KEEPER_ROLE);

        assertFalse(roles.hasRole(roles.KEEPER_ROLE(), KEEPER));
    }

    function testOwnerRetainsImplicitRoleAfterRenouncing() external {
        vm.prank(OWNER);
        roles.renounceRole(ADMIN_ROLE);

        assertTrue(roles.hasRole(roles.ADMIN_ROLE(), OWNER));
    }

    function testGrantRoleRevertsForZeroAccount() external {
        vm.expectRevert(
            abi.encodeWithSelector(MeridianRoles.InvalidRoleAccount.selector, address(0))
        );
        vm.prank(OWNER);
        roles.grantRole(KEEPER_ROLE, address(0));
    }

    function testRoleManagementRevertsForCallerWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, roles.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        roles.grantRole(KEEPER_ROLE, KEEPER);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, roles.ADMIN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        roles.revokeRole(KEEPER_ROLE, KEEPER);
    }

    function testOnlyRoleModifierAllowsAssignedRole() external {
        vm.prank(OWNER);
        roles.grantRole(KEEPER_ROLE, KEEPER);

        vm.prank(KEEPER);
        roles.keeperAction();

        assertEq(roles.actionCount(), 1);
    }

    function testOnlyRoleModifierRevertsForMissingRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, roles.KEEPER_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        roles.keeperAction();
    }

    function testOwnershipTransferRequiresTwoSteps() external {
        vm.prank(OWNER);
        roles.transferOwnership(PENDING_OWNER);

        assertEq(roles.owner(), OWNER);
        assertEq(roles.pendingOwner(), PENDING_OWNER);

        vm.prank(PENDING_OWNER);
        roles.acceptOwnership();

        assertEq(roles.owner(), PENDING_OWNER);
        assertEq(roles.pendingOwner(), address(0));
        assertTrue(roles.hasRole(roles.ADMIN_ROLE(), PENDING_OWNER));
        assertFalse(roles.hasRole(roles.ADMIN_ROLE(), OWNER));
    }

    function testTransferOwnershipRevertsForZeroAddress() external {
        vm.expectRevert(abi.encodeWithSelector(MeridianRoles.InvalidOwner.selector, address(0)));
        vm.prank(OWNER);
        roles.transferOwnership(address(0));
    }

    function testTransferOwnershipRevertsForNonOwner() external {
        vm.expectRevert(abi.encodeWithSelector(MeridianRoles.OnlyOwner.selector, OUTSIDER));
        vm.prank(OUTSIDER);
        roles.transferOwnership(PENDING_OWNER);
    }

    function testAcceptOwnershipRevertsForNonPendingOwner() external {
        vm.prank(OWNER);
        roles.transferOwnership(PENDING_OWNER);

        vm.expectRevert(abi.encodeWithSelector(MeridianRoles.NotPendingOwner.selector, OUTSIDER));
        vm.prank(OUTSIDER);
        roles.acceptOwnership();
    }

    function testOwnerCanCancelOwnershipTransfer() external {
        vm.prank(OWNER);
        roles.transferOwnership(PENDING_OWNER);
        vm.prank(OWNER);
        roles.cancelOwnershipTransfer();

        assertEq(roles.owner(), OWNER);
        assertEq(roles.pendingOwner(), address(0));

        vm.expectRevert(
            abi.encodeWithSelector(MeridianRoles.NotPendingOwner.selector, PENDING_OWNER)
        );
        vm.prank(PENDING_OWNER);
        roles.acceptOwnership();
    }

    function testCancelOwnershipTransferRevertsForNonOwner() external {
        vm.expectRevert(abi.encodeWithSelector(MeridianRoles.OnlyOwner.selector, OUTSIDER));
        vm.prank(OUTSIDER);
        roles.cancelOwnershipTransfer();
    }

    function testOnlyOwnerModifierTracksTransferredOwnership() external {
        vm.prank(OWNER);
        roles.ownerAction();

        vm.prank(OWNER);
        roles.transferOwnership(PENDING_OWNER);
        vm.prank(PENDING_OWNER);
        roles.acceptOwnership();

        vm.expectRevert(abi.encodeWithSelector(MeridianRoles.OnlyOwner.selector, OWNER));
        vm.prank(OWNER);
        roles.ownerAction();

        vm.prank(PENDING_OWNER);
        roles.ownerAction();

        assertEq(roles.actionCount(), 2);
    }

    function testGuardianCanPauseAndAdminCanUnpause() external {
        vm.prank(OWNER);
        roles.grantRole(GUARDIAN_ROLE, GUARDIAN);

        vm.prank(GUARDIAN);
        roles.pause();
        assertTrue(roles.paused());

        vm.prank(OWNER);
        roles.unpause();
        assertFalse(roles.paused());
    }

    function testPauseRevertsForCallerWithoutGuardianRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, OUTSIDER, roles.GUARDIAN_ROLE()
            )
        );
        vm.prank(OUTSIDER);
        roles.pause();
    }

    function testUnpauseRevertsForCallerWithoutAdminRole() external {
        vm.prank(OWNER);
        roles.grantRole(GUARDIAN_ROLE, GUARDIAN);
        vm.prank(GUARDIAN);
        roles.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianRoles.Unauthorized.selector, GUARDIAN, roles.ADMIN_ROLE()
            )
        );
        vm.prank(GUARDIAN);
        roles.unpause();
    }

    function testPauseAndUnpauseEnforceCurrentState() external {
        vm.prank(OWNER);
        roles.pause();

        vm.expectRevert(MeridianRoles.ContractPaused.selector);
        vm.prank(OWNER);
        roles.pause();

        vm.prank(OWNER);
        roles.unpause();

        vm.expectRevert(MeridianRoles.ContractNotPaused.selector);
        vm.prank(OWNER);
        roles.unpause();
    }

    function testPauseStateModifiers() external {
        roles.activeAction();

        vm.expectRevert(MeridianRoles.ContractNotPaused.selector);
        roles.pausedAction();

        vm.prank(OWNER);
        roles.pause();

        vm.expectRevert(MeridianRoles.ContractPaused.selector);
        roles.activeAction();

        roles.pausedAction();
        assertEq(roles.actionCount(), 2);
    }

    function testNonReentrantModifierAllowsSequentialCalls() external {
        roles.guardedAction(false);
        roles.guardedAction(false);

        assertEq(roles.actionCount(), 2);
    }

    function testNonReentrantModifierRejectsNestedCallAndRecovers() external {
        vm.expectRevert(MeridianRoles.ReentrantCall.selector);
        roles.guardedAction(true);

        roles.guardedAction(false);
        assertEq(roles.actionCount(), 1);
    }
}
