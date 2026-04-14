# Scotch V2 Architecture

## Layers
- `ScotchApp`: executable entry point and scene bootstrapping.
- `ScotchFeatures`: SwiftUI screens and feature view models.
- `ScotchRuntime`: bottle orchestration, runtime install/update, launch execution, compatibility behavior.
- `ScotchInfrastructure`: filesystem/process/logging/persistence adapters.
- `ScotchDomain`: pure models and use-case protocols.

## Composition
- `ScotchContainer` builds concrete services once and injects protocols into feature view models.
- Runtime services use actors for mutation and process orchestration.
- UI never talks directly to process/file APIs.

## Compatibility strategy
- Keep bottle metadata shape compatible (`Metadata.plist`), preserving settings and behavior.
- Preserve backend/env assembly behavior for DXVK, DXMT, D3DMetal, Zink, sync modes, and GPU spoofing keys.
- Preserve launch behavior via `open -a Wine.app --args start /unix ...` to avoid hidden windows.

## Performance strategy
- IO/process work is off main actor.
- Bottle scans are explicit refresh actions and run in background tasks.
- Logging uses append-only file handles with deterministic locations.
