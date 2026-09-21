# Scene 01 Final QA — #22

Status: **IN PROGRESS**
Baseline: `main@0879628da869f28a19e9cc082c32bf0377a1d03d`
Godot: **4.7.2**
Parent: #1
Issue: #22

## 1. Scope

This is the final Scene 01 MVP completion gate.

No new product capability is introduced here. Any failure found by this QA must be fixed with the smallest change that restores the already accepted Scene 01 contract. Post-MVP work remains in #17, #34, #49, #58, #62, #64, #65 and #66.

## 2. Automated baseline

Merged-main Godot CI:

- Workflow: `Godot CI`
- Run number: **#290**
- Run id: `35555475376`
- Event: `push`
- Head: `0879628da869f28a19e9cc082c32bf0377a1d03d`
- Conclusion: **SUCCESS**

Workflow contract:

- Godot 4.7.2
- project import must exit 0
- project import fails closed on `SCRIPT ERROR:`
- runtime tests are auto-discovered
- each runtime suite has a 30 second timeout
- job timeout is 5 minutes
- all suites run before the job returns failure

Run #290 result:

- Project Import: **PASS**
- Runtime suites: **52 / 52 PASS**
- Suite failures: **0**

Suite distribution:

- assembly: 2
- grid: 2
- input: 5
- objects: 2
- scene_01: 33
- vehicles: 8

Known non-blocking test teardown warnings remain in assembly-related suites:

- 176 ObjectDB instances / 12 resources still in use
- 8 ObjectDB instances / 2 resources still in use

These warnings predate #22, the affected suites return exit 0, and Run #290 completes successfully. They are test-hygiene debt, not a new Scene 01 product regression.

## 3. Final static / Ponytail audit

Current-main review focuses on the final MVP contracts rather than introducing another refactor.

### Lifecycle / time

- [x] simulation speed is applied to gameplay delta, not `Engine.time_scale`
- [x] Mission elapsed time uses simulation time
- [x] scoring consumes Mission elapsed time
- [x] Pause freezes gameplay progression
- [x] Reset restores READY + 1×
- [x] no new lifecycle mirror / queue / transaction layer found

### Gameplay ownership

- [x] MoveTo manual and Program paths use the shared explicit-vehicle command core
- [x] GrabDrop manual and Program paths use the shared explicit-vehicle command core
- [x] Rotate manual and Program paths use the same turn owner
- [x] Program does not mutate player selection
- [x] Program does not own Vehicle / Object / Mission mutable truth
- [x] Tutorial records only historical goals and presentation state

### Program authoring

- [x] CodeEdit source remains the only mutable Program authoring truth
- [x] Builder writes source instead of owning a second statement model
- [x] runtime execution receives a Program snapshot
- [x] canonical namespace is protected by SourceEditor
- [x] DSL remains language-independent
- [x] no legacy absolute `Face north/east/south/west` path found
- [x] Rotate uses `clockwise` / `counterclockwise`

### Deferred boundaries

- [x] #49 dynamic GroundBlock occupancy remains explicitly P3 / non-blocking
- [x] #58 global UI redesign is not pulled into Final QA
- [x] #62 controller refactor is not pulled into Final QA
- [x] #64 visual command preview is not required for MVP
- [x] #65 structured parameter picking is not required for MVP
- [x] #66 localization is not required for MVP

Current static gate:

```text
Blocking: 0
Major:    0
```

## 4. Automated acceptance coverage

The current 52-suite matrix includes direct coverage for:

- production Scene 01 E2E
- lifecycle state / pause / resume / reset
- lifecycle preparation gate
- simulation-speed movement / collision
- manual MoveTo
- GrabDrop and ownership
- Ground / Tray / Box domain behavior
- Assembly Compile / capability validation
- Mission completion
- Observable Runtime State
- HUD
- Program parser / source / validator / runner
- Program timing
- Program workspace
- Scoring
- Tutorial
- vehicle state machine / movement execution / visual contracts

## 5. Fresh player-visible walkthrough

This section must be executed against the final #22 candidate in a graphical Godot 4.7.2 client.

### A. Scene entry / UI

- [ ] Scene 01 enters without visible errors
- [ ] Chinese canonical UI is readable
- [ ] central gameplay area is usable at a normal desktop window size
- [ ] Tutorial / HUD / Program do not block required world interaction
- [ ] Program panel can collapse / expand
- [ ] clicking the world releases CodeEdit focus

### B. Manual logistics

- [ ] select Arm
- [ ] MoveTo pile
- [ ] rotate with A / D
- [ ] C picks a block
- [ ] MoveTo StandardBox
- [ ] C drops the block
- [ ] StandardBox increments exactly once
- [ ] tray / ground transfer path remains usable

### C. Lifecycle

- [ ] first gameplay command auto-starts READY → RUNNING
- [ ] Pause freezes movement / rotation / timer
- [ ] Resume continues the same in-flight command
- [ ] 0.5× / 1× / 2× / 4× are usable
- [ ] Reset returns gameplay to initial state and speed to 1×
- [ ] repeated Reset is stable

### D. Program Workspace

- [ ] namespace cannot be permanently removed or corrupted
- [ ] direct source typing works
- [ ] Builder adds MoveTo
- [ ] Builder adds clockwise / counterclockwise Rotate
- [ ] Builder adds GrabDrop
- [ ] Builder adds legal Repeat
- [ ] Save / Load round-trip source
- [ ] Export Blueprint copies source
- [ ] source diagnostics point to useful lines

### E. Program execution

- [ ] one Program can serially control Arm and Transport
- [ ] Program Rotate visibly costs simulation time
- [ ] Pause freezes Program Rotate
- [ ] Program MoveTo / Rotate / GrabDrop do not overlap illegally
- [ ] Program execution does not change player selection
- [ ] a successful Program can deliver to StandardBox

### F. Tutorial

- [ ] five goals are independent and may complete out of page order
- [ ] Previous / Next freely browse teaching pages
- [ ] manual pickup goal completes from a real manual pickup
- [ ] manual StandardBox +1 goal completes from a real manual delivery
- [ ] Program delivery goal completes only from a successful Program delivery
- [ ] Transport MoveTo goal completes only when the successful delivery Program includes Transport MoveTo
- [ ] DONE unlocks at 5/5
- [ ] Reset preserves Tutorial goal history and current page
- [ ] Skip / Reopen only affect presentation

### G. Mission / scoring

- [ ] filling StandardBox to 8/8 completes Mission
- [ ] result panel shows completion time
- [ ] result panel shows component count
- [ ] result panel shows automation rate
- [ ] completion freezes final score
- [ ] 4× reduces real waiting but does not improve simulation-time completion score
- [ ] Reset clears final scoring state for a new run

### H. Re-entry

- [ ] leave / destroy Scene 01
- [ ] enter Scene 01 again
- [ ] initial gameplay state is clean
- [ ] Program / Tutorial / HUD bind correctly
- [ ] no stale command / ownership / scoring runtime leaks into the new scene

## 6. Completion gate

#22 may close only when all are true:

- [x] #21 Tutorial merged
- [x] all MVP feature Issues completed
- [x] final static audit has no Blocking / Major finding
- [x] merged-main Godot 4.7.2 baseline passes
- [ ] #22 candidate PR Godot 4.7.2 CI passes
- [ ] fresh graphical walkthrough passes
- [ ] no regression fix remains unmerged
- [ ] #1 can be closed as Scene 01 MVP complete

## 7. Final disposition

Pending the #22 candidate CI and fresh graphical walkthrough.
