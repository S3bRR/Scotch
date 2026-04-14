# Scotch V2 Migration Notes

## Preserved behavior
- Bottle index and metadata persistence in user-scoped directories.
- Runtime manifest/version persistence and first-run runtime setup checks.
- Launch and batch execution through Wine runtime with assembled environment variables.
- Bottle backend selection and compatibility settings persistence.
- Program scanning from bottle filesystem and pin/blocklist persistence.

## Intentional architecture changes
- Removed static singleton managers in favor of protocol-backed services and actor implementations.
- Split UI, domain, runtime orchestration, and infrastructure concerns into separate targets.
- Added typed path/config abstractions to minimize hidden filesystem assumptions.

## Naming migration
- New code uses `Scotch` naming exclusively.
- Legacy product naming is not used inside `scotch_v2` sources.
