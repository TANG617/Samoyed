---
name: samoyed-routine
description: 通过访谈收集可重复的每日 Routine，区分日程步骤与一次性待办，将时间块、嵌套状态、Checklist、注意事项 Note 和提醒汇总为 Samoyed 可读取的 YAML Routine Config，完成校验后通过 Base64URL 内嵌 deeplink、HTTPS 或 Debug 模拟器 localhost 打开确认式导入。用于用户要求创建、修改、生成、校验或导入 Samoyed 日程与 day-blocks YAML 的场景。
---

# Samoyed 日程编排

把用户对一天的粗略描述变成可复用 Routine。以给大脑减负为目标：减少追问、外化记忆，并在真正导入前保留 App 内本地确认。

## 工作流程

1. 询问 Routine 名称或日期类型，以及一天的大致顺序。接受自然语言，不要求用户理解配置结构。
2. 只追问会改变结构的缺失信息。每次优先提出一个简短问题；安全时推断普通默认值。
3. 为每个时间块收集：
   - 开始时间和可选的结束时间；
   - 可重复执行的 Checklist；
   - 一条简短、稳定且值得反复看见的 Note；
   - 可选的 `at_start` 或 `<分钟数>m_before` 提醒。
4. 仅当某个状态确实发生在父状态内部时添加嵌套 Overlay。普通的一天顺序优先使用基础时间块。
5. 除非用户明确要求定义一次性的某一天，否则不要把临时预约和项目待办放入 Routine。必要时简要解释两者区别。
6. 用紧凑摘要展示拟定的时间块、Checklist、Note 和提醒。生成文件前只解决实质歧义。
7. 阅读 [references/config-format.md](references/config-format.md)，创建 `.routine.json` 构建规格，并运行 `scripts/build_routine.py` 生成 `.yml`。脚本能渲染时，不要手写最终 YAML。
8. 仅在脚本成功后导入：
   - 真机或无需托管：运行 `scripts/open_import.py <yaml> --title <名称> --inline --print-only`，把输出的 deeplink 交给用户。
   - Debug iOS 模拟器：运行 `scripts/open_import.py <yaml> --title <名称>`。
   - 已有 HTTPS 托管：运行 `scripts/open_import.py <yaml> --title <名称> --url <https-url>`。
   - 选择传输方式前阅读 [references/deeplink.md](references/deeplink.md)。
9. 停在 Samoyed 的预览确认页。让用户在 App 内选择 Import、Replace、Keep Both 或 Cancel；不要绕过本地确认。
10. 报告 YAML 路径、Routine 摘要、校验结果，以及是否已打开导入预览。

## 访谈规则

- 使用用户当前语言交流；用户使用中文时默认用中文访谈和总结。
- 优先外化记忆，不要为了填满字段而增加认知负担。
- 把 Checklist 视为附着于某个状态的可重复步骤，不要把它当作收件箱。
- 把 Note 写成用户在该状态中反复看到仍有帮助的短句。
- Checklist 的完成状态默认写为 `false`；完成状态属于每日执行数据，不得回写到 Routine。
- 用户未提供代表日期时，使用本地今天作为 `source_date`。说明它是传输所需元数据，不限制该 Routine 只能在哪一天使用。
- 用户知道结束时间时优先使用明确时间；若根据下一时间块推断边界，在摘要中说明。
- 拒绝同级时间重叠、子块超出父块、空标题和公共 HTTP URL。

## 构建命令

从本 `SKILL.md` 解析 Skill 目录，然后运行：

```bash
python3 <skill-dir>/scripts/build_routine.py <routine>.routine.json --output <routine>.yml
python3 <skill-dir>/scripts/open_import.py <routine>.yml --title "Routine 名称" --inline --print-only
```

已有托管配置时使用 `--url https://…`。内嵌传输限制为 32 KB；超限时返回 YAML 文件，或在用户批准后使用 HTTPS 托管。

## 失败处理

- 生成失败时，修正 JSON 规格并重新运行；不要降低校验标准。
- 没有已启动的模拟器时，返回 YAML 和准确的内嵌 deeplink，不要声称已打开预览。
- App 拒绝 YAML 时，保留原始错误，修正规格、重新生成并重试。
- 内嵌 YAML 超过 32 KB 时，返回已校验 YAML 供用户通过 Files 导入；未经明确授权，不要上传到第三方服务。
