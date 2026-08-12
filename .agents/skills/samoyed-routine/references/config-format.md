# Samoyed Routine 构建规格

先创建 JSON 源文件，再让 `scripts/build_routine.py` 渲染 App 可读取的 YAML。

## JSON 结构

```json
{
  "title": "标准工作日",
  "source_date": "2026-08-12",
  "blocks": [
    {
      "title": "晨间启动",
      "start": "07:30",
      "end": "09:00",
      "note": "先进入状态，不打开消息。",
      "checklist": ["喝水", "打开窗帘"],
      "reminders": ["at_start"],
      "children": [
        {
          "title": "早餐",
          "offset": "30m",
          "duration": "30m",
          "checklist": ["吃维生素"]
        }
      ]
    }
  ]
}
```

## 字段

- 根对象：必须包含 `title`、`source_date`（`YYYY-MM-DD`）和非空 `blocks`。
- 基础时间块：必须包含 `title` 和绝对时间 `start`；可包含 `end`、`note`、`checklist`、`reminders` 和 `children`。
- 嵌套时间块：只能使用绝对 `start`/`end` 或相对 `offset`/`duration` 中的一种，不能混用。
- Checklist：使用非空字符串数组；渲染器固定输出 `completed: false`。
- Reminder：使用 `at_start` 或 `10m_before` 这类非负提前量。
- Note：使用简短、可重复的自我提示；支持换行。

## 结构规则

- 同级时间块必须有不同的开始时间。
- 每个嵌套时间块必须完全位于直接父块内部。
- 开始时间使用 `00:00` 至 `23:59`；只有结束时间可以使用 `24:00`。
- 未填写结束时间或填写得更晚时，由下一个同级块或父块边界截断，与 Samoyed 的解析方式一致。
- 未覆盖时段表示开放时间，不要创建空白占位块。

生成的 YAML 始终使用 `version: 1`、`kind: day_blocks`，并限制在 App 支持的 YAML 子集内。
