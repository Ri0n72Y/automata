# 小车组装与蓝图系统 v1（设计文档）

Status: **实现中**（数据模型/目录/契约已完成；蓝图编辑 UI、关卡内布置与综合关待实现）
Scope: 新游玩模块 —— 用底盘 + 轮组 + 工作件组装小车蓝图，把蓝图车布置进关卡，并用 Program 编程完成任务；终局是"自复制机械"。
相关代码：`scripts/assembly/vehicle_part_definition.gd`、`vehicle_part_catalog.gd`、`vehicle_blueprint.gd`、`tests/stability/blueprint_contract_test.gd`
调研依据：同类游戏底盘/组装 UX/自复制结构（来源见 `.dsh-visual/research/assembly.md`，本地参考不入库）

---

## 1. 产品定位

当前 Scene 01 只有两台固定模板车（差速底盘+机械臂、差速底盘+托盘），玩家只做"编程搬运"。本模块补上游戏的前半部分：

```text
设计蓝图（选部件 → 看到能力/动作）
        ↓
在关卡中布置蓝图车（选择部署格）
        ↓
编程（Program 只允许该车真实具备的动作）
        ↓
完成任务；后期：用工作件与程序把另一台车"组装"出来（自复制）
```

核心设计原则：

1. **蓝图是唯一真值**：玩家编辑的是蓝图（部件组合），不是"改一辆已存在的车"。
2. **能力由部件推导，不由 UI 声明**：动作列表是能力标签的只读投影，Program 校验、Assembly 编译、HUD 显示共用同一条链路。
3. **组合要产生真实取舍**：底盘差异必须影响解空间（转向方式、占地、载重/托盘上限、成本），而不是只换速度数字。
4. **可验证**：每个部件组合都能通过契约测试预判"能不能做某动作"，部署前 fail-closed。

---

## 2. 部件模型

### 2.1 槽位

| 槽位 | 数量 | 作用 |
| --- | --- | --- |
| 底盘 Chassis | 1 | 决定移动方式（是否可原地转、是否全向）、footprint、速度基线、载重上限、成本 |
| 轮组 Wheels | 1 | 速度倍率、重量、成本；后续可影响通过性 |
| 工作件 Work Module | 1 | 提供抓取/托盘/推铲/扫描/组装等能力 |

MVP 固定三槽位、每槽 1 件：不做自由体素/多工作件挂点，避免组合爆炸与装配合法性不可读。后续可扩成"1 底盘 + N 挂点"。

### 2.2 部件属性

`VehiclePartDefinition`：`part_id`、`slot`、`display_name`、`description`、`capability_tags`、`tray_capacity`、`footprint`、`base_speed`、`speed_multiplier`、`carrying_speed_multiplier`、`weight`、`recommended_payload`、`max_payload`、**`cost`**、`suitable_levels`（给关卡设计/UI 提示，不参与计算）。

### 2.3 蓝图投影链路

```text
VehicleBlueprint（chassis/wheel/module 三个 id）
  ├─ capability_tags() = 三件部件能力的并集（去重）
  ├─ base_speed = chassis.base_speed × wheel.speed_multiplier
  ├─ tray_capacity = min(module.tray_capacity, floor(chassis.max_payload / ITEM_WEIGHT))
  ├─ total_weight / total_cost = 三件求和
  └─ to_vehicle_definition() → VehicleDefinition(vehicle_kind = ASSEMBLED)
        → Scene01AssemblyDefinitionAdapter（component_type = blueprint_vehicle_preset）
        → AssemblyCompiler / AssemblyCapabilities
        → Program 语句需求校验（moveTo→can_move, rotate→can_rotate, grabDrop→can_grab/has_tray）
```

- `VehicleDefinition.VehicleKind` 新增 `ASSEMBLED`，不改变既有 `.tres`（0=ARM、1=TRANSPORT）。
- `ITEM_WEIGHT = 2.0 kg`：把底盘载重变成可感知的托盘上限规则（全向底盘 14 kg → 7 格托盘；滑移 40 kg → 满 8 格）。
- 蓝图 id 规则 `^[a-z][a-z0-9_]{1,31}$`，同时作为部署车辆的 `vehicle_id`（Program 里直接书写）。
- 蓝图序列化：`to_dictionary()/from_dictionary()`，含 version，未知部件/非法 id 返回 null 并给出原因。

---

## 3. 底盘目录

### 3.1 已实现（MVP）

| id | 名称 | 转向 | 速度（×轮组） | 载重 | 成本 | 说明 |
| --- | --- | --- | --- | --- | --- | --- |
| `differential` | 差速底盘 | 平移 + 原地 90° 转身（0.3 s） | 2.0 | 推荐 20 / 上限 30 | 12 | 基准底盘；转向灵活，适合对位取放 |
| `skid_steer` | 滑移转向底盘 | 同差速（原地转身） | 1.7 | 26 / 40 | 16 | 慢但载重大；配重载轮组可拉满 8 格托盘 |
| `omni` | 全向底盘 | **MoveTo 不转身、不改变朝向**（`can_strafe`），Rotate 仍可单独执行 | 2.3 | 14 / 14 | 14 | 省掉路径转身时间，但托盘只能 7 格；抓取仍需先 Rotate 对准 |

关键差异（来自调研的结论）：网格玩法里"少一次转身"≈2.4 s 且少一条程序语句，比 2.0→2.3 的速度差更有意义；因此全向底盘的独特解空间是**横移不改朝向**，而不是"更快"。

### 3.2 计划中（不进 MVP）

| id | 名称 | 机制 | 为什么后置 |
| --- | --- | --- | --- |
| `tracked` | 履带底盘 | 可跨 1 格沟/粗糙地形、转身更慢、载重更高 | 需要地形/沟格规则，先有这种关卡再加 |
| `ackermann` | 阿克曼转向底盘 | 不能原地转，Rotate 必须伴随 Move；直道最快 | 需要"转弯半径/连续路径"规则，会改变 Program 语义 |
| `balanced` | 两轮平衡底盘 | 只能前后+平衡，速度极高、极脆 | 需要新物理与失败状态，属后期 |

---

## 4. 轮组目录

| id | 名称 | 速度倍率 | 重量 | 成本 | 说明 |
| --- | --- | --- | --- | --- | --- |
| `standard` | 标准轮组 | ×1.0 | 4 | 2 | 均衡 |
| `fast` | 高速轮组 | ×1.15 | 3 | 3 | 轻量高速 |
| `heavy` | 重载轮组 | ×0.9 | 8 | 4 | 更稳、配合重底盘 |

后续：履带轮组（地形）、麦克纳姆轮组（与全向底盘绑定）、防滑轮组（湿地关卡）。

---

## 5. 工作件目录

| id | 名称 | 能力 / 动作 | 适用关卡机制 | 状态 |
| --- | --- | --- | --- | --- |
| `gripper_arm` | 机械臂抓手 | `can_grab` → **GrabDrop**；`can_carry` | 单件取放、装车、分拣、把方块送入目标箱 | 已实现 |
| `cargo_tray` | 货运托盘 | `has_tray` → **Tray**（容量受底盘载重限制）；`can_carry` | 批量运输、中转站、长距离搬运 | 已实现 |
| `push_blade` | 推铲 | `can_push` → **Push**（推前方 1 格） | 清障、把方块推入沟槽/收集区；不靠抓取 | 计划 |
| `scanner` | 扫描器 | `can_scan` → **Scan**（读取目标箱编号/内容） | Bean Sorting 的编号分拣、隐藏目标信息 | 计划 |
| `lifter` | 升降台 | `can_lift` → **Lift**（抬升 1 层） | 多层平台、跨层搬运 | 计划 |
| `fabricator` | 组装臂（施工臂） | `can_assemble` → **Assemble**（按蓝图消耗零件并现场造车） | **自复制终局**：小车组装小车 | 后期核心 |

设计约束：新工作件必须写明"提供哪个动作、解决哪类关卡机制、与哪些底盘组合有额外收益"，并在目录里维护 `suitable_levels`。不做"纯数值更好"的工作件。

---

## 6. 能力 → 动作映射

| 能力标签 | 玩家可见动作 | Program 语句 | 说明 |
| --- | --- | --- | --- |
| `can_move` | MoveTo | `[id:moveTo] x y` | 所有底盘 |
| `can_rotate` | Rotate | `[id:rotate] clockwise/counterclockwise` | 差速/滑移/全向 |
| `can_strafe` | （MoveTo 语义变化） | — | 全向：移动不改变 facing |
| `can_grab` | GrabDrop | `[id:grabDrop]` | 抓手 |
| `has_tray` | Tray（容量） | 由 GrabDrop 装/卸 | 托盘被动能力 |
| `can_carry` | Carry | — | 被动标签（HUD/筛选） |
| `can_push` / `can_scan` / `can_lift` / `can_assemble` | Push / Scan / Lift / Assemble | 待定 | 计划中 |

UI 只展示 `ACTION_BY_CAPABILITY` 投影出的动作（`MoveTo / Rotate / GrabDrop / Tray` 等），不作第二套权限判断。

---

## 7. 蓝图编辑 UI 规格

布局：沿用 Scene 01 现有三区信息架构，编辑器放在**右侧栏（240 px 常规 / 360–460 px 作者模式）**，不新建全屏工作区。

```text
┌ 蓝图 · <名称>                         [保存] [加载] [部署] ┐
│ 槽位                                │ 可用动作            │
│  底盘  [差速底盘 ▾]  (12)           │  MoveTo  Rotate     │
│  轮组  [标准轮组 ▾]  (2)            │  GrabDrop           │
│  工作件[机械臂抓手 ▾] (8)           │                     │
│                                     │ 属性：速度 2.0      │
│ [模板：抓取车 / 运输车 / 侦察车]     │ 重量 28  成本 22    │
│ 诊断：…                             │ 托盘 0 / 7          │
└─────────────────────────────────────┴─────────────────────┘
```

交互规则（来自同类游戏调研 + 项目 UI 流程）：

1. **槽位装配**：每槽一个下拉/卡片，不做拖拽体素；默认从 3 个模板起步。
2. **实时投影**：选完部件立即刷新"可用动作"与属性；动作是能力只读投影。
3. **非法组合 fail-closed**：缺件/未知 id 时部署按钮禁用，并显示中文原因（来自 `get_last_error()` / 编译诊断）。
4. **成本与载重可见**：总成本、总重量、托盘上限实时显示，给关卡预算与取舍依据。
5. **保存/加载/复制**：蓝图 JSON 写入 `user://blueprints/*.json`，支持复制到剪贴板；加载未知部件时给出诊断而不是崩溃。
6. **恢复上次有效**：编辑失败不清空上一次可用蓝图；Undo 只回退蓝图编辑，不影响场景。
7. **部署步骤独立**：点"部署"后进入部署模式（hover 显示占位 ghost/合法性），点击合法格生成车辆；仅 READY 状态允许部署。
8. **试跑**：部署后可用"演示动线"ghost 播放一次 MoveTo/Rotate 示例（待实现）。

---

## 8. 关卡集成（部署与编程）

MVP 集成到 Scene 01（不新开场景）：

1. 蓝图车在 `Scene01VehicleManager` 中注册为**额外车辆**：`vehicle_id = blueprint_id`，起始格来自部署点击。
2. 部署发生在 READY（首次玩法命令前）；部署会触发一次 `VehicleManager`/控制器重配置，使选择、移动、抓放、Observable、CompileGate 都认识新车辆。
3. CompileGate 已按 `get_vehicles()` 全量编译；蓝图车的 `VehicleDefinition`（ASSEMBLED）由 adapter 映射为通用组件，能力标签进入 Program 校验。
4. Program 里直接使用蓝图 id：`[bp_scout_arm:moveTo] 5 3`；Builder 的动作列表来自 CompileGate 能力。
5. Reset 语义：蓝图车保留在场景中并回到部署初始状态；部署格与蓝图 id 作为场景/存档状态保存（待实现）。
6. 关卡完成条件、Tutorial、Scoring 暂不改动；综合关单独设计（§9）。

限制：当前车辆视觉按工作件复用两种合并网格（抓手→机械臂车、托盘→运输车），底盘差异暂不体现在模型上；后续按"底盘壳 + 工作件挂点"生成组合网格。

---

## 9. 综合关卡设计：装配站（Assembly Yard，规划）

目标：第一次让"组装 + 布置 + 编程 + 搬运"闭环成立，并为自复制做铺垫。

```text
24×14 网格
  ┌──────────────────────────────────────────┐
  │  [零件源 A]   [零件源 B]     [2×2 装配台] │
  │                                          │
  │  [种子车] ──→ [货箱区] ──→ [目标箱 8/8]  │
  └──────────────────────────────────────────┘
```

- **零件源**：A/B 两处零件堆（对应底盘、工作件的"资源化"）。
- **装配台**：2×2 格，放置蓝图 ghost；缺件时显示缺口清单。
- **目标**：用部署出的车把 8 个箱子送入目标箱；第二阶段改为"把另一台车组装出来"。
- **预算闸门**：零件总成本 ≤ 12、装配台 1、同时在场车辆 ≤ 3、程序语句 ≤ N（评分维度）。
- **评分**：完成时间（模拟时间）+ 消耗零件成本 + 程序语句数；三者共同计入结果面板。
- **自复制第二阶段**：`fabricator` 工作件 + 蓝图 = 现场造车；闸门限制防止指数爆炸。

---

## 10. 自复制机械路线（终局）

五阶段（调研结论）：

1. **种子**：只有一台可执行程序的种子车。
2. **采集**：种子车把零件从源头搬到装配台。
3. **构建**：施工臂按蓝图在装配台消耗零件，生成新车辆。
4. **扩张**：新车辆加入程序队列（每台车有自己的 Program 或共享任务表）。
5. **收敛**：达成目标数量/目标产量即停，避免无限增长。

四道闸门（必须同时存在，否则失控）：蓝图成本上限、单关卡零件预算、每关零件源数量、并发车辆上限。

失败模式与对策：

| 失败模式 | 表现 | 对策 |
| --- | --- | --- |
| 复杂度爆炸 | 玩家拼出无法理解/无法调度的车队 | 三槽位 + 分级解锁部件 |
| 等待过长 | 复制链太长，玩家干等 | 4× 模拟速度、并行车、缩短零件源距离 |
| 难以验证 | 部署后才发现缺件/缺动作 | 部署前预检 + 缺件 ghost + 中文诊断 |
| 软锁 | 零件耗尽无法完成 | 重置提示 + 可回收零件 |

---

## 11. 实现里程碑

| # | 内容 | 状态 |
| --- | --- | --- |
| 1 | 部件定义 / 目录 / 蓝图模型 / 能力推导 / 序列化 | **已完成** |
| 2 | 蓝图编辑 UI（下拉、动作投影、保存/加载、部署按钮） | **已完成**（`B` 键开关；右侧覆盖面板） |
| 3 | 部署后端：动态注册车辆、控制器重配置、Program id 支持 | **已完成** |
| 4 | 图形验证：编辑 → 部署 → 编程 → 完成移动 | **已完成**（flow 脚本 + 截图） |
| 5 | 综合关「装配站」与预算/评分 | 待实现（依赖 1–4，已具备） |
| 6 | `fabricator` 工作件与自复制终局 | 后期 |

### 11.1 验收方式（2026-10-18 调整）

项目测试策略改为**流程验收优先**：不再为装配模块新增防御性单测；用

```powershell
godot --headless --path . --script res://tools/acceptance_blueprint_flow.gd
```

一次跑完"初始场景 → 托盘蓝图部署 → 编译闸门 → Program 驱动移动 → 抓取蓝图部署/能力差异 → HUD → Reset"全流程，全部打印 PASS/FAIL 并以退出码结束。图形验收：`.dsh-visual/captures/bp_07_blueprint_panel.png`、`bp_08_blueprint_deployed.png`（本地参考）。原有 46 例 legacy 测试套件保留，用于守住既有契约与 CI。

### 11.2 已知限制（MVP）

- 部署仅允许 READY 状态；运行中需先 Reset。
- 蓝图面板覆盖在 Operations 右栏之上（MVP 不做面板切换/互斥）。
- 车辆视觉只按工作件复用机械臂/托盘两种合并网格，底盘差异暂不体现。
- 蓝图保存为单个 `user://blueprints/last_blueprint.json`，暂不做多蓝图库。

### 11.3 PR #92 审查修复（2026-10-18）

四处 Medium 已逐条核实并修复，流程验收脚本新增对应检查（`tools/acceptance_blueprint_flow.gd`）：

1. **重复部署预览/提交不一致**：部署会话开始时把 `blueprint` 解析为带唯一后缀的 `_deployment_blueprint`，ghost 预览与点击提交消费同一候选；`_cancel_deployment` 清理。
2. **蓝图托盘车缺货物显示结构**：`blueprint_vehicle_placeholder.tscn` 复用运输车的 8 个 `TraySlots` + `TrayCountLabel`；`VehicleStateVisual` 按 `definition.tray_capacity` 控制槽位/标签可见性（无托盘能力的车隐藏标签）。
3. **成本未进入编译结果**：`VehicleDefinition` 新增 `assembly_cost`；`VehicleBlueprint.to_vehicle_definition()` 传入 `get_total_cost()`；adapter 用 `assembly_cost` 填充 `AssemblyComponentDefinition.cost`，编译结果 `metrics.cost` 与蓝图 UI 一致。
4. **托盘载货未减速**：`VehicleRuntimeState.get_effective_speed()` 同时判断 `arm_has_item` 与托盘非空，继续由 Movement 单一入口消费。
5. **重新打开编辑器未解除部署状态**：`_open()` 先 `_cancel_deployment()`，编辑与放置互斥；部件改动也会清掉缓存候选，世界点击不再可能部署旧组合。

验证：流程验收 `FLOW RESULT failures=0`（含成本一致、托盘显示/装载、重复部署候选、载货减速与卸货恢复）；legacy 46/46 PASS；图形截图 `fix_08_blueprint_deployed.png`、`fix_09_tray_loaded.png`（本地 `.dsh-visual/`）。`warning_surface.gdshader` 的深灰踏纹属于既定视觉目标，保留。
- 车辆 id 重复时自动追加 `_2/_3` 后缀。

---

## 12. 风险与开放问题

- **视觉复用**：MVP 蓝图车按工作件复用两种网格，底盘差异不可见；需要组合网格生成器（底盘壳 + 挂点）。
- **能力差异**：全向底盘已用 `can_strafe`（MoveTo 不转身）区分；差速 vs 滑移仍只有速度/载重差异，后续可加"转身耗时"。
- **载重规则**：`ITEM_WEIGHT` 让载重影响托盘格数；其它 payload 语义（超载减速）尚未实现。
- **成本尚未强制**：`cost` 已进入目录/蓝图，但关卡预算闸门未实现。
- **动态部署时序**：Scene 01 现有控制器在 `configure` 时枚举车辆，部署需要一次受控重配置，必须补集成测试防止信号重复连接。
- **Program/教学耦合**：Tutorial 第 5 目标硬编码 Arm/Transport；蓝图车不参与该目标，综合关需新的教学目标。
