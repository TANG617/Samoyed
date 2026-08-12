# Samoyed `Now` Widget

- 版本：v0.3
- 日期：2026-08-07
- 状态：P1 候选，P0 验证前冻结

本文档定义 P0 验证通过后，第一个系统入口实验：单一 `Now` Widget。

产品范围以 [PRD.md](PRD.md) 为准；系统入口边界以 [SystemSurfaces.md](SystemSurfaces.md) 为准。Widget 只消费核心层语义，不定义新的业务规则。

## 1. 为什么只保留一个 Widget

Samoyed 的核心价值是让用户更低成本地知道“现在是什么、现在做什么”。Widget 是最直接的验证载体，因为它能够减少打开 App 和寻找 `Now` 的步骤。

Widget 不是为了扩大平台覆盖面，也不证明核心产品已经成立。在以下条件满足前，不继续开发：

- 首次激活可以在空数据下独立完成。
- 默认日型能够自动运行。
- `Now` 已成为最高频页面。
- 7 天测试证明用户确实减少了重复规划或上下文恢复成本。

## 2. P1 假设

> 已经稳定使用 `Now` 的用户，会通过桌面 Widget 更频繁、更低成本地查看当前状态，并在不打开 App 的情况下完成少量当前步骤。

Widget 需要验证的是行为价值，不是展示能力。

## 3. 最小范围

### 3.1 Widget 家族

第一轮只实现或启用：

- `systemSmall`

只有真实测试证明 small 信息不足，才增加：

- `systemMedium`

当前不进入范围：

- `systemLarge`
- accessory inline / circular / rectangular
- StandBy 专门布局
- 多种可配置 Widget
- 与 Live Activity 或 Controls 的组合

### 3.2 展示信息

固定优先级：

1. 当前 block 标题
2. 当前 block 结束时间
3. 最多 1–2 个未完成 checklist
4. 剩余步骤数量
5. 必要的状态说明

不展示：

- 完整 `activeChain`
- layer 编号
- note 长文本
- 模板管理信息
- 今天和明天的 schedule
- 统计与完成率

### 3.3 交互

必须支持：

- 点击 Widget 打开 `Now`

在共享写入稳定后可以支持：

- 完成 Widget 明确展示的一条 checklist

不支持：

- 切换模板
- 创建或编辑 block
- 修改时间
- 输入文本
- 启动 Live Activity
- 暴露通用任务操作

## 4. 状态设计

### 4.1 尚未激活

显示“先在 Samoyed 建立你的第一个日型”，点击进入首次激活。

不得在 Widget provider 中创建 sample data 或静默生成虚假历史。

### 4.2 今天没有模板

显示“今天尚未运行日型”，点击进入 App 的今天处理入口。

### 4.3 空白时段

显示“当前是空白时段”，可补充下一 block 的开始时间。

### 4.4 当前没有步骤

保留当前 block 和时间，显示“当前没有待完成步骤”。

### 4.5 全部完成

显示简短完成状态，不重复列出所有已完成项。

### 4.6 数据错误

使用稳定的恢复文案并打开 App。Widget 不展示底层错误、文件路径或调试信息。

## 5. 数据与架构

### 5.1 单一业务真相

Widget 与 App 读取同一个 App Group 文档，并复用核心层的 `Now` 查询语义。

Widget 不得：

- 复制时间解析算法。
- 自行选择模板。
- 自行推断 `taskSourceBlock`。
- 为提高展示完整度写入或修复业务数据。

### 5.2 最小快照

Widget entry 只携带渲染所需数据，例如：

- `date`
- 当前 block 标识、标题和时间
- 1–2 个展示任务的 block/task 标识、标题和完成状态
- 剩余数量
- 状态类型
- 可选的下一刷新边界

不要把整个 `SamoyedDocument` 放进 entry。

### 5.3 时间线

刷新优先对齐：

- 当前 block 结束时间
- 当天边界
- 用户交互后的显式 reload

WidgetKit 不保证精确实时刷新。产品文案和验收不得承诺“每个 block 零延迟自动切换”。

### 5.4 交互式写入

如果启用 checklist 完成：

1. intent 参数使用明确的 date、block ID 和 task ID。
2. 写入前重新加载最新文档。
3. 只修改目标 checklist。
4. 目标过期或不存在时安全失败。
5. 写入使用共享原子变更路径。
6. 成功后请求刷新 Widget。

App 回到前台时重新加载文档，避免 Widget 写入后内存状态滞后。

## 6. 深链

Widget 整体点击默认进入：

- `samoyed://now`

尚未激活时应进入首次激活。需要定位明确 block 时可以使用已有 today route，但不得让用户先经过 Library 或模板管理页。

## 7. 实施顺序

只有 P1 进入条件满足后执行：

1. 用现有 `Now` 快照实现 `systemSmall`。
2. 覆盖未激活、无模板、空白和全部完成状态。
3. 验证跨 block 刷新与 App Group 读取。
4. 先发布只读实验。
5. 观察 Widget 是否减少打开 App 查找当前状态的成本。
6. 只有只读价值成立且共享写入可靠，再启用 checklist 完成。
7. 只有 small 信息不足被真实观察到，再评估 medium。

## 8. 验收标准

### 8.1 正确性

- 与 App `Now` 展示同一个当前 block。
- 展示任务来自同一核心推导。
- 完成 checklist 后 App 与 Widget 状态一致。
- 过期交互不会误改新的当前任务。
- 无数据和文档错误时不崩溃。

### 8.2 体验

- 一次扫视能够识别当前状态。
- small 尺寸不需要塞入完整任务列表。
- 交互目标符合系统建议尺寸。
- 支持 Dynamic Type、VoiceOver、深浅色外观。

### 8.3 产品证据

Widget 继续投入至少需要满足一项：

- 测试用户主动把 Widget 放到主屏并持续使用。
- 用户通过 Widget 查看 `Now` 的次数明显高于专门打开 App。
- 用户明确表示 Widget 减少了上下文恢复成本。

如果用户没有持续放置或使用 Widget，不增加更多尺寸和系统位置。

## 9. 非目标

- 构建 Widget 家族。
- 追求所有 Apple 系统表面的视觉一致性。
- 用 Widget 替代首次激活、模板创建或 Today 修正。
- 为 Widget 引入新的领域模型。
- 以 Widget 数量、尺寸数量或 intent 数量衡量产品进展。
