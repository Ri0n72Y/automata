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

- `Scene01Tutorial`: owns five independent Tutorial goal-completion flags, presentation-only `view_step`, visibility, and the current Program session's minimal attribution profile.
- `Scene01TutorialUI`: tutorial presentation only.
- `Scene01ManualControls`: manual guide presentation + existing input ownership.
- `Scene01HUD`: current gameplay status presentation.
- `Scene01ProgramUI`: Program authoring presentation; collapse/accordion presentation truth is the real Control visibility.
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
- Program rail target width: 460 px.
- Outer margin: 16 px.
- Top content offset: 82 px.
- Vertical bottom margin: 16 px.
- Central gameplay width target: about 1000 px or greater.

### Compact desktop (1600–1919)

- Left rail target width: 320 px.
- Program rail target width: 400 px.
- Program should favor collapsed presentation when necessary.

### Below 1600

No complete responsive redesign is required in this patch.

Minimum behavior:

- Program defaults collapsed and expands to 360 px.
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
SCENE 01 · 教学          目标 n / 5
Page title

Short instruction, approximately <= 3 lines.
本页目标：...（0/1）
场景目标：填满 StandardBox（current/8）

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
Scene 01 · 操作指南       教学   +
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

+ ADD COMMAND
```

The Source Editor is primary. Command Builder is secondary.

### Add Command expanded

```text
− ADD COMMAND

Vehicle       [Arm Vehicle]

MoveTo        X [ ]  Y [ ]
              [+ MoveTo]
────────────────────────────
Rotate        [Clockwise ▼] [+ Rotate 90°]

              [+ GrabDrop]

Repeat        × [2]
Target        [statement ▼]
              [+ Repeat]

              [Clear All]
```

This is still only a text-generation convenience layer. It must not become a second Program model.

### Program collapse

`Scene01ProgramUI` may own presentation-only collapsed/expanded state.

Expanded rail tiers: 360 px below 1600, 400 px at 1600–1919, and 460 px at 1920+.

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
- Practical minimum around 160 px; use remaining rail height when available.
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
- `scripts/scene_01/scene_01_ui_layout_metrics.gd` — immutable rail width metrics only; no mutable state or coordination
- optionally minimal presentation-only changes in `scene_01_tutorial_ui.gd`

Do not modify unless a direct blocker is demonstrated:

- Program parser / validator / preflight / runner. **Exception updated 2026-09-20:** the player walkthrough requires programmable relative 90° rotation with visible simulation-time cost, so the minimal `Rotate` statement is allowed through the existing Program and shared manual rotation chain.
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
- No unrelated gameplay / scoring / lifecycle behavior changes. Program execution changes are limited to the accepted relative `Rotate` command and its shared turn animation described below.

## 13. Definition of Done

Implementation is complete only when:

1. The above layout contract is satisfied.
2. Automated tests covering existing Tutorial/Program contracts still pass.
3. The player-visible walkthrough can proceed without first hiding major UI panels.
4. Any further visual-system work is deferred to #58 rather than added to this patch.


## 13.5. Language baseline — 2026-09-20

Scene 01 当前以**简体中文**作为玩家界面的 canonical copy：

- 所有玩家可见标题、按钮、状态、提示、任务文本、错误反馈和场景内 3D 标签使用中文。
- DSL namespace、命令 token、参数 token、`vehicle_id` 与快捷键名称保持运行时原值，例如 `automata_scene01_program 2`、`moveTo`、`rotate`、`grabDrop`、`clockwise`、`counterclockwise`；这些属于编程语言 contract，不属于 UI 翻译。
- 当前不引入第二套文案表、语言状态 owner 或临时翻译抽象。中文字符串直接作为基准文案。
- 后续英文及其他语言支持应通过统一 localization/i18n 模块抽取这些玩家可见字符串，不修改 gameplay、Program DSL 或 scene ownership。

## 14. Player-walkthrough delta — 2026-09-19 / 2026-09-20

The graphical walkthrough exposed direct player-facing blockers. These are accepted here without expanding into #58 or #62.

### Disclosure controls

Scene 01 expand/collapse controls use `+` for collapsed and `−` for expanded. Triangle disclosure glyphs are removed from Manual Guide, Program Workspace and Debug. The lifecycle play symbol remains a play control, not a disclosure control.

### Program rail / builder

Program rail widths remain 360 / 400 / 460 px. The command builder lives inside its own vertical `ScrollContainer`.

MoveTo and Rotate are visually separated by a divider because MoveTo uses a multi-row parameter block while Rotate is a compact single-row command.

### Tutorial navigation and goals

Tutorial pages are help/presentation, not an unlock chain. `Scene01Tutorial` owns only presentation `view_step` plus five independent historical goal flags:

1. select Arm;
2. manually pick up a block;
3. increase StandardBox count by one manually;
4. complete one Program-owned StandardBox delivery;
5. complete a successful delivery Program that also contains Transport MoveTo.

There is no prerequisite ordering among these five goals. A real gameplay event completes the matching goal whenever it occurs. Previous / Next only browse the five teaching pages. The final DONE page becomes reachable at 5/5.

Tutorial copy must expose explicit task progress such as `箱子计数 +1（0/1）` and the live scene goal `填满 StandardBox（4/8）`. The manual packing page includes the tip that simulation speed can be changed from the top lifecycle island.

Lifecycle Reset resets gameplay and Program runtime state but preserves Tutorial goal history, current `view_step`, and visibility. Reopen and Skip do not mutate goal truth. Tutorial may read current ObservableState only for presentation such as `current/8`; snapshots must never complete historical goals.

### Code editor focus and canonical namespace

A left mouse click outside the Program rail releases GUI focus from CodeEdit so gameplay keyboard commands such as `M` work immediately.

The first source line is the canonical namespace:

```text
automata_scene01_program 2
```

The editor restores/protects this header when an edit attempts to remove it. CodeEdit text remains the only mutable Program authoring truth.

Selecting a source line uses the built-in current-line highlight plus a gutter execution marker so the selected line has a visible line-number-area cue without introducing a second selection model.

### Relative Rotate command

DSL v2 uses one relative rotation command:

```text
[arm_vehicle:rotate] clockwise
[arm_vehicle:rotate] counterclockwise
```

Each Rotate is exactly one 90° turn and matches one manual `D` / `A` action respectively. Absolute north/east/south/west facing is not part of the taught Program surface.

Manual A/D and Program Rotate must call the same vehicle-turn owner. Rotation has a short visible simulation-time animation; it is not an instantaneous runtime-state write. Lifecycle pause/speed therefore also applies to rotation. MoveTo and GrabDrop must reject while that shared turn is active rather than overlapping it.

The command builder may generate Rotate source text, but CodeEdit remains the only mutable authoring truth.

### Deferred visual guidance

Execution-preview guidance is explicitly deferred to a separate issue. No path preview, turn preview, GrabDrop preview extension, Repeat teaching layer, or dynamic command documentation is added in PR #63.

### Deferred block-style command assembly

Pin/slot-based command assembly is explicitly deferred to a separate low-priority issue. PR #63 keeps the current text-first builder and does not add scene-picking parameter pins or another Program model.
