# Scotch V2 Release Checklist

## Packaging
- [ ] Build `ScotchApp` in release configuration.
- [ ] Build `ScotchCmd` in release configuration and include in app bundle resources if required by distribution layout.
- [ ] Ensure runtime support resources are present in bundle/package output:
  - `winetricks`
  - `VulkanSpoof/libMoltenVK_shim.c` build path support
  - any packaged helper binaries/scripts used at runtime
- [ ] Build distributable disk image (DMG) using release packaging script/workflow.

## Entitlements and Permissions
- [x] Verify Apple Events usage text is present for Terminal integration flows.
- [ ] Verify app entitlements for shipping profile are correct.
- [ ] Validate bundle resources and launch behavior on each supported architecture.

## Signing and Notarization
- [ ] Codesign app bundle.
- [ ] Notarize build with Apple notary service.
- [ ] Staple notarization ticket.
- [ ] Verify notarization status on clean machine.

## Final Gate
- [ ] Run `scripts/release_gate.sh`.
- [ ] Confirm `Docs/manual_qa_matrix.md` and `Docs/final_parity_report.md` are up to date.
- [ ] Tag release after all required checks pass (or explicit written waivers).
