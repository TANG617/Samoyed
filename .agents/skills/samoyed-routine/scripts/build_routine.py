#!/usr/bin/env python3
"""把简洁的 JSON Routine 规格编译为 Samoyed 支持的受限 YAML。"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
from pathlib import Path
from typing import Any


TIME_PATTERN = re.compile(r"^(\d{2}):(\d{2})$")
MINUTES_PATTERN = re.compile(r"^(\d+)m$")
REMINDER_PATTERN = re.compile(r"^(\d+)m_before$")
ROOT_KEYS = {"title", "source_date", "blocks"}
BLOCK_KEYS = {
    "title",
    "note",
    "start",
    "end",
    "offset",
    "duration",
    "reminders",
    "checklist",
    "children",
}


class SpecError(ValueError):
    pass


def require_mapping(value: Any, path: str) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise SpecError(f"{path} 必须是对象")
    return value


def require_list(value: Any, path: str) -> list[Any]:
    if not isinstance(value, list):
        raise SpecError(f"{path} 必须是数组")
    return value


def clean_text(value: Any, path: str, *, allow_empty: bool = False) -> str:
    if not isinstance(value, str):
        raise SpecError(f"{path} 必须是文本")
    text = value.strip()
    if not allow_empty and not text:
        raise SpecError(f"{path} 不能为空")
    for character in text:
        if ord(character) < 32 and character not in "\n\r\t":
            raise SpecError(f"{path} 包含不支持的控制字符")
    return text


def parse_time(value: Any, path: str, *, allow_24: bool) -> int:
    text = clean_text(value, path)
    match = TIME_PATTERN.fullmatch(text)
    if match is None:
        raise SpecError(f"{path} 必须使用 HH:mm")
    hour, minute = (int(part) for part in match.groups())
    if hour == 24 and minute == 0 and allow_24:
        return 24 * 60
    if not 0 <= hour <= 23 or not 0 <= minute <= 59:
        raise SpecError(f"{path} 超出有效时间范围")
    return hour * 60 + minute


def parse_minutes(value: Any, path: str, *, allow_zero: bool) -> int:
    text = clean_text(value, path)
    match = MINUTES_PATTERN.fullmatch(text)
    if match is None:
        raise SpecError(f"{path} 必须使用 <分钟数>m")
    minutes = int(match.group(1))
    if minutes == 0 and not allow_zero:
        raise SpecError(f"{path} 必须大于零")
    return minutes


def normalize_reminders(value: Any, path: str) -> list[str]:
    if value is None:
        return []
    reminders = []
    for index, raw in enumerate(require_list(value, path)):
        reminder = clean_text(raw, f"{path}[{index}]")
        if reminder != "at_start" and REMINDER_PATTERN.fullmatch(reminder) is None:
            raise SpecError(f"{path}[{index}] 必须是 at_start 或 <分钟数>m_before")
        reminders.append(reminder)
    return reminders


def normalize_checklist(value: Any, path: str) -> list[str]:
    if value is None:
        return []
    return [
        clean_text(raw, f"{path}[{index}]")
        for index, raw in enumerate(require_list(value, path))
    ]


def parse_block(raw_value: Any, path: str, *, is_base: bool, parent_start: int) -> dict[str, Any]:
    raw = require_mapping(raw_value, path)
    unknown = set(raw) - BLOCK_KEYS
    if unknown:
        raise SpecError(f"{path} 包含不支持的字段：{', '.join(sorted(unknown))}")

    title = clean_text(raw.get("title"), f"{path}.title")
    note = None
    if raw.get("note") is not None:
        note = clean_text(raw["note"], f"{path}.note", allow_empty=True) or None

    has_absolute = "start" in raw or "end" in raw
    has_relative = "offset" in raw or "duration" in raw
    if is_base:
        if has_relative:
            raise SpecError(f"{path} 是基础时间块，不能使用 offset 或 duration")
        if "start" not in raw:
            raise SpecError(f"基础时间块必须包含 {path}.start")
        has_absolute = True
    elif has_absolute == has_relative:
        raise SpecError(f"{path} 必须且只能使用一种计时模式：start/end 或 offset/duration")

    if has_absolute:
        if "start" not in raw:
            raise SpecError(f"绝对计时必须包含 {path}.start")
        start = parse_time(raw["start"], f"{path}.start", allow_24=False)
        requested_end = (
            parse_time(raw["end"], f"{path}.end", allow_24=True)
            if raw.get("end") is not None
            else None
        )
        timing = {"type": "absolute", "start": start, "requested_end": requested_end}
    else:
        if "offset" not in raw:
            raise SpecError(f"相对计时必须包含 {path}.offset")
        offset = parse_minutes(raw["offset"], f"{path}.offset", allow_zero=True)
        duration = (
            parse_minutes(raw["duration"], f"{path}.duration", allow_zero=False)
            if raw.get("duration") is not None
            else None
        )
        start = parent_start + offset
        requested_end = start + duration if duration is not None else None
        timing = {
            "type": "relative",
            "offset": offset,
            "duration": duration,
            "requested_end": requested_end,
        }

    return {
        "path": path,
        "title": title,
        "note": note,
        "timing": timing,
        "start": start,
        "reminders": normalize_reminders(raw.get("reminders"), f"{path}.reminders"),
        "checklist": normalize_checklist(raw.get("checklist"), f"{path}.checklist"),
        "raw_children": require_list(raw.get("children", []), f"{path}.children"),
    }


def resolve_siblings(
    raw_blocks: list[Any],
    *,
    parent_start: int,
    parent_end: int,
    is_base: bool,
    path: str,
) -> list[dict[str, Any]]:
    parsed = [
        parse_block(raw, f"{path}[{index}]", is_base=is_base, parent_start=parent_start)
        for index, raw in enumerate(raw_blocks)
    ]
    parsed.sort(key=lambda block: (block["start"], block["title"].casefold()))

    for index, block in enumerate(parsed):
        start = block["start"]
        if start < parent_start or start >= parent_end:
            raise SpecError(f"{block['path']} 的开始时间位于父块之外")
        next_start = parsed[index + 1]["start"] if index + 1 < len(parsed) else parent_end
        requested_end = block["timing"]["requested_end"]
        end = min(parent_end, next_start, requested_end if requested_end is not None else parent_end)
        if end <= start:
            raise SpecError(f"{block['path']} 解析后为空或与同级时间块重叠")
        block["end"] = end
        block["children"] = resolve_siblings(
            block.pop("raw_children"),
            parent_start=start,
            parent_end=end,
            is_base=False,
            path=f"{block['path']}.children",
        )
    return parsed


def compile_spec(raw_value: Any) -> dict[str, Any]:
    raw = require_mapping(raw_value, "root")
    unknown = set(raw) - ROOT_KEYS
    if unknown:
        raise SpecError(f"根对象包含不支持的字段：{', '.join(sorted(unknown))}")

    title = clean_text(raw.get("title"), "title")
    source_date = clean_text(raw.get("source_date"), "source_date")
    try:
        parsed_date = dt.date.fromisoformat(source_date)
    except ValueError as error:
        raise SpecError("source_date 必须使用 YYYY-MM-DD") from error
    if parsed_date.isoformat() != source_date:
        raise SpecError("source_date 必须使用 YYYY-MM-DD")

    raw_blocks = require_list(raw.get("blocks"), "blocks")
    if not raw_blocks:
        raise SpecError("blocks 不能为空")
    blocks = resolve_siblings(
        raw_blocks,
        parent_start=0,
        parent_end=24 * 60,
        is_base=True,
        path="blocks",
    )
    return {"title": title, "source_date": source_date, "blocks": blocks}


def quote(text: str) -> str:
    escaped = (
        text.replace("\\", "\\\\")
        .replace('"', '\\"')
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("\t", "\\t")
    )
    return f'"{escaped}"'


def time_text(minutes: int) -> str:
    if minutes == 24 * 60:
        return "24:00"
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def append_block(lines: list[str], block: dict[str, Any], indent: int) -> None:
    prefix = " " * indent
    lines.append(f"{prefix}- title: {quote(block['title'])}")
    if block["note"]:
        lines.append(f"{prefix}  note: {quote(block['note'])}")

    timing = block["timing"]
    lines.append(f"{prefix}  timing:")
    lines.append(f"{prefix}    type: {timing['type']}")
    if timing["type"] == "absolute":
        lines.append(f"{prefix}    start: {quote(time_text(timing['start']))}")
        if timing["requested_end"] is not None:
            lines.append(f"{prefix}    end: {quote(time_text(timing['requested_end']))}")
    else:
        lines.append(f"{prefix}    offset: {quote(str(timing['offset']) + 'm')}")
        if timing["duration"] is not None:
            lines.append(f"{prefix}    duration: {quote(str(timing['duration']) + 'm')}")

    if block["reminders"]:
        lines.append(f"{prefix}  reminders:")
        lines.extend(f"{prefix}    - {reminder}" for reminder in block["reminders"])
    if block["checklist"]:
        lines.append(f"{prefix}  tasks:")
        for item in block["checklist"]:
            lines.append(f"{prefix}    - title: {quote(item)}")
            lines.append(f"{prefix}      completed: false")
    if block["children"]:
        lines.append(f"{prefix}  children:")
        for child in block["children"]:
            append_block(lines, child, indent + 4)


def render_yaml(compiled: dict[str, Any]) -> str:
    lines = [
        "version: 1",
        "kind: day_blocks",
        f"source_date: {compiled['source_date']}",
        "blocks:",
    ]
    for block in compiled["blocks"]:
        append_block(lines, block, 2)
    return "\n".join(lines) + "\n"


def count_blocks(blocks: list[dict[str, Any]]) -> int:
    return sum(1 + count_blocks(block["children"]) for block in blocks)


def count_tasks(blocks: list[dict[str, Any]]) -> int:
    return sum(len(block["checklist"]) + count_tasks(block["children"]) for block in blocks)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("spec", type=Path, help="JSON Routine 源规格")
    parser.add_argument("--output", required=True, type=Path, help="YAML 输出路径")
    args = parser.parse_args()

    try:
        raw = json.loads(args.spec.read_text(encoding="utf-8"))
        compiled = compile_spec(raw)
        yaml = render_yaml(compiled)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(yaml, encoding="utf-8")
    except (OSError, json.JSONDecodeError, SpecError) as error:
        print(f"错误：{error}", file=sys.stderr)
        return 2

    print(
        f"已为 {compiled['title']!r} 写入 {args.output}："
        f"{len(compiled['blocks'])} 个基础时间块，{count_blocks(compiled['blocks'])} 个时间块，"
        f"{count_tasks(compiled['blocks'])} 个 Checklist 项。"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
