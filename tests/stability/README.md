# Dependency-risk stability suite

Tests in this directory run on every pull request and every push to `main`.

This is not a feature checklist, a bug archive, or a coverage target. A test belongs in
this routine gate only when it protects a structurally fragile production dependency and
fails close enough to the responsible owner or boundary to be diagnostically useful.

## Selection rule

Start from the real production dependency path, not from issue history or test names.
Prefer a focused stability test when correctness depends on one or more of:

- multiple authoritative upstream inputs converging at one owner;
- one output consumed by multiple subsystems;
- mutable state transitions, reset, cancellation, retry, or ownership transfer;
- lifecycle, ordering, signal, or timing behavior;
- a query/readiness API that must not publish or mutate runtime state;
- conversion between authoritative and derived representations;
- cache or publication lifetime;
- fail-closed error propagation.

The test should sit at the nearest meaningful owner or dependency edge. Do not load
Scene 01 merely to verify an invariant that can be exercised directly.

## Routine inventory

| Test | Structural risk protected |
| --- | --- |
| `assembly_compiler_contract_test.gd` | assembly definition -> compiled representation, cache/revision identity, atomic fail-closed results |
| `program_capability_validator_contract_test.gd` | compiled capabilities -> Program allow/reject boundary |
| `ground_block_field_smoke_test.gd` | mutable ground ownership, cached cell interfaces, policy/reset release |
| `object_domain_smoke_test.gd` | cross-receiver ownership and receiver lifetime release |
| `scene_01_assembly_definition_adapter_contract_test.gd` | vehicle definition -> assembly definition representation transform |
| `scene_01_assembly_compile_gate_contract_test.gd` | multi-vehicle compile fan-in, query/publication separation, invalidation lifetime |
| `scene_01_lifecycle_state_smoke_test.gd` | READY/RUNNING/PAUSED state and simulation-speed transitions |
| `scene_01_program_source_test.gd` | canonical source -> semantic Program representation and requirement derivation |
| `grab_drop_command_smoke_test.gd` | GrabDrop transaction ownership, rollback, target revalidation |
| `move_command_state_machine_test.gd` | MoveCommand mutable transition boundary |
| `transport_tray_state_smoke_test.gd` | tray inventory ownership, access guard, reset release |
| `vehicle_move_execution_contract_test.gd` | MoveCommand -> VehicleActor/VehicleRuntimeState timing, cancel and reset semantics |
| `move_target_commit_boundary_test.gd` | shared live target selection -> execute-vs-select-only commit routing |
| `lifecycle_readiness_purity_stability_test.gd` | readiness query -> preparation gate must remain side-effect free |
| `vehicle_runtime_reset_stability_test.gd` | VehicleRuntimeState reset -> stationary tray interaction metadata restoration |

Every routine test above is intentionally independent of Scene 01 presentation and
graphical composition.

## Full Suite

The manually requested `full` suite still discovers every runnable `*_test.gd` and
`*_smoke_test.gd` outside `tests/fixtures` and `tests/support`, including the stability
suite.

Full Suite is the home for broader owner contracts, feature acceptance, composition,
integration, E2E, and headless UI checks whose value is real but whose setup is not the
nearest routine diagnostic cut.

## What does not qualify by itself

Do not add a routine stability test only because:

- a feature is important or newly added;
- a bug happened once;
- an issue requested a test;
- line/branch coverage would increase;
- an end-to-end scenario provides reassurance.

Those facts may reveal a structural risk, but the permanent test must protect that risk,
not preserve the history that exposed it.

## Future test policy

A production change does not automatically require a new stability test.

1. Inspect the changed owner and its real upstream/downstream dependencies.
2. If a high-risk node or edge changed, update the nearest existing stability test or add
   one focused test when no nearby protection exists.
3. If the change is a leaf feature or presentation-only behavior, use Full Suite,
   graphical acceptance, or no permanent automated test as appropriate.
4. When a bug appears, identify the first responsible dependency edge. Add or change a
   stability test only if that failure exposed an unprotected structural risk.
5. Delete or shrink a stability test when ownership moves, the dependency disappears,
   the invalid state becomes unrepresentable, or a nearer test protects the same risk.

Prefer deleting duplicated setup over creating shared orchestration or generic dependency
testing machinery.
