# Automata

3D 网格制物流自动化解谜游戏（Godot 4.7 / GDScript）。玩家指挥机械臂车与运输车搬运方块，也可以直接编写 Program 让车辆自动执行。

当前可玩内容：**Scene 01 · Basic Packing** —— 在 16×10 网格上把方块搬进 StandardBox，填满 8/8 通关。

## 快速开始

```powershell
# 环境：Godot 4.7.2（`godot` 在 PATH 上）
godot --headless --path . --editor --quit   # 首次/干净 worktree 先导入
godot --path .                              # 图形运行
```

操作：左键选车 · `M` 移动 · `A`/`D` 转向 · `C` 抓放 · `X` 停止 · `Q`/`E` 旋转相机。

## 测试与 CI

```powershell
godot --headless --path . --script res://tests/stability/scene_01_lifecycle_state_smoke_test.gd
```

- 全部测试：46 个运行时套件，见 `tests/`；单例退出码即结果。
- CI：`.github/workflows/godot-ci.yml`（导入检查 + 运行时测试，PR/push 默认跑 `tests/stability`，手动 `workflow_dispatch` 可选 full）。
- 本地 `user://` 不可写时 Save/Load 测试会假失败，重定向 `APPDATA` 到可写目录即可复现 CI 结果。

## 目录

```text
scenes/scene_01/   Scene 01 场景、UI 组件、车辆与物件
scripts/           assembly / vehicles / grid / input / objects / camera / scene_01
tests/             运行时测试（stability 为每次 PR 必跑的结构性稳定套件）
docs/              开发上下文、UI 规范、QA 记录
assets/ shaders/   美术素材与地面着色器
```

## 文档入口

- **[docs/context/project_context.md](docs/context/project_context.md)** —— 当前开发上下文：架构、真值归属、手动/Program 闭环、进度与开放议题、已知风险、约定与下一步（新接手或 AI agent 先读这份）。
- [docs/art/aperture_visual_v1.md](docs/art/aperture_visual_v1.md) —— Aperture / Portal 2 视觉方向、调色板、实现状态与下一轮计划。
- [docs/Skill-UI-implement-flow.md](docs/Skill-UI-implement-flow.md) —— 高保真 UI 复刻流程。
- [docs/specs/scene_01_ui_layout_v1.md](docs/specs/scene_01_ui_layout_v1.md) —— UI 布局规范（部分内容已被 #82/#85 实现超越，见上下文文档 §7）。
- [docs/qa/scene_01_final_qa.md](docs/qa/scene_01_final_qa.md) —— #22 Final QA 记录。
- [tests/stability/README.md](tests/stability/README.md) —— 稳定性测试准入与退役规则。
