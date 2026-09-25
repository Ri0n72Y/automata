# Skill-UI-implement-flow

## 目的

用于把一张 UI 效果图、设计稿或目标截图，稳定地复刻成真实产品 UI。

核心原则：

> 先把图片转成可验证的设计数据，再写代码。不要先凭感觉改 UI，再用截图反复猜。

这套流程适用于游戏 HUD、工具栏、侧边栏、工作区、弹窗等界面。它尤其适合“已有旧 UI，需要按目标图重构”的情况。

---

## 1. 先冻结本轮范围

在写代码前，明确三类内容。

### 1.1 不变的功能 contract

例如：

- Play / Pause 行为不变；
- simulation time 继续使用真实 simulation time；
- Reset 仍调用现有 lifecycle owner；
- UI 不复制 gameplay truth。

这些是本轮不能因为视觉复刻而改变的产品语义。

### 1.2 可以改变的 presentation

例如：

- 控件排列；
- 尺寸；
- padding / spacing；
- 圆角；
- 颜色；
- icon；
- 展开 / 折叠 presentation；
- 控件视觉权重。

### 1.3 明确不做的范围

例如：

- 本轮只做主界面，不做 Program Workspace；
- 不借 UI 重构新增玩法；
- 不提前抽象完整 Design System。

如果范围没有先冻结，UI 复刻很容易变成无边界重构。

---

## 2. 必须同时准备两张图

每轮复刻至少需要：

1. **Reference**：目标效果图；
2. **Current**：当前真实运行截图。

尽量保持：

- 同一窗口比例；
- 同一 UI scale；
- 同一相机或相近 framing；
- 同一主要状态。

不要只看 Reference 写代码。真正需要解决的是：

> Current → Reference 的差异。

---

## 3. 先做差异表，不直接编码

按区域逐项比较：

| 项目 | Reference | Current | 调整方向 |
| --- | --- | --- | --- |
| 组件组成 | 有哪些元素 | 当前有哪些 | 增 / 删 / 合并 |
| 层级 | 谁最显眼 | 当前谁最显眼 | 调视觉权重 |
| 几何 | 宽、高、位置 | 当前比例 | 调尺寸 |
| spacing | 内外间距 | 当前间距 | 调 layout |
| style | 背景、边框、阴影 | 当前 style | 调 theme |
| control language | pill / card / text action | 普通 button 等 | 换 presentation |
| state | hover / pressed / disabled | 当前反馈 | 补完整 |
| copy | 文案长度 | 当前文案 | 缩短或重写 |

先把“哪里不一样”说清楚，再决定怎么改。

---

## 4. 从设计稿反推数据

不要只说：

- “再小一点”；
- “再紧凑一点”；
- “更像效果图”。

要尽量转成数字。

### 4.1 记录 Reference 原始尺寸

例如：

`1672 × 941`

### 4.2 测量目标组件像素尺寸

例如目标 capsule：

- width ≈ 420 px；
- height ≈ 54 px；
- top ≈ 20 px。

### 4.3 同时记录归一化比例

例如：

- width / viewport_width ≈ 25%；
- height / viewport_height ≈ 5.7%。

像素值用于复刻，比例值用于检查不同分辨率下是否仍合理。

### 4.4 从 Current 反推 UI scale

如果运行截图和设计稿 viewport 不同，不要直接抄 Reference 像素。

优先比较：

- 组件占屏比例；
- Current logical size → screenshot physical size 的近似缩放关系。

目标是得到**实现层的 logical px contract**。

---

## 5. 把视觉拆成“组件角色”，不要拆成一堆 Button

效果图中的一组元素，可能在语义上是一个组件。

例如：

`[ Pause | Reset ]`

应理解为：

> 一个 Run Control Group，内部有两个 action。

而不是：

> 两个独立按钮挨在一起。

同样：

`4× ⌄`

更接近：

> lightweight selector

而不是：

> 一个普通矩形按钮。

实现前先定义角色：

- status indicator；
- primary action；
- secondary action；
- grouped control；
- lightweight selector；
- section header；
- property row；
- card；
- navigation disclosure。

视觉一致性首先来自角色一致，而不是统一颜色。

---

## 6. 定义视觉权重

每个组件都要回答：

> 哪个元素应该第一眼被看到？

推荐至少区分：

### Primary
主要动作或当前关键状态。

### Secondary
可操作，但不应该抢主动作注意力。

### Tertiary
信息、选择器、辅助入口。

### Passive
纯状态文字或说明。

例如顶部运行胶囊：

- Play / Pause：Primary；
- Reset：Secondary，但与 Play 属于同一控制组；
- Speed：Tertiary；
- Time：Passive；
- State：Passive + semantic color。

如果所有东西都有边框和底色，就不存在视觉层级。

---

## 6.1 Icon / Glyph 也属于 design contract

高保真复刻时，不要默认使用 Unicode 字符充当按钮图标。

例如：

- `▶`；
- `Ⅱ`；
- `↺`；
- `+` / `−`；
- 文本箭头。

它们的实际形状会受系统字体、fallback font、字重和平台影响，很难稳定接近设计稿。

对于主要 UI action，优先使用：

- 项目内 SVG；
- 统一 viewBox；
- 统一 stroke / fill；
- 固定视觉尺寸；
- hover / pressed 由按钮容器负责，而不是换字符。

Unicode glyph 更适合真正属于文字内容的符号，而不是需要像素级复刻的 control icon。

设计记录里应增加：

- icon source；
- viewBox / nominal size；
- stroke width；
- fill / stroke color；
- icon-to-container ratio；
- 是否随 semantic state 改色。

如果设计稿里的 chevron、play、pause、reset 是视觉语言的一部分，就应当把它们作为资产复刻，而不是让字体替你决定外观。

---

## 7. 写成 Design Contract 后再实现

每个组件在编码前写一个小 contract。

示例：

### Lifecycle Capsule

组成：

`State + Time + [Play/Pause | Reset] + Speed`

几何：

- width ≈ 352 logical px；
- height ≈ 44 logical px；
- top = 12 logical px。

视觉：

- 一个连续外胶囊；
- Play / Pause 与 Reset 共用一个浅色 control group；
- Speed 无明显外框，只保留文本 + chevron；
- 状态点小于正文高度；
- 不使用显眼 divider 把整个 capsule 切成 toolbar。

状态 copy：

- READY → 就绪；
- RUNNING → 运行中；
- PAUSED → 已暂停。

这份 contract 是实现和 review 的共同依据。

---

## 8. 实现时优先改 presentation tree，不复制 domain state

UI 复刻允许重组场景树，但不要因此复制业务 truth。

正确：

`Lifecycle owner → UI projection`

错误：

`Lifecycle owner → UI 自己再保存一份 running/paused truth`

同理：

- Tutorial collapse 只属于 presentation；
- pointer coordinate 读取现有 selection owner；
- capability 显示读取真实 capability；
- Program projection 不建立第二份 mutable program model。

如果为了“方便 UI”产生第二套业务状态，应先停下来重审架构。

---

## 9. 不要用 magic-number 拼旧布局

常见失败模式：

> 旧 UI 是两个独立 Panel，为了看起来像一张侧栏，只把两个 Panel 的 y 坐标调得更接近。

如果 Reference 表达的是：

> 一个 Sidebar，内部多个 section，

那么实现也应重组为：

`SidebarPanel → VBox → StatusSection / TutorialSection / ...`

不要靠：

- 固定高度；
- 手写 top offset；
- panel A bottom = panel B top；

伪造视觉结构。

Reference 的**结构关系**比单个像素更重要。

---

## 10. CI / Test contract 必须和新 UI 架构一起迁移

UI 重构之后，旧测试常常仍然锁死：

- 旧节点路径；
- 旧 panel 数量；
- 旧按钮；
- 旧布局关系。

区分两种失败：

### Stale Test
产品决策已经改变，测试仍要求旧 UI。

应更新测试。

### Real Regression
新 UI 自己违反了新 design contract。

应修 production。

不要因为 CI 红就盲目恢复旧节点，也不要把所有失败都解释成 stale test。

---

## 11. UI 测试应该验证 contract，而不是截图细节

适合自动测试的内容：

- 组件存在；
- section 层级正确；
- 一个 control group 是否真的共用 parent/container；
- collapsed / expanded state；
- supported viewport 下不越界；
- central gameplay corridor 是否保留；
- logical width / height 是否在 contract tolerance 内；
- UI 读取真实 domain state；
- removed legacy control 不再存在。

不适合把所有像素差异都塞进 runtime test。

像素级美观仍需要 graphical walkthrough。

---

## 12. 一次只复刻一个区域

推荐顺序：

1. 选择一个区域；
2. 差异表；
3. Design Contract；
4. 实现；
5. CI；
6. Current screenshot；
7. 与 Reference 对比；
8. 通过后再进入下一区域。

不要同时改：

- 顶部 capsule；
- 左 Sidebar；
- Tutorial；
- 右操作台；
- Program Workspace。

否则无法判断哪一次变化真正解决了视觉问题。

---

## 13. Graphical Walkthrough 的比较顺序

不要第一眼先看“好不好看”。

按顺序检查：

### A. Composition
组件组成是否一致？

### B. Geometry
位置、宽高、占屏比例是否接近？

### C. Hierarchy
视觉注意力顺序是否一致？

### D. Spacing
padding / gap / section rhythm 是否一致？

### E. Control language
是不是 Reference 的 pill / card / row，而不是默认控件换色？

### F. Color / Typography
最后再调颜色、字号、字重和细节。

如果 A/B/C 都错了，先调字体颜色没有意义。

---

## 14. 推荐的接受标准

在进入下一个区域前至少满足：

- 功能 contract 不回归；
- domain truth 没有复制；
- CI 全绿；
- 新 UI tree 符合 Reference 的结构关系；
- 关键尺寸已写成 logical px 或比例 contract；
- supported viewport 不越界；
- Current screenshot 与 Reference 的主要差异已从“结构性”下降为“视觉微调”。

如果仍然需要解释：

> “虽然看起来不同，但功能是一样的”

通常说明复刻还没完成。

---

## 15. 常见反模式

### 只换 Theme
把旧界面换成白色，并不等于复刻了新的 UI。

### 先实现再总结需求
容易围绕错误结构不断打补丁。

### 所有控件都用 Button
会把状态、选择器、主操作、次操作做成同一视觉权重。

### 用更多 divider 解决层级
Reference 很轻时，divider 越多越像工具软件 toolbar。

### 为了测试保留废弃 UI
测试应该跟产品 contract 迁移，而不是反过来绑架实现。

### 用文字描述替代真实 control
“按 M 移动”不等于一个右侧 Move action UI。

### 一次改整个界面
无法形成稳定的 visual compare loop。

---

## 16. 标准工作模板

每个区域都按下面格式记录：

### Scope

- 本轮：
- 不变：
- 不做：

### Reference Data

- viewport：
- component x/y：
- width/height：
- normalized ratio：

### Component Model

- 外层：
- 子组件：
- Primary：
- Secondary：
- Passive：

### Visual Contract

- padding：
- gap：
- radius：
- border：
- background：
- typography：
- states：

### Functional Contract

- state owner：
- signals：
- actions：
- forbidden duplicate state：

### Test Contract

- node/component relationship：
- geometry tolerance：
- state projection：
- removed legacy contract：

### Review

- Composition：
- Geometry：
- Hierarchy：
- Spacing：
- Control language：
- Color/Typography：

### Result

- CI：
- graphical walkthrough：
- remaining delta：

---

## 一句话版本

> **UI 复刻不是“照着图片调 CSS/Theme”，而是先从图片恢复组件结构、视觉权重和尺寸 contract，再让现有真实业务状态投影进这套结构，最后用 CI + 同屏截图逐区域收敛。**
