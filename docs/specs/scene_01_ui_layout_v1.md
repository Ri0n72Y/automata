# Scene 01 UI Layout Spec v1

Status: **Accepted for implementation**
Scope: **#21 test-blocking presentation layout fix**
Branch: `codex/21-scene01-tutorial`
Related: #21, PR #63
Out of scope: #58 global visual redesign, #62 controller refactor

## 1. Problem

The current Scene 01 layout blocks player-visible testing:

- Tutorial occupies a large fixed panel on the left.
- HUD occupies another large fixed panel on the lower left.
- Program Workspace occupies a large fixed panel on the right.
- These panels encroach on the central gameplay view, making vehicle selection, MoveTo targeting, facing, GrabDrop interaction and scene reading difficult.

This is a presentation-layer blocker, not a gameplay-contract problem.

## 2. Goal

Restore a clearly usable central gameplay area while preserving existing owners and contracts.

The layout must:

1. Keep the central gameplay view visually and interactively usable.
2. Prevent Tutorial / Manual Guide / HUD / Program Workspace from overlapping each other.
3. Keep Tutorial and Manual Guide mutually exclusive.
4. Keep Program Source as the canonical authoring surface.
5. Avoid any gameplay, scoring, lifecycle or Program execution changes.

## 3. Ponytail constraints

No new global UI coordinator, layout manager, duplicated authoring state, compatibility layer or gameplay mirror.

Ownership remains:

- `Scene01Tutorial`: tutorial progress/history only.
- `Scene01TutorialUI`: tutorial presentation only.
- `Scene01ManualControls`: manual guide presentation + existing input ownership.
- `Scene01HUD`: current gameplay status presentation.
- `Scene01ProgramUI`: Program authoring presentation plus its own presentation-only collapse state.
- CodeEdit source text remains the single mutable Program authoring truth.

Forbidden dependencies:

- Tutorial must not control Program workspace open/closed state.
- HUD must not control Tutorial.
- Program UI must not own gameplay state.
- No shared mutable UI state dictionary.

## 4. Layout model

Use a three-region desktop layout:

```text
┌──────────────────────────────────────────────────────────────┐
│                     Lifecycle / Debug                        │
├──────────────┬──────────────────────────────┬────────────────┤
│ LEFT RAIL    │        GAMEPLAY VIEW         │ PROGRAM RAIL   │
│ Tutorial /   │                              │ Source/editor  │
│ Manual       │                              │                │
│ HUD          │                              │                │
└──────────────┴──────────────────────────────┴────────────────┘
```

The central gameplay region is protected: persistent UI must not geometrically cover it.

## 5. Desktop dimensions

Primary validation sizes:

- 1920×1080
- approximately 2264×1274

### Wide desktop (viewport width >= 1920)

- Left rail target width: 360 px.
- Program rail target width: 500–520 px.
- Outer margin: 16 px.
- Top content offset: 82 px.
- Vertical bottom margin: 16 px.
- Central gameplay width target: about 1000 px or greater.

### Compact desktop (1600–1919)

- Left rail target width: 320 px.
- Program rail target width: 420–460 px.
- Program should favor collapsed presentation when necessary.

### Below 1600

No complete responsive redesign is required in this patch.

Minimum behavior:

- Program defaults collapsed.
- Left rail should not exceed 300 px.
- Persistent panels must not re-cover the central gameplay region.

Do not introduce a breakpoint service.

## 6. Left rail

The left rail contains two vertically separated regions:

1. Tutorial / Manual Guide slot.
2. HUD status slot.

Minimum gap between them: 12 px.

### Tutorial / Manual Guide

They continue to share one presentation slot:

```text
Tutorial visible
    -> Manual Guide RootControl hidden

Tutorial skipped/closed
    -> Manual Guide RootControl visible
```

No tab manager and no third owner.

### Tutorial panel

Target:

- Width: 100% of left rail.
- Height: content-driven, approximately 220–260 px.
- Compact text; avoid large empty body regions.

Content order:

```text
SCENE 01 · 教学          步骤 n / 5
Step title

Short instruction, approximately <= 3 lines.

模板能力
Arm        编译通过 · 可移动 · 可抓取
Transport  编译通过 · 可移动 · 可承载

                         跳过教学
```

Capability content remains a read-only projection of formal CompileGate results.

### Manual Guide

Keep the existing owner and default collapsed behavior.

Header remains conceptually:

```text
Scene 01 · 操作指南       教学   ▶
```

When expanded, it grows only inside the left rail and must not enter the gameplay region.

## 7. HUD

HUD remains owned by `Scene01HUD`.

Target height: approximately 160–190 px.

HUD responsibility is only current state:

```text
SCENE 01 · 状态

Arm Vehicle · MOVING
机械臂：持有 1    托盘：0
标准箱：4 / 8
任务：RUNNING

M 移动   X 停止   C 抓放
```

Feedback may add one extra line only when feedback exists.

Responsibility split:

- HUD = what is happening now.
- Tutorial = what should I do next.
- Manual Guide = how controls work.

## 8. Program Workspace

Program Workspace is the main layout change.

The existing side-by-side `AddCommandColumn + SourceColumn` layout must become a single-column rail.

### Default expanded structure

```text
PROGRAM
[Save] [Load] [Export] [RUN]

SOURCE · canonical v2
┌────────────────────────────┐
│ automata_scene01_program 2 │
│ ...                        │
└────────────────────────────┘
语法有效 · n 条语句

▶ ADD COMMAND
```

The Source Editor is primary. Command Builder is secondary.

### Add Command expanded

```text
▼ ADD COMMAND

Vehicle       [Arm Vehicle ▼]

MoveTo        X [ ]  Y [ ]
              [+ MoveTo]

              [+ GrabDrop]

Repeat        × [2]
Target        [statement ▼]
              [+ Repeat]

              [Clear All]
```

This is still only a text-generation convenience layer. It must not become a second Program model.

### Program collapse

`Scene01ProgramUI` may own presentation-only collapsed/expanded state.

Expanded rail: approximately 420–520 px depending on viewport.

Collapsed rail: approximately 48–56 px.

Initial behavior:

- Program is collapsed on first Scene 01 entry.
- Player explicitly expands it when needed.
- Tutorial text may instruct the player to open Program.
- Tutorial must not call Program UI methods to open or close it.

### Source Editor

Remove the current fixed 420 px minimum height as the controlling layout constraint.

Target:

- Vertical expand/fill.
- Practical minimum around 220–260 px.
- Use remaining rail height.

## 9. Input contract

Fullscreen root controls remain non-blocking:

```text
mouse_filter = IGNORE
```

Only actual panels, buttons and editors capture input.

With Tutorial visible and Program visible/collapsed, the central gameplay region must still allow:

- Arm selection.
- Transport selection.
- MoveTo target selection.
- Grid clicking.
- Facing / GrabDrop interaction.

No transparent full-screen child may consume gameplay mouse input.

## 10. Z-order

Preserve existing semantic layering unless a concrete bug requires otherwise:

- Manual/base UI: existing base layer.
- Tutorial: layer 3.
- Program: layer 4.
- HUD: layer 5.

Z-order must not be used as a layout mechanism. Panels should already be geometrically separated.

## 11. Allowed implementation scope

Expected files:

- `scenes/scene_01/components/scene_01_tutorial_ui.tscn`
- `scenes/scene_01/components/scene_01_program_ui.tscn`
- `scenes/scene_01/components/scene_01_hud.tscn`
- `scenes/scene_01/components/scene_01_manual_ui.tscn`
- `scripts/scene_01/scene_01_program_ui.gd`
- optionally minimal presentation-only changes in `scene_01_tutorial_ui.gd`

Do not modify unless a direct blocker is demonstrated:

- Program parser / validator / preflight / runner.
- Lifecycle.
- Scoring.
- Vehicle selection / move / grab-drop domain logic.
- CompileGate semantics.
- ObservableState.
- #58 visual design system.
- #62 shared controller refactor.

## 12. Incremental test acceptance

This layout patch is ready for #21 walkthrough when all are true:

- No overlap among Tutorial/Manual Guide, HUD and Program rail at 1920×1080.
- No overlap at approximately 2264×1274.
- Central gameplay view remains roughly 900–1000 px wide or better on wide desktop.
- Arm, Transport, source pile and StandardBox can be visually inspected without hiding UI.
- Tutorial and Manual Guide remain mutually exclusive.
- Program rail can collapse and expand.
- Source Editor remains canonical mutable authoring truth.
- Add Command does not hold a second Program state.
- HUD remains readable.
- Central gameplay mouse interaction is not blocked by transparent controls.
- No gameplay / scoring / lifecycle / Program execution behavior changes.

## 13. Definition of Done

Implementation is complete only when:

1. The above layout contract is satisfied.
2. Automated tests covering existing Tutorial/Program contracts still pass.
3. The player-visible walkthrough can proceed without first hiding major UI panels.
4. Any further visual-system work is deferred to #58 rather than added to this patch.
