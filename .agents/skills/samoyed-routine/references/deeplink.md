# Samoyed Routine 导入 Deeplink

## 路由

```text
samoyed://import-routine?url=<percent-encoded-url>&title=<percent-encoded-title>
```

`url` 是必填参数。`title` 可选；未提供时，App 会从 YAML 文件名推导名称。

## 传输选择

- 正式构建或真机：使用经用户批准的 `https://` URL。
- Debug iOS 模拟器：使用 `scripts/open_import.py`，从 `http://127.0.0.1:<随机端口>` 单次提供本地 YAML，再通过 `xcrun simctl` 打开 deeplink。
- 公共 `http://` URL 一律拒绝；Release 构建也拒绝 localhost HTTP。

## App 行为

1. 最多接收 512 KB UTF-8 文本。
2. 要求 HTTP 响应成功。
3. 对重定向后的最终 URL 重新执行传输安全校验。
4. 解析并校验 Samoyed YAML。
5. 展示来源主机、文件名、时间块数量和 Checklist 数量。
6. 添加或替换 Routine 前要求用户在本地明确确认。

远程内容只承担传输作用。导入会创建本地 Routine，不会替换今天已经物化的日计划，也不会改动 Checklist 的每日执行状态。
