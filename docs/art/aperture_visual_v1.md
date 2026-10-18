# Scene 01 Aperture 视觉方向 v1

Status: **第一轮已落地（2026-10-18）**，后续视觉轮次继续迭代。
目标：把 Scene 01 从"青蓝科幻白盒"收敛到《传送门 2》Aperture Science 测试室语言。
参考与量化数据：`.dsh-visual/reference/notes.md`（7 张参考图的像素级统计，本地参考，不随仓库分发）。

## 1. 视觉基准（从参考图实测，非估计）

| 角色 | 值 | 用法 |
| --- | --- | --- |
| 面板白 | `#E8E8E4` | 墙面、白结构件（线性 `0.807, 0.807, 0.776`） |
| 地面白瓷 | `#EDEFE9` → 实装略降温至 `#E2E4DA` | 可玩地板；1 m 拼板、深色细缝 |
| 顶棚/梁/框 | `#24272B` | 顶部过梁、踢脚、观察窗框、门框；metallic ≤ 0.4 |
| 平台结构灰 | `#3A3E42` | 平台侧立面 |
| 青色灯带/LED | `#3FC6CE` | 唯一"科技色"：灯带、LED 点阵、状态 |
| 蓝色强调 | `#1B7FD4` | UI 主行动/焦点；play 图标 |
| 橙色强调 | `#E8892C` | 仅门/危险/重置类语义，面积 < 0.5% |
| 背景虚空 | `#171A1C` | 玻璃/平台外，让白盒"跳"出来 |

硬指标：高饱和强调 ≤ 3%（当前实测 0.16%）；受光白面无彩偏色；阴影冷色（hue 200–215°，实测 210°）。

## 2. 空间与材质规则

- **面板模数 1.15 m**，接缝 4 cm 宽（屏幕 ≈3 px）+ 2 cm 倒角；用几何/着色器暗线，不靠粗黑边。
- **房间净高 3.2 m**；围挡顶部必须有深色过梁/顶梁，暗示顶棚存在。
- **地面是主角**：1 m 可玩格 = 地板模数（服从玩法），程序化深缝 + 每格 ±1.8% 亮度差；不再使用黄黑警示条。
- **边界带**：深灰防滑底板（低对比斜纹）+ 内侧一圈青色 LED 点阵导引线（0.5 m 间距），替代工业警示。
- **白板** roughness 0.55 / metallic 0；**深色结构** metallic 0.35（禁止镜面金属）；**玻璃** alpha 0.12、cull disabled、roughness 0.05。
- **磨损分级**：洁净区 0–2 级（仅板缝积灰），旧区才允许 4–5 级；当前为洁净区。

## 3. 光照与后处理（Forward+）

- 渲染器：`forward_plus`（桌面），`mobile` 作为回退，`web = gl_compatibility`。
- 主光 `DirectionalLight3D`：5000 K 中性偏冷、energy 1.35、PSSM 4 段、`shadow_blur` 1.2、`light_angular_distance` 1.0（PCSS 软阴影）、最大距离 60 m。
- 补光：冷色方向光 0.2；环境光 `#B9C7D4` → 实装中性冷 `(0.52,0.56,0.60)` energy 0.32。
- `Environment`：Filmic tonemap、exposure 1.06、SSAO 1.35/半径 1.1、Glow 0.45（阈值 0.92）、深度雾 `#AEBCC9` 0.006 + 高度雾、体积雾 0.008（极轻）、饱和度 0.92、对比 1.10。
- 不做真实光柱；如未来需要，用加法混合假几何或提高体积雾密度，不在玩法层加遮挡。

## 4. 已实装内容（本轮）

| 区域 | 实现 |
| --- | --- |
| 渲染器 | `project.godot` 切 Forward+；CI 仍用 headless，不受影响 |
| 场景 | 新 `aperture_panel_wall.gdshader`（1.15 m 模型空间网格 + 板间色差 + 底部积灰）；后/左两面 3.2 m 白板墙 + 深色顶梁/过梁/踢脚 + 角落柱；原玻璃围挡、信号灯、玻璃框架已隐藏（`visible = false`，节点保留可回退） |
| 观察窗 | 深色暗室背板 + 玻璃 + 深色细框（x≈12 m 处） |
| 门 | 深色门板 + 橙色发光门框（唯一橙色强调，x≈4.6 m） |
| 标识 | 白底黑字 `01` 号牌 + `TEST CHAMBER` 白底黑字铭牌（深色背板，Label3D） |
| 顶棚结构 | 深色桁架（沿后/左墙顶）+ 竖向吊杆，暗示顶棚存在且压暗画面顶部 |
| 导引 | 地面四周青色 LED 点阵（`aperture_led_dots.gdshader`，additive/mix 圆点）+ 墙面竖向点线 |
| 地面 | 程序化 1 m 深缝 + 每格亮度抖动 + 降低瓷砖反光；黄黑警示条改为深灰防滑带（几何/契约不变，仅 shader 与材质） |
| 物件 | StandardBlock / StandardBox 改为白壳 + 深色边框 + 青色发光带；StandardBox 追加白色外包板 + 正面青色容量条（内部 8 格槽位与计数逻辑不变） |
| 车辆 | 车身保持 `painted_white` + 深色关节 + 青色轮毂；新增深色眼座 + 青色圆形"眼灯"（Arm / Transport 各一），运输车托盘前缘加青色灯条；选中高亮改为**加法混合的蓝色辉光**（白色外壳不再被黄色/深蓝整体染色） |
| 车辆重建 | 两车改为**单一多 surface 合并网格**（白/深色/橡胶/青色 4 个 surface）：白色圆角车身 + 深色底盘/保险杠/托盘内衬 + 橡胶轮 + 青色眼灯/侧标记/托盘灯条；机械臂为白色胶囊双段 + 深色球关节 + 白色夹爪。细节层：侧面板缝、传感器舱（深色 + 青色点）、尾部天线（深色杆 + 青色球）。节点数从每车约 60 个 MeshInstance 降为 1 个；生成脚本 `tools/build_vehicle_meshes.gd` |
| 环境合并 | 实验室环境（墙/梁/观察窗/LED/门/平台周边，原 106 个可见 MeshInstance）按材质合并为 1 个 9-surface 网格；生成脚本 `tools/build_environment_meshes.gd`；`aperture_panel_wall.gdshader` 改为按法线选择面板轴向，便于任意旋转/合并后的墙体 |
| 交互语义色 | 悬停格 = 青 `#3FC6CE` 20%；已选格 = 蓝 `#1B7FD4` 26%；MoveTo 有效路径/目标 = 青（α 0.22/0.85）；无效 = 红 `#E23B32`（α 0.25/0.8）；抓放预览有效 = 青 α0.3；lifecycle 状态：就绪蓝 / 运行中青 / 已暂停橙 |
| 材质 | `lab_structural_white`、`painted_white`、`dark_mechanical_metal`、`lab_platform_coating`、`cyan_emissive`、`lab_glass`、`warning_tile` 全部按上表重整 |
| UI | 面板 `#F7F9FB` a0.97 / 1px `#D0E0E6` / 顶部 2px 青色强调边 / 圆角 6；按钮白底→hover 青色边→pressed 青色底白字；主行动（运行/部署/提交）实心青 `#12A0AF`；进度条青 `#3FC6CE`；CodeEdit 等宽；5 px 细滚动条；lifecycle 顶部控制条为深色控制台（`#101C23`），状态/计时用等宽字体；分区标题带 3px 青色左标线；小标题字幕（MISSION / OPERATIONS / ASSEMBLY BLUEPRINT / SORTING PROTOCOL）；图标 play 蓝 / 其余深灰 |

## 5. 验收（2026-10-18）

- 46/46 运行时测试 PASS（含 UI 契约 6 项）；渲染器切换、场景/材质、物件与车辆、交互配色、车辆/环境网格合并、车辆细节六批改动分别全量复跑，均 46/46。
- **性能：1920×1080 ready 场景 draw call 从 364 降到 150（−59%）**；其中车辆每车约 60 个 MeshInstance → 1 个（4 surface），环境 106 个可见 MeshInstance → 1 个（9 surface）。
- 图形 walkthrough（1920×1080，真实渲染客户端，见 `.dsh-visual/captures/pass25_*`）：ready / selected / program-open / MoveTo targeting / moving / paused 六个状态均已截图；HUD、状态灯、路径预览、忙碌态反馈均正常。
- 干净副本 `godot --headless --editor --quit` 导入 exit 0、无 fatal；E2E 场景测试 PASS（包含新合并网格资源）。
- 1920×1080 截图指标：强调 0.09%（≤3%）、暗部 hue 209°、亮度 p50 0.442 / p95 0.98、受光白 chroma 4.0。
- 已尝试并放弃：地面加法混合"光斑"四边形（俯视视角下读作灰色条带，不如保留干净地板），相关 shader/材质已删除。
- 已知偏差：顶部 20% 平均亮度 0.55（高于参考的暗顶棚，因为本作是俯视视角、顶部是远墙而非天花板）；中性像素占比 52%（低于参考 65%，因为整体保留冷色环境光，属刻意取舍）。

## 5.1 网格构建管线（可复现）

合并网格是**生成产物**，源文件为 `tools/*.gd`：

```powershell
# 车辆：白色圆角壳 / 深色结构 / 橡胶轮 / 青色灯（每车 4 surface）
godot --headless --path . --script res://tools/build_vehicle_meshes.gd
# 环境：按材质合并整个实验室静态壳（9 surface，自动跳过 hidden 节点）
godot --headless --path . --script res://tools/build_environment_meshes.gd
```

- 产物：`assets/scene_01/vehicles/{arm,transport}_vehicle_mesh.res`、`assets/scene_01/environment/aperture_environment_mesh.res`。
- 车辆场景保留 gameplay 必需节点：`VisualRoot`、`VehicleSelectionArea/CollisionShape3D`、`DebugLabel`、运输车 `TraySlots`/`TrayCountLabel`、机械臂 `CarryWarning`；其余全部进合并网格。
- 环境场景保留 `ChamberNumber`/`ChamberCaption` 两个 Label3D 与 `DustMotes` 粒子，其余静态几何进合并网格。
- **环境 bake 是单向的**：合并后场景里只剩 `StaticShell`，再次运行环境脚本会因找不到 authored `material_override` 而中止（脚本已加保护）。要继续改环境几何，需要以 git 历史中的 authored 场景为起点重建，或另写程序化环境构建脚本。
- 注意：本机 DSH 命令沙箱以 Low 完整性运行，无法写入 `assets/`、`scenes/components/`、`docs/`、`tests/` 等目录；生成脚本需要用更宽权限的会话/正常编辑器运行一次。CI 与普通开发者机器不在此限制内。

## 5.2 UI v2：现代实验室控制台（2026-10-18 晚）

在保持节点名/脚本契约不变的前提下，成套重绘 Scene 01 / Scene 02 的 UI：

- **深色控制台顶栏**：lifecycle 状态条改为 `#101C23` 深色胶囊，状态灯/计时/倍速为浅色等宽字，运行/重置保持浅色内嵌控制组，形成"仪器面板"对比。
- **冷白面板 + 青色强调**：面板底色 `#F7F9FB`、边框 `#D0E0E6`、圆角 6、更柔和的投影；面板顶部 2px 青色描边；分区标题左侧 3px 青色标线。
- **主行动实心化**：Program「运行」、Blueprint「部署」、Bean「提交 / 结算」改为实心青底白字（`#12A0AF`，hover/pressed 有独立色阶），其余按钮维持克制的描边风格。
- **仪表字幕与等宽遥测**：HUD 增 `MISSION · CONTAINER SORTING`、Operations 增 `OPERATIONS · MANUAL / PROGRAM`、Blueprint 增 `ASSEMBLY BLUEPRINT · [B]`、Bean HUD 增 `SORTING PROTOCOL 01`；位置/朝向/载荷/任务进度/来源克数/结算明细改用 `lab_mono` 等宽字体。
- 字体栈升级为 `Segoe UI Variable Text` → `Segoe UI` → 中文回退；等宽栈 `Cascadia Mono` → `Consolas`。

验证：UI 契约测试与 46/46 全量测试通过；蓝图与 Bean 流程验收 `failures=0`；截图 `ui7_01_ready.png`、`ui7_07_blueprint_panel.png`、`bean_01_ready.png`（本地 `.dsh-visual/captures/`）。draw call 未增加（ready 188，仍在 ~190 区间）。

### 5.3 UI 全量收敛（2026-10-18，第二轮）

把剩余界面统一到同一套实验室语言：

- **Debug 面板**：改为深色「诊断台」控制台（`#101C23`、青色描边、深阴影），标题/折叠按钮浅色，展开内容保留稳定路径；新增 `DIAGNOSTICS · DEV TOOLS` 字幕并纳入折叠 body（折叠时不占位）。
- **任务完成面板**：深色结算控制台（12px 圆角、20px 投影），白色标题 + `MISSION COMPLETE · SORTING PROTOCOL` 字幕 + 浅色统计行，与顶部 lifecycle 控制台呼应。
- **Program 工作区**：`源码 · 规范 v2` 标题收敛为统一字幕 `PROGRAM · DSL V2`，语法状态行改用等宽字体；修掉新增内容导致的面板底部溢出（清空按钮恢复可见）。
- **等宽状态**：Blueprint `StatusLabel`、Bean `StateLabel`、HUD `FeedbackLabel` 统一 `lab_mono`；所有 UI 面板字号/字幕/间距一致。
- 验证：46/46 PASS、Bean/Blueprint 流程 `failures=0`；截图 `ui9_10_completion.png`、`ui9_03_program_open.png`、`ui9_01_ready.png`（本地）。

### 5.4 鲜明化光照/调色（2026-10-18 晚）

针对"整体灰蒙蒙"的反馈，只改场景光照与环境后处理（不改几何/材质烘焙）：

- **Tonemap**：Filmic → **ACES**，exposure 0.86，white 2.0；饱和度 0.92 → **1.34**，对比度 1.1 → **1.14**，亮度 0.98。
- **光比**：KeyLight 1.5 → 1.25（配合曝光降低过曝），色温略暖；FillLight 改为青蓝 `#70B9D1`（0.28）。
- **强调光**：新增 2 个青色 OmniLight（`#26D4EA`，左侧 2.0 / 右侧 1.6）与 1 个橙色 OmniLight（`#FF6E21`，门区 1.1），让白墙/地面出现 Portal 式冷暖光池。
- **去灰雾**：fog density 0.006 → 0.0022、aerial 0.35 → 0.12；volumetric fog 0.014 → 0.004，albedo 更蓝；glow 抬到 0.72 / strength 1.15 / threshold 0.82，让青色灯带与部署点发光。
- SSAO 略增强（intensity 1.8）以保留硬阴影边缘；背景近黑蓝 `#020304`。
- 验证：真实渲染截图 `vivid3_01_ready.png`（Scene 01）、`bean_03_settled.png`（Scene 02）；46/46 测试与三套流程验收保持通过。

## 6. 下一轮候选（未做）

1. **光照氛围**：假体积光柱（从顶梁缺口斜射）、墙面反射探针 / SSR 轻微地板反射、悬挂式 Chamberlock 装置。
2. **墙面细节**：图标/编号贴花（箭头、奔跑小人、危险标记）、少量板缝污渍、门侧状态灯、观察窗内侧暗室细节。
3. **UI 细节**：HUD 信息层级再压缩、Program 面板分节标题、图标统一 1.8 线宽复核。
4. **图形验收**：在真实桌面客户端做一次玩家可见 walkthrough 并截图归档。
