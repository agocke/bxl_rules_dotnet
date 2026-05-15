# Future work for `rules_dotnet` parity

This repository is intentionally smaller than Bazel's `rules_dotnet`, but there are several areas where we should align the public model and implementation more closely.

## Public API alignment

1. Remove stale references to old `fileRefs` behavior from code comments and docs.
2. Revisit `refs` as a public attr; prefer dependency/import-target modeling where possible instead of a separate assembly-reference surface.
3. Convert `analyzerConfigs` from `File[]` to label-based inputs resolved by the rule.
4. Rework `analyzers` to follow an analyzer target/provider model rather than raw analyzer DLL inputs.
5. Add explicit import-style rules/providers for external assemblies if `refs` still covers that use case.
6. Keep user-facing inputs label-based and reserve `File`-typed values for provider outputs and resolved implementation details.

## Target framework and pack resolution

1. Audit the current TFM model against `rules_dotnet`'s `target_frameworks` behavior.
2. Decide whether rules should expose an explicit target TFM, a `target_frameworks` list, or both.
3. Verify that the requested TFM drives compile-time reference assembly selection.
4. Add tests proving that different TFMs resolve different reference assemblies and reject incompatible references.

## Runtime and publish behavior

1. Audit runtime pack selection by TFM and RID.
2. Audit apphost pack selection for executable outputs.
3. Decide how to model framework-dependent versus self-contained publishing.
4. Evaluate RID-specific asset resolution and how those assets flow into run and publish outputs.
5. Audit support for trimming/ILLink integration.
6. Audit support for Native AOT toolchains and packs.
7. Decide which runtime and publish features are required for parity now versus later.

## Test and documentation follow-up

1. Add coverage for external package labels, imported assemblies, analyzer configs, analyzer targets, and TFM-specific reference resolution.
2. Tighten docs so examples consistently show labels/targets as inputs and treat `File` values as implementation outputs.
3. Document any intentional deviations from `rules_dotnet` so users know what is and is not expected to work.
