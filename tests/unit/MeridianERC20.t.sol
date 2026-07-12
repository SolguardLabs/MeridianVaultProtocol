// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import { MeridianRoles } from "../../src/access/MeridianRoles.sol";
import { MockStablecoin } from "../../src/mocks/MockStablecoin.sol";
import { MeridianERC20 } from "../../src/token/MeridianERC20.sol";
import { TestBase } from "../helpers/TestBase.sol";

contract MeridianERC20Test is TestBase {
    MockStablecoin internal token;

    address internal constant OWNER = address(0xA11CE);
    address internal constant ALICE = address(0xB0B);
    address internal constant BOB = address(0xCAFE);
    address internal constant SPENDER = address(0xD00D);

    uint256 internal constant CAP = 1_000_000e6;
    bytes32 internal constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bytes32 internal constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    function setUp() public {
        token = new MockStablecoin(OWNER, "Meridian USD", "mUSD", 6, CAP);
    }

    function testMetadataAndInitialState() external view {
        assertEq(keccak256(bytes(token.name())), keccak256(bytes("Meridian USD")));
        assertEq(keccak256(bytes(token.symbol())), keccak256(bytes("mUSD")));
        assertEq(token.decimals(), 6);
        assertEq(token.totalSupply(), 0);
        assertEq(token.cap(), CAP);
        assertEq(token.remainingMintableSupply(), CAP);
        assertTrue(token.DOMAIN_SEPARATOR() != bytes32(0));
    }

    function testOwnerCanMintUpToCap() external {
        vm.prank(OWNER);
        token.mint(ALICE, CAP);

        assertEq(token.totalSupply(), CAP);
        assertEq(token.balanceOf(ALICE), CAP);
        assertEq(token.remainingMintableSupply(), 0);
    }

    function testAdminRoleCanMintAndUpdateCap() external {
        vm.prank(OWNER);
        token.grantRole(ADMIN_ROLE, BOB);

        vm.prank(BOB);
        token.mint(ALICE, 100e6);
        vm.prank(BOB);
        token.setCap(CAP + 1);

        assertEq(token.balanceOf(ALICE), 100e6);
        assertEq(token.cap(), CAP + 1);
    }

    function testMintRevertsForCallerWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(MeridianRoles.Unauthorized.selector, ALICE, token.ADMIN_ROLE())
        );
        vm.prank(ALICE);
        token.mint(ALICE, 1);
    }

    function testMintRevertsWhenCapWouldBeExceeded() external {
        vm.prank(OWNER);
        token.mint(ALICE, CAP);

        vm.expectRevert(
            abi.encodeWithSelector(
                MockStablecoin.MockStablecoin__CapExceeded.selector, CAP + 1, CAP
            )
        );
        vm.prank(OWNER);
        token.mint(ALICE, 1);
    }

    function testMintRevertsForZeroReceiver() external {
        vm.expectRevert(
            abi.encodeWithSelector(MeridianERC20.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(OWNER);
        token.mint(address(0), 1);
    }

    function testZeroCapLeavesSupplyUncapped() external {
        vm.prank(OWNER);
        token.setCap(0);

        vm.prank(OWNER);
        token.mint(ALICE, CAP + 1);

        assertEq(token.totalSupply(), CAP + 1);
        assertEq(token.remainingMintableSupply(), type(uint256).max);
    }

    function testSetCapRevertsBelowCurrentSupply() external {
        vm.prank(OWNER);
        token.mint(ALICE, 100);

        vm.expectRevert(
            abi.encodeWithSelector(MockStablecoin.MockStablecoin__CapBelowSupply.selector, 99, 100)
        );
        vm.prank(OWNER);
        token.setCap(99);
    }

    function testSetCapAllowsValueEqualToCurrentSupply() external {
        vm.prank(OWNER);
        token.mint(ALICE, 100);

        vm.prank(OWNER);
        token.setCap(100);

        assertEq(token.cap(), 100);
        assertEq(token.remainingMintableSupply(), 0);
    }

    function testSetCapRevertsForCallerWithoutAdminRole() external {
        vm.expectRevert(
            abi.encodeWithSelector(MeridianRoles.Unauthorized.selector, ALICE, token.ADMIN_ROLE())
        );
        vm.prank(ALICE);
        token.setCap(CAP + 1);
    }

    function testTransferMovesBalances() external {
        _mintAlice(100);

        vm.prank(ALICE);
        bool success = token.transfer(BOB, 40);

        assertTrue(success);
        assertEq(token.balanceOf(ALICE), 60);
        assertEq(token.balanceOf(BOB), 40);
        assertEq(token.totalSupply(), 100);
    }

    function testTransferZeroAmountIsAllowed() external {
        vm.prank(ALICE);
        bool success = token.transfer(BOB, 0);

        assertTrue(success);
        assertEq(token.balanceOf(ALICE), 0);
        assertEq(token.balanceOf(BOB), 0);
    }

    function testTransferRevertsForInsufficientBalance() external {
        _mintAlice(10);

        vm.expectRevert(
            abi.encodeWithSelector(MeridianERC20.ERC20InsufficientBalance.selector, ALICE, 10, 11)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 11);
    }

    function testTransferRevertsForZeroReceiver() external {
        _mintAlice(10);

        vm.expectRevert(
            abi.encodeWithSelector(MeridianERC20.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(ALICE);
        token.transfer(address(0), 1);
    }

    function testApproveAndTransferFromConsumeAllowance() external {
        _mintAlice(100);

        vm.prank(ALICE);
        bool approved = token.approve(SPENDER, 70);
        vm.prank(SPENDER);
        bool transferred = token.transferFrom(ALICE, BOB, 45);

        assertTrue(approved);
        assertTrue(transferred);
        assertEq(token.allowance(ALICE, SPENDER), 25);
        assertEq(token.balanceOf(ALICE), 55);
        assertEq(token.balanceOf(BOB), 45);
    }

    function testInfiniteAllowanceIsNotConsumed() external {
        _mintAlice(100);

        vm.prank(ALICE);
        token.approve(SPENDER, type(uint256).max);
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 45);

        assertEq(token.allowance(ALICE, SPENDER), type(uint256).max);
    }

    function testApproveRevertsForZeroSpender() external {
        vm.expectRevert(
            abi.encodeWithSelector(MeridianERC20.ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(ALICE);
        token.approve(address(0), 1);
    }

    function testTransferFromRevertsForInsufficientAllowance() external {
        _mintAlice(100);

        vm.prank(ALICE);
        token.approve(SPENDER, 20);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianERC20.ERC20InsufficientAllowance.selector, SPENDER, 20, 21
            )
        );
        vm.prank(SPENDER);
        token.transferFrom(ALICE, BOB, 21);
    }

    function testBurnReducesBalanceAndSupply() external {
        _mintAlice(100);

        vm.prank(ALICE);
        token.burn(35);

        assertEq(token.balanceOf(ALICE), 65);
        assertEq(token.totalSupply(), 65);
        assertEq(token.remainingMintableSupply(), CAP - 65);
    }

    function testBurnRevertsForInsufficientBalance() external {
        _mintAlice(10);

        vm.expectRevert(
            abi.encodeWithSelector(MeridianERC20.ERC20InsufficientBalance.selector, ALICE, 10, 11)
        );
        vm.prank(ALICE);
        token.burn(11);
    }

    function testBurnFromConsumesAllowance() external {
        _mintAlice(100);

        vm.prank(ALICE);
        token.approve(SPENDER, 50);
        vm.prank(SPENDER);
        token.burnFrom(ALICE, 30);

        assertEq(token.balanceOf(ALICE), 70);
        assertEq(token.totalSupply(), 70);
        assertEq(token.allowance(ALICE, SPENDER), 20);
    }

    function testBurnFromRevertsForInsufficientAllowance() external {
        _mintAlice(100);

        vm.prank(ALICE);
        token.approve(SPENDER, 20);

        vm.expectRevert(
            abi.encodeWithSelector(
                MeridianERC20.ERC20InsufficientAllowance.selector, SPENDER, 20, 21
            )
        );
        vm.prank(SPENDER);
        token.burnFrom(ALICE, 21);
    }

    function testPermitSetsAllowanceAndIncrementsNonce() external {
        uint256 ownerPrivateKey = 0xA11CE;
        address permitOwner = vm.addr(ownerPrivateKey);
        uint256 value = 123e6;
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _permitDigest(permitOwner, SPENDER, value, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permitOwner, SPENDER, value, deadline, v, r, s);

        assertEq(token.allowance(permitOwner, SPENDER), value);
        assertEq(token.nonces(permitOwner), 1);
    }

    function testPermitRevertsAfterDeadline() external {
        vm.warp(100);

        vm.expectRevert(abi.encodeWithSelector(MeridianERC20.PermitExpired.selector, 99));
        token.permit(ALICE, SPENDER, 1, 99, 27, bytes32(0), bytes32(0));
    }

    function testPermitRevertsForInvalidSignature() external {
        uint256 signerPrivateKey = 0xB0B;
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _permitDigest(ALICE, SPENDER, 1, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(signerPrivateKey, digest);

        vm.expectRevert(MeridianERC20.InvalidPermitSignature.selector);
        token.permit(ALICE, SPENDER, 1, deadline, v, r, s);
    }

    function testPermitSignatureCannotBeReused() external {
        uint256 ownerPrivateKey = 0xA11CE;
        address permitOwner = vm.addr(ownerPrivateKey);
        uint256 deadline = block.timestamp + 1 days;
        bytes32 digest = _permitDigest(permitOwner, SPENDER, 1, 0, deadline);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerPrivateKey, digest);

        token.permit(permitOwner, SPENDER, 1, deadline, v, r, s);

        vm.expectRevert(MeridianERC20.InvalidPermitSignature.selector);
        token.permit(permitOwner, SPENDER, 1, deadline, v, r, s);
    }

    function testPermitRejectsZeroOwnerAndZeroSpender() external {
        uint256 deadline = block.timestamp + 1 days;

        vm.expectRevert(MeridianERC20.InvalidPermitSignature.selector);
        token.permit(address(0), SPENDER, 1, deadline, 27, bytes32(0), bytes32(0));

        vm.expectRevert(MeridianERC20.InvalidPermitSignature.selector);
        token.permit(ALICE, address(0), 1, deadline, 27, bytes32(0), bytes32(0));
    }

    function _mintAlice(uint256 amount) internal {
        vm.prank(OWNER);
        token.mint(ALICE, amount);
    }

    function _permitDigest(
        address permitOwner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, permitOwner, spender, value, nonce, deadline)
        );
        return keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
    }
}
