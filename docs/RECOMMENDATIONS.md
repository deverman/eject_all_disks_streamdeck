# Recommendations and Next Steps

This file captures outstanding items and follow-ups from the doc-consistency pass.

## Outstanding Items (Not Addressed in PR)
- Visual state mismatch remains by request: docs still mention visual feedback, but only `icon.svg` and `ejecting.svg` exist and code does not switch to success/error images.
- Marketplace version mismatch: Marketplace lists version 3.0.0.1 while code reports 3.0.2 (verify which is authoritative before the next release).
- `AGENTS.md` still states `manifest.json` lives in the repo bundle and uses `streamdeck pack org.deverman.ejectalldisks.sdPlugin`; current flow generates the manifest in the installed bundle.

## Next Steps After Merge
1. Decide how to resolve the visual state mismatch:
   - add success/error SVGs and wire image swapping, or
   - update docs to describe text-only success/error states.
2. Align release versioning:
   - confirm the current Marketplace version vs `EjectAllDisksPlugin.version`,
   - update code or publish a new Marketplace build to match.
3. Update repo guidance to reflect the current export/manifest flow:
   - align `AGENTS.md` packaging command and manifest location with `build.sh`/CI.
4. Start SD-card ignore feature work:
   - log DiskArbitration description keys (BSD-only, no volume names) to determine reliable SD-card heuristics,
   - add a settings toggle in PI,
   - add tests for filtering logic in `SwiftDiskArbitration`.

## References
- Marketplace listing: https://marketplace.elgato.com/product/safeeject-one-push-disk-manager-3b9d46a2-616a-4e13-9e58-82a7d6384278
