# Bean Sorting v1（第一个可玩谜题）

Status: **可玩 MVP 已实现**（Scene 02）。目标是把 #76 的关卡循环先做成能玩的纵切片，而不是一次补齐 #78–#80 的全部基础设施。

## 1. 玩家循环

```text
进入 Scene 02 → 看本局 1–5 号箱位置 → 选/组装车辆
  → 手动或 Program 搬运豆子 → 主动提交 → 0–3000 分结算
```

- 3 个来源箱：黄豆 / 绿豆 / 白豆，各 1000g，位置固定。
- 5 个目标箱：位置固定，每局把编号 1–5 随机分配给它们。
- 固定规则：黄豆→1 号箱、绿豆→2 号箱、白豆→3 号箱；4/5 号为干扰箱。
- 单次 Grab 最多 300g，满来源箱需要 300+300+300+100 四次。
- 目标箱接受任意豆种，不实时拒绝；正确性只在结算时判断。
- 玩家点击「提交 / 结算」后快照冻结，显示正确/错箱/未提交与分豆种明细。

## 2. 实现映射（对应 issues）

| Issue | 实现 |
| --- | --- |
| #68 Bean Domain | `scripts/beans/bean_batch.gd`（继承 StandardBlock，复用 ownership/claim）、`bean_source_inventory.gd`、`bean_target_inventory.gd` |
| #69 Content Definition | `scenes/scene_02/scene_02_bean_sorting.tscn` 中固定 source/target 单元；映射表在 `bean_sorting_controller.gd` |
| #70 Round Setup | 控制器 `_setup_round()`：`1..5` 洗牌 → 目标箱；Reset 保留编号，「新一局」重洗 |
| #71 Objective / Settlement | `submit_beans()` + `_build_settlement()`：score/correct/wrong/lost/per-bean/per-target/elapsed 快照 |
| #72 HUD | `scenes/scene_02/components/bean_hud.tscn` + `scripts/scene_02/bean_hud.gd`：规则、编号、来源余量、提交/新一局、结果 |
| #73 Scoring | `score = correct_grams`（0–3000）；错箱不计分 |
| #74 Tutorial | 未做独立教学；HUD 常驻规则说明（MVP 替代） |
| #77 Mission Framework | 未引入通用框架；复用 Scene01 lifecycle + 本关 submit 快照 |
| #81 QA 门 | 以流程验收脚本 + 图形截图代替（见下） |

复用而未新造：网格/相机/车辆/移动/抓放、ProgramRunner/CommandExecutor、Assembly CompileGate、Blueprint UI（`B` 键仍可部署蓝图车）。

## 3. 场景组成

- 文件：`scenes/scene_02/scene_02_bean_sorting.tscn`，根脚本 `scripts/scene_02/bean_sorting_controller.gd`（extends `Scene01LifecycleController`）。
- 豆类对象：`Scene01ObjectManager` 节点挂 `bean_object_manager.gd`（extends `Scene01ObjectManager`，只暴露 bean source/target，禁用地面拾取/丢弃）。
- 视觉：来源堆按豆种着色 + 克数标签；目标箱白色壳体 + `#n` 编号 + 克数标签，全部由节点脚本生成，无额外资源烘焙。
- 场景切换：Scene 01 按 `2` 进入本关；Scene 02 按 `1` 回 Scene 01（`scripts/ui/level_switcher.gd`，本地测试便利）。

## 4. 验证

```powershell
godot --headless --path . --script res://tools/acceptance_bean_flow.gd
```

覆盖：场景初始化/库存/编号排列/映射；300g 抓取与批次克数；300+300+300+100 满箱；错箱不实时拒绝；提交得分/错箱/分豆种明细；Reset 清结算、恢复库存、保留编号；Program 移动；新一局重洗。结果：`BEAN FLOW RESULT failures=0`。

图形：`.dsh-visual/captures/bean_01_ready.png`、`bean_02_delivered.png`、`bean_03_settled.png`。legacy 46/46 保持通过。

## 5. 已知差距（相对 #76 完整里程碑）

- 车辆组装仍需走 Scene 01 的蓝图 UI；本关未做专属装配工位/零件源（#78–#80 的编辑工作区）。
- 地面丢弃（永久流失）未开放：当前 `BeanObjectManager` 禁用地面交互，lost 恒为 0；规则上不产生可拾回豆。
- 「新一局」仅在 READY（非运行/暂停）可用；未做局间动画/计分排行。
- HUD 不显示选中车辆状态（依赖 Operations 面板）；场景无固定障碍布局（先保证可玩性）。
- 教学校验、完整 QA 门（#81）、分数曲线/排行、多语言未做。
- 计时：结算快照使用 lifecycle `timer`；提交时若刚启动会接近 0（正常）。
