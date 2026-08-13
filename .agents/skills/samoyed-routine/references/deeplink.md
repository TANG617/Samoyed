# Samoyed Routine 导入 Deeplink

## 路由

默认使用无服务器的内嵌传输：

```text
samoyed://import-routine?v=1&payload=<unpadded-base64url-yaml>&title=<percent-encoded-title>
```

`v=1` 表示 `payload` 是 UTF-8 YAML 的无填充 Base64URL 编码。`payload` 必填，`title` 可选；内嵌 YAML 最大 32 KB。

保留远程传输兼容：

```text
samoyed://import-routine?url=<percent-encoded-url>&title=<percent-encoded-title>
```

`url` 与 `payload` 必须且只能出现一个。远程模式中，未提供 `title` 时 App 会从 YAML 文件名推导名称。

## 传输选择

- 正式构建或真机：优先使用 `--inline --print-only`，不上传 Routine Config。
- 超过 32 KB 或已有托管配置：使用经用户批准的 `https://` URL。
- Debug iOS 模拟器：使用 `scripts/open_import.py`，从 `http://127.0.0.1:<随机端口>` 单次提供本地 YAML，再通过 `xcrun simctl` 打开 deeplink。
- 公共 `http://` URL 一律拒绝；Release 构建也拒绝 localhost HTTP。

## App 行为

1. 内嵌模式最多解码 32 KB UTF-8 YAML；远程模式最多接收 512 KB。
2. 内嵌模式拒绝未知版本、填充或非 Base64URL 字符；远程模式要求 HTTP 响应成功。
3. 对远程重定向后的最终 URL 重新执行传输安全校验。
4. 两种传输都使用同一个 Samoyed YAML 结构与时间校验器。
5. 展示来源类型、时间块数量和 Checklist 数量。
6. 添加或替换 Routine 前要求用户在本地明确确认。

传输内容只用于本次导入。导入会创建本地 Routine，不会替换今天已经物化的日计划，也不会改动 Checklist 的每日执行状态。
