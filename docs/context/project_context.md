# Automata 项目开发上下文

Status: **current as of 2026-10-18**
Purpose: 让新接手的开发者 / AI agent 在不重新通读 124 个脚本的前提下，快速建立对"这个工程现在是什么状态、为什么这样设计、下一步该动哪里"的完整认知。
维护方式：里程碑合并、UI 规范变更、CI 基线变化后更新；过时信息宁可删除，不要保留错误口径。

---

## 1. 项目是什么

| 项 | 内容 |
| --- | --- |
| 项目名 | `automata`（仓库 <https://github.com/Ri0n72Y/automata>，远端账号 Ri0n72Y） |
| 类型 | 3D 网格制物流自动化 + 可视化编程解谜（"写程序指挥车辆搬箱子"） |
| 当前可玩内容 | **Scene 01 · Basic Packing**：16×10 网格，机械臂车（Arm）+ 运输车（Transport）把无限方块堆的方块搬进 StandardBox，填满 8/8 通关 |
| 玩家界面语言 | **简体中文为 canonical 文案**（无 i18n，见 §7） |
| 引擎 | Godot **4.7.2**（本地 `godot` 指向 Steam 版 `D:\Games\Steam\steamapps\common\Godot Engine\godot.cmd`） |
| 渲染 / 物理 | **Forward+**（桌面；`mobile` 回退、`web = gl_compatibility`）、3D 物理引擎 **Jolt Physics**（2026-10-18 由 gl_compatibility 切换，见 [视觉方向 v1](../art/aperture_visual_v1.md)） |
| 脚本 | 纯 GDScript（无 C#、无 GDExtension）；无 autoload，全部靠场景节点 + 显式注入 |
| 主场景 | `res://scenes/scene_01/scene_01_basic_packing.tscn` |
| 导出预设 | 仅 `Windows Desktop`（`export_presets.cfg`，导出到 `build/`） |

产品意图（从议题与文档推断）：先做一个教学/演示性的单关 MVP 验证"手工搬箱 vs 写 Program 自动搬箱"的核心循环，再把同一套车辆/装配/Program 能力推进到真正的关卡内容（Bean Sorting 里程碑 #76）与车辆组装编辑（Assembly #78–#80）。

---

## 2. 仓库与当前工作状态（2026-10-18）

```text
origin/main  f4a7aab  [WIP] Scene 01 P1: static raised platform and partial lab enclosure (#89)  2026-10-08
本地 main    10f6437  refactor(scene-01): unify Operations and Program right rail (#85)            2026-10-05  ← 落后 3 个 squash 提交
当前 checkout codex/86-scene01-lab-platform-p1  HEAD 93f5357                                      2026-10-08
```

- **当前分支的文件树与 `origin/main` 完全一致**（`git diff HEAD origin/main` 为空）。该分支对应已 squash 合并的 PR #89，HEAD 不是 origin/main 的祖先只是 squash 造成的表象。
- 工作区唯一未提交改动：`.gitignore` 追加 `.dsh-scope.*`（DSH 工具产物忽略规则，无换行结尾）。除此之外工程干净。
- **约定：新工作从 `origin/main` 起新分支**，不要从本地 `main` 起（落后）。历史分支名规约 `codex/<issue>-<slug>`，提交信息规约 `type(scope): 中文/英文摘要 (#PR)`，如 `refactor(scene-01): unify Operations and Program right rail (#85)`。
- 本地 `.dsh-scope.json` 声明了技能白名单与 `godot` MCP；本会话未挂载 godot MCP 工具（未确认是否为必需）。

### CI

- 工作流 `.github/workflows/godot-ci.yml`（GitHub Actions，ubuntu-latest，job timeout 5 min）。
- 两步：`godot --headless --path . --editor --quit` 导入检查 + 逐个 `godot --headless --path . --script res://tests/...` 运行时测试，每例 30s 超时。
- **失败判定是"退出码非 0 或日志命中 `GODOT_FATAL_LOG_PATTERN`"**。该正则含 `ObjectDB instances were leaked` / `resources still in use at exit` / shader 错误等，比早期只看 `SCRIPT ERROR:` 严得多（该收紧由 #87 引入）。
- PR/push(main) 默认只跑 **stability 套件**（`tests/stability`，16 例）；手动 `workflow_dispatch` 选 `full` 才跑全部。
- 最近 main 推送 CI：run `37792191695`（#574，2026-10-08）**success**，导入 PASS、stability 16/16。
- 本地复现全量套件：见 §8。

---

## 3. 目录与文件地图

```text
project.godot                 # 主场景、输入映射、渲染器、Jolt
export_presets.cfg            # 仅 Windows Desktop
.github/workflows/godot-ci.yml

assets/                       # 原始素材
  scene_01/*.png              # 256×256 地面 albedo/normal、警示贴图（#87 美术切片，低分辨率占位级）
  scene_01/meshes/*.obj       # rounded_shell / beveled_panel：合并网格的几何来源（场景已不直接引用）
  scene_01/vehicles/*.res     # 合并后的车辆网格（每车 1 个 Mesh、4 个 surface，生成产物）
  scene_01/environment/*.res  # 合并后的实验室环境网格（1 个 Mesh、9 个 surface，生成产物）
  ui/icons/*.svg              # play/pause/reset/chevron/status_dot
  ui/icons/*.svg.import       # DPITexture 导入契约，需提交
tools/                        # 网格生成脚本（build_vehicle_meshes.gd / build_environment_meshes.gd）

scenes/scene_01/
  scene_01_basic_packing.tscn           # 主场景（装配总入口）
  scene_01_vehicle_showcase.tscn        # 无引用的孤立展示场景（可考虑删除）
  components/                           # UI 与场地组件
    scene_01_field_surface.tscn         # 16×10 地面 + 边界警示 + GroundBody（模型驱动校验）
    scene_01_floor_backdrop.tscn        # 200×200 背景地面
    scene_01_lab_platform_environment.tscn  # 纯 MeshInstance 实验室平台/玻璃围挡（无碰撞）
    scene_01_camera_lighting.tscn       # 正交相机 + 双方向光 + WorldEnvironment
    scene_01_hud.tscn / scene_01_operations_panel.tscn / scene_01_lifecycle_controls.tscn
    scene_01_debug_ui.tscn / scene_01_program_ui.tscn / scene_01_ui_theme.tres ...
  objects/standard_box.tscn / infinite_block_pile.tscn / standard_block_placeholder.tscn
  vehicles/arm_vehicle_placeholder.tscn / transport_vehicle_placeholder.tscn
  vehicles/definitions/*.tres           # 车辆静态配置真值
  materials/*.tres                      # 10 个 PBR 材质
shaders/scene_01/*.gdshader             # 地面十字/警示/背景表面着色器（instance uniform 驱动）

scripts/                      # 74 个 class_name，按域分包
  assembly/                   # 装配定义→编译→能力→校验（9 个类）
  vehicles/                   # VehicleDefinition/RuntimeState/Actor/Move/GrabDrop/Pathfinder/Tray
  grid/                       # GridModel、GridTileView、GridDebugView
  input/                      # 选择/移动/抓放三个控制器 + 可用性常量
  objects/                    # StandardBlock/StandardBox/InfiniteBlockPile/GroundBlockField/接口
  camera/                     # Scene01CameraRig（正交四向 90° 环绕）
  scene_01/                   # Scene 01 编排层（32 个脚本，见 §4）

tests/                        # 46 个运行时测试（Full Suite 口径）
  support/contract_test.gd    # 断言基类 expect_* / finish()
  fixtures/                   # 测试替身
  stability/                  # 每次 PR 必跑的 16 个结构性稳定测试（准入规则见 tests/stability/README.md）
  scene_01/ (20) input/ (5) vehicles/ (3) grid/ (2)

docs/
  context/project_context.md            # 本文
  specs/scene_01_ui_layout_v1.md        # UI 布局规范（部分已滞后，见 §7）
  qa/scene_01_final_qa.md               # #22 Final QA 记录（停在 09-25）
  Skill-UI-implement-flow.md            # 高保真 UI 复刻流程（15 节，实际工作的 UI 方法论）
.reasonix/skills/godot-automated-playtest/SKILL.md  # headless 模拟玩家操作的方法与项目断言点
```

---

## 4. 运行时架构

### 4.1 场景装配与启动顺序

`scene_01_basic_packing.tscn` 根节点 `Scene01BasicPacking` 挂 `scene_01_mission_controller.gd`，继承链：

```text
scene_01_controller.gd (Node3D, 网格/相机/选择/移动基座)
  └── scene_01_lifecycle_controller.gd (READY/RUNNING/PAUSED + 模拟速度 + 首命令自动起跑)
        └── scene_01_mission_controller.gd (StandardBox 计数 → Mission 完成/elapsed)
```

`SceneRoot/` 下：`Scene01AssemblyCompileGate`、`Scene01ObservableState`、`Scene01ProgramRunner`、`Scene01ScoreTracker`、`Scene01Tutorial`、`GridRoot`（场地/材质/相机控制器/选择/移动/抓放/网格选择 + 预览）、`RobotRoot/Scene01VehicleManager`+两车、`ObjectRoot`（`grid_transform_follower.gd` 跟随 GridRoot）→`Scene01ObjectManager`+堆/箱、`CameraRoot`。UI 与根平级：`HUDRoot`(layer5)、`OperationsUIRoot`(layer4，内含 Program)、`UIRoot`(操作指南)、`LifecycleUIRoot`、`DebugUIRoot`。

启动顺序：根 `_enter_tree` 建 `GridModel` → 子节点 `_ready`（CompileGate 收车管、Runner 经 `../..` 拿控制器并配 executor、Tutorial 连信号）→ 根 `_ready` 配置车辆/场地/相机/输入控制器并复原基线。依赖注入四种混用：`@export NodePath`、`%UniqueName` @onready、`get_parent/get_node`、运行时 `configure(...)`。

### 4.2 唯一真值（single source of truth）

| 真值 | 拥有者 | 说明 |
| --- | --- | --- |
| 车辆运行态 | `VehicleRuntimeState`(RefCounted) | anchor_cell / facing / motion_state / 背负物 / 托盘；`VehicleActor` 只是投影，`sync_from_state()` 只读 |
| 单次移动进度 | `MoveCommand` | PLANNING→MOVING/WAITING/BLOCKED；路径终点必须=目标、相邻步距=1 |
| 物品归属 | `StandardBlock` 的 WeakRef owner | 任何时刻只属于一个 source / receiver / 车辆手 / 托盘 |
| 网格几何 | `GridModel`（由 `Scene01Controller` 持有） | node ready 后几何不可变，改动会 push_error 并回滚导出值 |
| 装配能力 | `AssemblyCompileResult`（`Scene01AssemblyCompileGate._compiled_results`） | 全部车辆编译成功才整批发布，失败不发布部分结果 |
| 生命周期/模拟时间 | `Scene01LifecycleState` | READY/RUNNING/PAUSED + 速度 0.5/1/2/4；用 `timer` + delta 缩放，**不碰 `Engine.time_scale`** |
| Mission | StandardBox 当前数/容量（8，初始 3） | 完成时冻结 elapsed |
| 计分 | `Scene01ScoreTracker` | Mission elapsed + 首 RUNNING 时编译组件数 + 手动/自动时间区间 |
| Program 源码 | `CodeEdit` 文本 | 首行 `automata_scene01_program 2` 为 canonical namespace；Builder 只写文本，不建第二份语句模型 |
| UI 只读投影 | `Scene01ObservableState` | 订阅车辆/箱/Mission 信号后统一广播，HUD/Tutorial 消费 |

### 4.3 手动玩法闭环与输入

| 按键 | InputMap action | 行为 |
| --- | --- | --- |
| 左键 | — | 选车（`VehicleSelectionController`）/ 在 MoveTo 目标模式中选格 |
| `M` | `vehicle_move_command` | 进入/退出 MoveTo 目标模式（也可点 Operations 面板） |
| `X` | `vehicle_stop_task` | 停止当前任务 |
| `C` | `vehicle_grab_drop` | 抓/放（朝向前方交互格；唯一目标解析 + 失败回滚） |
| `A` / `D` | `vehicle_rotate_counterclockwise` / `clockwise` | 相对 90° 转身（0.3s 动画，`TURN_DURATION_SECONDS`） |
| `Q` / `E` | `camera_rotate_clockwise` / `counterclockwise` | 相机 90° 环绕（校验 GridRoot 变换相关坐标） |

链：左键选中 → `M` 进入 live-target → 点击格 → `GridSelectionController.selection_confirmed` → `VehicleMoveController.request_vehicle_move` → `GridPathfinder` BFS 四方向最短路径 → `MoveCommand` → `VehicleActor.start_move` → `VehicleMoveController._physics_process` 统一推进（多车连续扫掠 AABB 碰撞，冲突则退到最近安全点 cancel→BLOCKED）。

抓放链：`C` → `resolve_target_for_vehicle`（静态堆/StandardBox 接口、车辆 Tray 接口、地面 GroundBlockField 回退）→ `GrabDropCommand.execute`（抓取失败退回原 receiver，放下失败重新 claim 回手臂；Arm 有 `can_grab`，Transport 只有 `has_tray`）。

### 4.4 Program 系统

源码 DSL（v2，首行固定 namespace）：

```text
automata_scene01_program 2
[arm_vehicle:moveTo] 5 3
[arm_vehicle:rotate] clockwise
[arm_vehicle:grabDrop]
[transport_vehicle:moveTo] 6 3
repeat 2 3
# 注释
```

运行链：ProgramUI Run → `Scene01ProgramRunner.start_program(snapshot)` → Preflight（语法校验、目标可通行、按语句收集每车 required capabilities 写入 CompileGate）→ CompileGate 逐车编译 + `ProgramCapabilityValidator`（缺能力则整批拒绝）→ 执行器逐句调用与手动同一套 Move/Rotate/GrabDrop 控制器（Program 不改玩家选择、不持有车辆/物体/Mission 真值）。失败时 ProgramUI 把 reason 映射成中文 + 源码行号；**能力失败的反馈只显示笼统句子，不展示具体 compile 诊断**（已知体验缺口）。

### 4.5 装配 → 能力链路

```text
VehicleDefinition (.tres: capability_tags / footprint / speed / tray_capacity)
  → Scene01AssemblyDefinitionAdapter（每车 1 个 "vehicle" 根组件，映射 can_move/can_rotate/can_grab/has_tray）
  → AssemblyCompiler（按 assembly_id+revision 缓存，结构变化报 revision_content_mismatch）
  → AssemblyCapabilities { can_move, can_rotate, grab_drop }
  → ProgramCapabilityValidator（语句→能力：moveTo→can_move, rotate→can_rotate, grabDrop→grab_drop）
```

Arm：`can_move/can_rotate/can_grab/can_carry`，无托盘，可执行抓放。Transport：`can_move/can_rotate/can_carry/has_tray`，**没有 can_grab**，Transport 的 GrabDrop 语句会被能力校验拒绝，它只作为 Arm 的托盘取放目标。编译缓存必须显式 `invalidate_vehicle` 才能在运行期改定义。

### 4.6 UI 现状（三区布局）

```text
顶部：lifecycle 胶囊（状态/时间/播放暂停/重置/0.5×-4×）      右上：Debug（默认折叠）
左栏：HUD 状态卡（240px，可折 44px）内含 Tutorial / 操作指南互斥 section
右栏：Operations/Program 统一单栏（日常 240px；作者模式 360/400/460 @1600/1920 断点），Program 默认收起
中间：保留完整玩法视野；所有全屏根 Control `mouse_filter=IGNORE`
```

主题统一 `scene_01_ui_theme.tres`（HUD/Ops/Lifecycle），Program 继承 Ops，滚动条独立主题。2026-10-18 起 UI 采用 Aperture 视觉语言（近白面板、圆角 3、1px 冷灰边框、蓝/青小面积强调、等宽代码字体），**布局、节点结构与面板几何未变**。主题与图标细节见 [视觉方向 v1](../art/aperture_visual_v1.md)。`docs/specs/scene_01_ui_layout_v1.md` 是 #21/#63 时代的规范，**部分已滞后于 #82/#85 的实现**（左栏宽度、Tutorial 独立 slot、折叠符号、Program 折叠形态等，见 §7）。

### 4.7 教学与评分

Tutorial 五个互相独立的目标（无先后）：选中 Arm；非 RUNNING 时手动拾取方块；非 RUNNING 时 StandardBox +1；一次成功 Program 内含"Arm moveTo + Arm grabDrop + 箱 +1"；目标 4 且程序含 Transport moveTo。Previous/Next 只翻 5 页教学，5/5 才可进 DONE。Reset 保留目标历史与页码；Skip/Reopen 只改可见性；Tutorial 仅内存，不落盘。

结果面板（Mission COMPLETED 时）：完成时间（模拟时间）、组件数（首 RUNNING 时各车组件数，当前 2）、自动化率（自动区间/（自动+手动））。

### 4.8 视觉与网格管线（2026-10-18 起）

- 视觉方向与调色板、Aperture 规则见 [aperture_visual_v1.md](../art/aperture_visual_v1.md)。
- 车辆与实验室环境都使用**静态合并网格**（generated `.res`），源脚本在 `tools/`：
  - `tools/build_vehicle_meshes.gd` → `assets/scene_01/vehicles/*_mesh.res`（每车 1 个 Mesh、4 surface：白/深色/橡胶/青）。
  - `tools/build_environment_meshes.gd` → `assets/scene_01/environment/aperture_environment_mesh.res`（9 surface，自动跳过 hidden 节点）。
- 车辆场景仍需保留：`VisualRoot`（挂 `VehicleStateVisual`）、`VisualRoot/VehicleSelectionArea`（含 CollisionShape3D）、`VisualRoot/DebugLabel`；运输车还有 `TraySlots`/`TrayCountLabel`，机械臂有 `CarryWarning`。合并网格挂 `VisualRoot/BodyMesh`。
- 环境场景保留 `StaticShell`（合并网格）、`ChamberNumber`/`ChamberCaption`（Label3D）、`DustMotes`（粒子）。
- `aperture_panel_wall.gdshader` 按法线选择面板轴向（水平轴沿墙走向），因此墙体可以任意旋转或合并。
- 性能基线（1920×1080，ready 场景）：draw call **364 → 149**（−59%），其中车辆节点约 60×2 → 1×2。
- 限制：本机命令沙箱以 Low 完整性运行，无法写 `assets/`、`scenes/components/`、`docs/`、`tests/`；重新生成网格需用更宽权限的会话跑上述脚本（CI/普通机器不受限）。

### 4.9 小车组装 / 蓝图模块（2026-10-18 起）

- 设计文档：[vehicle_assembly_v1.md](../design/vehicle_assembly_v1.md)（底盘/轮组/工作件目录、能力→动作、蓝图 UI、综合关与自复制路线）。
- 数据模型与投影链路（已实现）：
  - `scripts/assembly/vehicle_part_definition.gd`、`vehicle_part_catalog.gd`（3 底盘 / 3 轮组 / 2 工作件 + 4 模板 + 成本）、`vehicle_blueprint.gd`（能力/成本/重量/托盘推导、序列化）。
  - `VehicleBlueprint → VehicleDefinition(kind=ASSEMBLED) → Scene01AssemblyDefinitionAdapter(blueprint_vehicle_preset) → AssemblyCompiler / ProgramCapabilityValidator`。
  - 全向底盘 `can_strafe`：MoveTo 不转身；托盘上限 = `min(module.tray_capacity, floor(chassis.max_payload / 2kg))`。
- 界面与部署（已实现）：
  - `scene_01_blueprint_ui.tscn` + `scripts/scene_01/scene_01_blueprint_ui.gd`：`B` 键开关，右侧覆盖面板，槽位下拉 / 动作投影 / 速度重量成本 / 保存读取 / 部署（READY 限定 + 网格 ghost 合法性）。
  - `Scene01VehicleManager.deploy_blueprint()`：实例化 `blueprint_vehicle_placeholder.tscn`（合并网格按工作件选择）、动态注册；`Scene01Controller.deploy_blueprint_vehicle()` 重配置选择/移动/抓放/Observable/CompileGate。
  - `Scene01ObservableState.register_dynamic_vehicles()` + HUD 通用读取：部署车可被选中、HUD 显示状态/载荷、Reset 保留并回到部署格。
- 验收方式：`tools/acceptance_blueprint_flow.gd` 全流程验收（部署→编译→Program 移动→能力差异→HUD→Reset）；**不再为装配模块新增防御性单测**（用户 2026-10-18 指示），原 46 例 legacy 套件保留。
- **待实现**：综合关「装配站」（预算/评分/2×2 装配台）、部署 ghost 的图形细节、多蓝图库、`fabricator` 自复制终局。

---

## 5. 进度现状

### 5.1 已完成

- **Scene 01 MVP 全链关闭**：议题 #1–#22（#2–#21 功能、#22 Final QA）全部 closed；合并 PR #47–#67（装配编译、生命周期、HUD、Program MVP/多车源码、Tutorial、评分、Final QA）。
- **UI 信息架构收敛**：#82（明亮实验室 UI 基线）、#85（Operations + Program 合并为统一右栏）已合并；#58 UI 信息架构随 #22 折叠完成。
- **美术支线 #86 P1 已合并**：PR #87（floor/双车视觉切片）、#88（地面与双车视觉打磨）、#89（静态抬升平台 + 部分实验室围挡）。地面从"逐格结点"改为 **model-driven 单面 + shader instance uniform**（删除 `grid_row_*`、`grid_tile_static`、`field_12x8/16x10`，新增 `scene_01_field_surface.tscn` 与 `grid_surface_view_contract_test.gd`；`grid_tile_view.gd` 现在对 authored 场地的尺寸/原点做 fail-closed 校验）。
- **质量基线**：本地 Full Suite **46/46 PASS**（scene_01 20、stability 16、input 5、vehicles 3、grid 2）；main CI 绿；无 ObjectDB/resource 泄漏告警（旧 assembly 泄漏已消失）。

### 5.2 进行中 / 未合并

- **#86 P2（物件与容器视觉）有两条并行 WIP Draft PR**：`#90 codex/86-p2-object-visuals`、`#91 codex/86-scene01-object-visuals-p2`，均 CI 绿但都未合并，**内容重叠、存在美术分叉风险，需择一收口**。
- #86 P3 光影、P4 背景尚未开始。

### 5.3 开放议题（21 个）

| 组 | 议题 | 含义 |
| --- | --- | --- |
| 美术 | #86 | Scene 01 模型/材质/灯光向效果图收敛（P1 done，P2 WIP，P3/P4 todo） |
| Bean Sorting 里程碑 | **#76**（里程碑）+ #68–#74、#77、#81 | 下一关内容：豆子按克计量、目标箱编号洗牌、任务映射 HUD、0–3000 分结算、通用 Mission Framework、可玩完成门 |
| Assembly 组装 | #78/#79/#80 | ModuleCatalog/可编辑装配模型 → 最小车辆组装工作区 → 玩家装配实例化为可运行车辆 |
| 技术债 / backlog | #62 | 拆分 Vehicle input/command/pathfinding 巨型 controller（当前 `vehicle_move_controller.gd` 1024 行） |
| | #64/#65 | Program 命令视觉预览/执行指引；拼装式参数编辑与场景拾取 |
| | #66 | i18n：中文基准文案抽英文等语言 |
| | #49 | GroundBlock 动态 occupancy 接入规划（P3） |
| | #34/#17 | 连续移动操控模式；高级控制流与渐进解锁 |

### 5.4 门禁与文档缺口

- `docs/qa/scene_01_final_qa.md` 停在 2026-09-25，"AUTOMATED PASS / PLAYER WALKTHROUGH PENDING"，§5 图形验收清单仍未勾选、§6 还有 3 项未勾。**其中"无未合并回归修复""#1 可关闭"实际已兑现**（#1/#22 已 closed，main CI 绿），**真正缺口只剩：当前 head 的图形 walkthrough 书面记录 + 文档同步**。
- 本次调查（2026-10-18）未发现任何自动测试阻塞项。

---

## 6. 开发约定（动代码前必读）

1. **测试策略：流程验收优先（2026-10-18 用户指示）**：不为新功能堆防御性单测/契约测试；优先写"能跑完整流程"的验收脚本（如 `tools/acceptance_blueprint_flow.gd`）和真实图形截图。原 `tests/` 的 46 例 legacy 套件保留，用于守住既有契约与 CI；新增测试只有在保护真实高风险边界时才加。
2. **contract-first，单一真值**：新功能先定义 owner 与契约（Resource/RefCounted + 信号/查询接口），UI 只能投影，不得保存第二份业务状态（`docs/Skill-UI-implement-flow.md` §8）。
3. **Ponytail 倾向**：优先删/复用而不是新增抽象；禁止为方便 UI 新增全局 UI 协调器、状态镜像或兼容层。历史上有专门的重构提交（`1b45698 refactor: apply Ponytail simplification pass`）与议题 #62。
4. **稳定性测试准入**：`tests/stability` 只收"结构性脆弱依赖"的测试（多源汇聚、所有权转移、生命周期/时序、fail-closed 等），准入与退役规则见 `tests/stability/README.md`；功能/组合/E2E 放 Full Suite 或流程验收。
5. **测试骨架**：`extends SceneTree` + `tests/support/contract_test.gd`；场景实例化后 `await process_frame`/`physics_frame` 再取节点；输入用 `root.push_input`（前先 await）或直接调控制器；`test.finish(self, "suite name")` 决定退出码。详见 `.reasonix/skills/godot-automated-playtest/SKILL.md`。
6. **中文 canonical 文案**：玩家可见字符串直接写中文，DSL token / vehicle_id / 快捷键名保持原值；i18n 延后到 #66，不引入临时翻译抽象。
7. **UI 复刻流程**：先冻结范围 → Reference+Current 双图 → 差异表 → 组件角色/视觉权重 → design contract（logical px + 比例）→ 改 presentation tree → CI + 同屏截图逐区域收敛。禁止用 magic number 拼旧布局、禁止用 Unicode 字符冒充 control icon（用 `assets/ui/icons/*.svg` + DPITexture）。
8. **场景/资源**：静态内容用 `.tscn`/`.tres` 序列化（编辑器可见），运行期只创建"可变运行态 / 源码派生投影 / 玩法生成物"；`unique_name_in_owner = true` 用于 `%` 引用。
9. **提交与分支**：`codex/<issue>-<slug>` 分支；`type(scope): 中文摘要 (#PR)` 提交；PR 合并方式为 squash（历史如此）。
10. **导入缓存**：`.godot/` 已在 gitignore；干净 worktree 首次跑 Godot 前需 `godot --headless --path . --editor --quit`（或 `--import`），否则 `class_name` 解析失败。

---

## 7. 已知问题与风险（按可信度标注）

| # | 问题 | 证据 | 影响 / 建议 |
| --- | --- | --- | --- |
| R1 | **转身被双重推进（已复现）**：MoveTo 路径转角时 `VehicleMoveController._advance_managed_vehicles` → `actor.advance_move()` → `advance_turn(delta)`，同一帧 `VehicleGrabDropController._advance_turns()` 又给所有 `is_turning()` 车辆 `advance_turn(delta)` → **移动中的 90° 转身只用约 0.15s（9 物理帧@60Hz），而手动 A/D 转身是正常的 0.3s（18 帧）**。纯手动旋转不经过 Move 控制器，不受影响。 | 代码：`vehicle_move_controller.gd:493-535,591-594`、`vehicle_actor.gd:119-171,182-195`、`vehicle_grab_drop_controller.gd:61-62,174-180`。2026-10-18 用临时 headless 脚本实测：`A TURN_FRAMES=9`（MoveTo，facing 1→目标需转向）vs `B TURN_FRAMES=18`（手动 `rotate_selected_vehicle(1)`），同一 Arm、同一 60Hz physics | **确认缺陷，非推测**。最小修复：`_advance_turns` 跳过 `runtime_state.motion_state == MOVING` 的车辆（移动中的转身归 MoveController），或反过来让 `advance_move` 不推进 turn——二者只能有一个 owner；修复时补一条双控制器同帧回归测试 |
| R2 | `Scene01ProgramUI._on_run()` 忽略 `start_program` 返回值：已在运行时（runner 直接 return false 且不发 execution_failed）点 RUN 会无反馈，状态栏停留旧文案 | `scripts/scene_01/scene_01_program_ui.gd:112-118`、`scene_01_program_runner.gd:47-50` | 小体验缺陷，补一行拒绝文案即可 |
| R3 | UI 规范与实现漂移：`scene_01_ui_layout_v1.md` 仍写左栏 360/320、Tutorial 独立 slot/layer3、`+/-` 折叠符号、Program 收起 48–56px；实现为固定 240 左栏、Tutorial 嵌入 HUD、chevron 图标、Program 隐藏但右栏保留 Operations | spec §5/§6/§8/§14 vs `scene_01_hud.gd:86-108`、`ui_layout_metrics.gd:4-25`、`tutorial_ui.gd:70-77`；测试锁 240（`tests/scene_01/scene_01_sidebar_ui_contract_test.gd:124`） | 文档滞后为主。若按 spec 恢复宽度需同步迁移测试 |
| R4 | 本地 Steam 版 Godot 的 `_editor_data` 写不进 Steam 目录，导入后进程以 `0xC0000005` 退出并报 `Safe save failed`；同 tree 复制到可写目录 fresh import exit 0，CI 导入 PASS | 本次调查实测 + CI run #574 | **环境问题非工程错误**。正常桌面会话先清 `.godot` 再验；CI 才是导入准绳 |
| R5 | `user://` 不可写时 Save/Load round-trip 测试会读到历史遗留文件而"假失败"（默认沙箱 45/46，重定向 APPDATA 后 46/46） | `tests/scene_01/scene_01_program_workspace_test.gd:108`；`scripts/scene_01/scene_01_program_workspace_support.gd:37-56` | 建议测试改用每轮隔离临时路径，避免固定 `user://scene_01_program.txt` |
| R6 | #86 P2 两条 Draft PR 重叠（#90/#91），长期并行会分叉 | `gh pr list` | 择一收口，另一条关闭或 rebase 到胜出实现 |
| R7 | headless 是 dummy renderer：shader 不实际编译绘制，layout 测试只验结构/几何 | CI 工作流 + 图形验收清单 | 视觉/手感/遮挡只能人工图形 walkthrough；lab platform 无碰撞、无测试引用，需图形客户端确认是否遮挡玩法 |
| R8 | i18n 缺失：172 处中文字面量散在 `.gd`/`.tscn`，0 处 `tr()` | grep 统计 | 显式延后（#66），但新增文案继续直接写中文 |
| R9 | 无根 README / 无仓库级入口文档；`docs/qa` 与 UI spec 都停在 9 月中下旬 | 本次调查 | 已补 `README.md` 与本文；QA 文档待当前 head 的图形验收后更新 |
| R10 | `scenes/scene_01/scene_01_vehicle_showcase.tscn` 无任何引用；车辆/方块/箱场景仍名 `*_placeholder` | 引用搜索 | 无害清理项 |
| R11 | UI 图标的 `.svg.import` 在本机指向非标准缓存名 `*-ui1.dpitex`（沙箱无法覆盖 9/25 旧缓存所致）；干净副本 `godot --import` 会自动归一化回 canonical 路径，CI 不受影响 | 2026-10-18 实测干净副本导入 exit 0 且 `.import` 被重写为 canonical | 无需处理；若提交后 CI/他人机器首次导入出现图标差异，删除对应 `.godot/imported` 缓存重导即可 |
| R12 | 视觉参考图与中间截图在 `.dsh-visual/`（已 gitignore）。参考图版权归 Valve/Portal Wiki，仅作风格研究，不得进入 `assets/` | `.gitignore` | 新会话需要参考时重新采集，或读 [视觉方向 v1](../art/aperture_visual_v1.md) |
| R13 | 车辆/环境视觉是**生成产物**（`assets/scene_01/{vehicles,environment}/*.res`）：手工改 `.tscn` 里的网格不会生效，必须改生成脚本后重跑；车辆脚本可反复运行，**环境 bake 是单向的**（合并后场景只剩 `StaticShell`，再跑会中止，需以 git 历史 authored 场景为起点或另写程序化环境构建）；本机命令沙箱 Low 完整性无法写 `assets/`、`scenes/components/`、`docs/`、`tests/`，重新生成需更宽权限会话 | `tools/build_vehicle_meshes.gd`、`tools/build_environment_meshes.gd`；本次实测 150 draw call | 正常机器/CI 无此限制；改车形先改脚本，再跑截图对比 |

---

## 8. 如何运行与验证

```powershell
# 0) 环境
godot --version        # 期望 4.7.2.stable.steam

# 1) 导入（干净 worktree 必须先做一次）
godot --headless --path . --editor --quit

# 2) 图形运行（人工验收）
godot --path .

# 3) 单个测试（退出码即结果）
godot --headless --path . --script res://tests/stability/scene_01_lifecycle_state_smoke_test.gd

# 3.5) 重新生成合并网格（改车形/环境后；需要可写 assets 的会话）
godot --headless --path . --script res://tools/build_vehicle_meshes.gd
godot --headless --path . --script res://tools/build_environment_meshes.gd

# 3.6) 蓝图装配模块流程验收（部署 → 编译 → Program 移动 → 能力差异 → HUD → Reset）
godot --headless --path . --script res://tools/acceptance_blueprint_flow.gd

# 4) 全量套件（CI full 口径：tests/**/*_test.gd 与 *_smoke_test.gd，排除 fixtures/support）
Get-ChildItem -Recurse -File tests -Include *_test.gd,*_smoke_test.gd |
  Where-Object { $_.FullName -notmatch '\\fixtures\\|\\support\\' } |
  ForEach-Object {
    $rel = $_.FullName.Substring((Get-Location).Path.Length + 1) -replace '\\','/'
    $out = godot --headless --path . --script ("res://" + $rel) 2>&1
    if ($LASTEXITCODE -ne 0 -or ($out -match 'SCRIPT ERROR:|Parse Error:|resources still in use at exit')) {
      Write-Output "FAIL $rel"; $out | Select-String -Pattern 'ERROR|failed' | Select-Object -First 5
    } else { Write-Output "PASS $rel" }
  }

# 5) 沙箱/CI 模拟（user:// 可写；否则 Save/Load 用例会假失败）
$env:APPDATA = Join-Path $env:TEMP 'automata-appdata'; New-Item -ItemType Directory -Force $env:APPDATA | Out-Null
```

判定：输出含 `"<suite> passed."` 且退出码 0；日志命中 CI fatal 正则即失败。

---

## 9. 建议的下一步（按价值/阻塞排序）

> 2026-10-18：视觉 v1 已完成（渲染器/光照、场地与材质、车辆与物件、UI、性能合并、图形 walkthrough 六轮），阶段性目标收口；以下为后续可选工作。

1. **补当前 head 的图形 walkthrough 书面记录**（`docs/qa/scene_01_final_qa.md` §5）：截图已在 `.dsh-visual/captures/pass25_*`，把结论同步进 QA 文档并更新 §6 勾选项。
2. **环境可编辑性债务（R13）**：为环境写一个程序化构建脚本（或在 git 历史 authored 场景上重建），让后续墙面/道具修改不必依赖一次性 bake。
3. **车辆再细化**（用户反馈驱动）：轮拱/悬架、面板缝更真实、可选更圆润或更机械的风格分支。
4. **修 R1 双重转身**（已复现的玩法手感缺陷）：只保留一个 turn owner 并补回归测试。
5. **收口 #86 P2**：#90/#91 择一，合并后再开 P3 光影 / P4 背景。
6. **启动 Bean Sorting 里程碑 #76**：建议顺序 #68 → #69 → #70 → #71/#73 → #72 → #74 → #81；#77 与 #73 有重叠，先对齐。
7. **Assembly 线 #78→#79→#80**：在 Bean Sorting 关卡内容成型后再做。
8. **小额债务**：R2 一行修复、R5 测试隔离化、R10/R11/R12 清理；#62 巨型 controller 拆分单独排期。
9. **提交**：当前工作区有大量未提交改动（视觉 v1 + 工具脚本 + 合并网格），建议按 渲染/光照、环境 bake、车辆重建、UI 主题、交互配色、文档 六组拆 commit。

---

## 10. 速查常量

| 项 | 值 |
| --- | --- |
| 渲染器 | `forward_plus`（桌面）/ `mobile`（回退）/ `gl_compatibility`（web）；2026-10-18 由 gl_compatibility 切换 |
| 主场景网格 | 16 × 10，cell_size 1.0（`GridModel` 默认 12×8，以场景导出为准） |
| 格子坐标 | `cell(x,y)` → 世界 `(x+0.5, 0, y+0.5)*cell_size + grid_local_origin`；y 对应世界 Z；默认外圈 BOUNDARY 不可走 |
| 朝向 | NORTH/EAST/SOUTH/WEST = 0..3；`Basis = grid_basis * Basis(UP, -facing*PI/2)` |
| StandardBox | capacity 8，initial_count 3，交互格 `(15,3)` |
| 车辆 | Arm：footprint 1×1，base_speed 2.0，携物速度 ×0.25，能力 move/rotate/grab/carry；Transport：1×1，speed 2.4，托盘容量 8，能力 move/rotate/carry/has_tray |
| 转身 | 0.3 s / 90° |
| 模拟速度 | 0.5× / 1× / 2× / 4×；默认 1× |
| Program | 首行 `automata_scene01_program 2`；`[id:moveTo] x y`、`[id:rotate] clockwise|counterclockwise`、`[id:grabDrop]`、`repeat <n> <1-based 语句号>` |
| 控件节点路径 | `SceneRoot/GridRoot/VehicleMoveController`、`.../VehicleGrabDropController`、`.../GridSelectionController`、`.../VehicleSelectionController`；根挂 `scene_01_controller.gd` |
| 关键 UI 尺寸 | lifecycle 胶囊 350×42 top12；HUD 240（折叠 44）top82；Program 右栏 240 / 360 / 400 / 460 |
| 测试 | 46 例；stability 16 / scene_01 20 / input 5 / vehicles 3 / grid 2 |

---

## 11. 本文的证据边界

- 架构与契约描述来自**代码阅读 + 现有测试 + 场景文件**，引用标注到文件:行号，可复查。
- 进度与议题状态来自 `git log`、`gh issue/pr/run list`（2026-10-18 查询）。
- 本地测试结论来自 2026-10-18 在 Windows + Godot 4.7.2 上按 CI 规则实跑（46/46），与 CI #574 的 stability 16/16 一致。
- R1（双重转身）**已用临时 headless 脚本运行时复现**（MoveTo 期间 9 帧 vs 手动 18 帧，见 §7）；其余风险均可在本地复现或已有 CI 记录。
- 未覆盖：图形观感、手感、遮挡、性能；这些只能由真实图形客户端验收。
