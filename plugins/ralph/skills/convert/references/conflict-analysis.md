# Conflict Analysis Reference

When populating `sharedFiles`, classify each entry's `conflictType` using these rules.

## Classification Rules

| File Type | Append-Only | Structural-Modify |
|-----------|-------------|-------------------|
| **Registry/barrel files** (index.ts, routes.ts) | Adding new imports, exports, or route registrations | Modifying existing imports or restructuring exports |
| **Config files** (config.ts, env files) | Adding new config keys or sections | Changing existing config values or restructuring |
| **Schema files** (schema.prisma, migrations) | Adding new models or tables | Modifying existing models (adding fields, changing types) |
| **Shared utilities** (utils.ts, helpers.ts) | Adding new standalone functions | Modifying existing function signatures or logic |
| **Package manifests** (package.json) | Adding new dependencies | Changing existing dependency versions or scripts |

**When uncertain** -> default to `structural-modify` (the conservative, safe choice).

## Cross-Story Analysis

After classifying all stories' shared files:

1. **Check for unlock opportunities** -- if multiple same-priority stories share a file and ALL declare `append-only`, they can run in parallel with `conflictStrategy: "optimistic"`. Note this as a recommendation.
2. **Check for structural conflicts** -- if two same-priority stories both declare `structural-modify` for the same file AND neither depends on the other, consider suggesting a split or adding a dependency to enforce ordering.
3. **Set conflictStrategy** -- if the majority of shared-file overlaps are `append-only` (e.g., 5 stories all appending to `src/index.ts`), set `conflictStrategy: "optimistic"` in the project-level JSON.
