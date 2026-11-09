#!/usr/bin/env python3
"""
Send GoPlay APK release and changelog to Telegram Community group/channel.
Zero external dependencies (uses standard library urllib).
"""

import datetime
import html
import json
import os
import sys
import urllib.error
import urllib.request
import uuid

MAX_CAPTION_LEN = 1000  # Telegram caption limit is 1024 chars; keep margin for safety
MAX_FILE_BYTES = 50 * 1024 * 1024  # Telegram Bot API max file size limit (50 MB)


def format_changelog(notes_content: str) -> list[str]:
    """Parse notes content into clean, HTML-escaped lines for Telegram."""
    formatted = []
    lines = notes_content.strip().splitlines()

    for raw_line in lines:
        line = raw_line.strip()
        if not line or line.startswith("---") or line.startswith("## ["):
            continue

        if line.startswith("### "):
            section = html.escape(line.replace("### ", "").strip(), quote=False)
            formatted.append(f"\n<b>{section}:</b>")
        elif line.startswith(("- ", "* ", "• ")):
            clean_item = line.lstrip("-*• ").strip()
            item = html.escape(clean_item, quote=False)
            formatted.append(f"• {item}")
        else:
            escaped = html.escape(line, quote=False)
            formatted.append(escaped)

    return formatted


def build_caption(tag: str, changelog_lines: list[str]) -> str:
    """Build the Telegram caption without external GitHub links."""
    now = datetime.datetime.now(datetime.timezone.utc)
    month_name = now.strftime("%B")  # e.g. "November"

    # Header section matching screenshot format
    header = (
        f"🎮 <b>GoPlay {html.escape(tag, quote=False)}</b>\n"
        f"Release\n\n"
        f"{month_name} Update\n\n"
        f"<b>Changelog</b>"
    )

    # Check if full changelog fits
    full_changelog = "\n".join(changelog_lines).strip()
    full_caption = f"{header}\n{full_changelog}"

    if len(full_caption) <= MAX_CAPTION_LEN:
        return full_caption

    # Truncate changelog if it exceeds caption length
    trunc_suffix = "\n• ..."
    available_space = MAX_CAPTION_LEN - len(header) - len(trunc_suffix) - 2

    current_body = []
    current_len = 0
    for line in changelog_lines:
        line_len = len(line) + 1  # newline
        if current_len + line_len > available_space:
            break
        current_body.append(line)
        current_len += line_len

    truncated_changelog = "\n".join(current_body).strip()
    return f"{header}\n{truncated_changelog}{trunc_suffix}"


def make_multipart_body(fields: dict, file_field: str, filename: str, file_bytes: bytes, mime_type: str):
    """Build multipart/form-data payload for file upload using standard library."""
    boundary = f"----WebKitFormBoundary{uuid.uuid4().hex}"
    parts = []

    for key, val in fields.items():
        if val is None:
            continue
        parts.append(f"--{boundary}\r\n".encode("utf-8"))
        parts.append(f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8"))
        parts.append(f"{val}\r\n".encode("utf-8"))

    parts.append(f"--{boundary}\r\n".encode("utf-8"))
    parts.append(
        f'Content-Disposition: form-data; name="{file_field}"; filename="{filename}"\r\n'.encode("utf-8")
    )
    parts.append(f"Content-Type: {mime_type}\r\n\r\n".encode("utf-8"))
    parts.append(file_bytes)
    parts.append(b"\r\n")

    parts.append(f"--{boundary}--\r\n".encode("utf-8"))
    payload = b"".join(parts)
    content_type = f"multipart/form-data; boundary={boundary}"
    return payload, content_type


def send_telegram_document(token: str, chat_id: str, thread_id: str, apk_path: str, caption: str):
    """Send APK document to Telegram chat."""
    filename = os.path.basename(apk_path)
    print(f"Reading {apk_path} ({os.path.getsize(apk_path)} bytes)...")
    with open(apk_path, "rb") as f:
        file_bytes = f.read()

    fields = {
        "chat_id": chat_id,
        "caption": caption,
        "parse_mode": "HTML",
    }
    if thread_id:
        fields["message_thread_id"] = thread_id

    url = f"https://api.telegram.org/bot{token}/sendDocument"
    body, content_type = make_multipart_body(
        fields,
        file_field="document",
        filename=filename,
        file_bytes=file_bytes,
        mime_type="application/vnd.android.package-archive"
    )

    req = urllib.request.Request(
        url,
        data=body,
        headers={
            "Content-Type": content_type,
            "Content-Length": str(len(body)),
            "User-Agent": "GoPlay-CI-Bot/1.0"
        },
        method="POST"
    )

    print(f"Uploading {filename} to Telegram chat {chat_id}...")
    with urllib.request.urlopen(req, timeout=180) as resp:
        res_data = resp.read()
        res_json = json.loads(res_data.decode("utf-8"))
        if not res_json.get("ok"):
            raise RuntimeError(f"Telegram API response not ok: {res_json}")
        print("Upload successful!")


def send_telegram_message(token: str, chat_id: str, thread_id: str, text: str):
    """Send text message fallback to Telegram chat."""
    payload = {
        "chat_id": chat_id,
        "text": text,
        "parse_mode": "HTML",
        "disable_web_page_preview": False
    }
    if thread_id:
        payload["message_thread_id"] = thread_id

    url = f"https://api.telegram.org/bot{token}/sendMessage"
    json_bytes = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=json_bytes,
        headers={
            "Content-Type": "application/json",
            "Content-Length": str(len(json_bytes)),
            "User-Agent": "GoPlay-CI-Bot/1.0"
        },
        method="POST"
    )

    print(f"Sending message to Telegram chat {chat_id}...")
    with urllib.request.urlopen(req, timeout=60) as resp:
        res_data = resp.read()
        res_json = json.loads(res_data.decode("utf-8"))
        if not res_json.get("ok"):
            raise RuntimeError(f"Telegram API response not ok: {res_json}")
        print("Message sent successfully!")


def main():
    if len(sys.argv) < 5:
        print("Usage: send_telegram_release.py <apk_path> <tag_name> <notes_path> <repository>")
        sys.exit(1)

    apk_path = sys.argv[1]
    tag_name = sys.argv[2]
    notes_path = sys.argv[3]
    repository = sys.argv[4]

    token = os.environ.get("TELEGRAM_BOT_TOKEN", "").strip()
    chat_id = os.environ.get("TELEGRAM_CHAT_ID", "").strip()
    thread_id = os.environ.get("TELEGRAM_THREAD_ID", "").strip()

    if not token or not chat_id:
        print("::warning::TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID secret is not set. Skipping Telegram notification.")
        sys.exit(0)

    if not os.path.exists(apk_path):
        print(f"::error::APK file not found at {apk_path}")
        sys.exit(1)

    release_url = f"https://github.com/{repository}/releases/tag/{tag_name}"

    notes_content = ""
    if os.path.exists(notes_path):
        with open(notes_path, "r", encoding="utf-8") as f:
            notes_content = f.read()

    changelog_lines = format_changelog(notes_content)
    caption = build_caption(tag_name, changelog_lines)

    file_size = os.path.getsize(apk_path)
    file_size_mb = file_size / (1024 * 1024)

    try:
        if file_size <= MAX_FILE_BYTES:
            send_telegram_document(token, chat_id, thread_id, apk_path, caption)
        else:
            print(f"::warning::APK file size ({file_size_mb:.1f} MB) exceeds Telegram standard bot limit of 50 MB.")
            apk_filename = os.path.basename(apk_path)
            download_url = f"https://github.com/{repository}/releases/download/{tag_name}/{apk_filename}"
            fallback_text = (
                f"{caption}\n\n"
                f"📦 <b>Direct Download:</b> <a href=\"{download_url}\">{apk_filename} ({file_size_mb:.1f} MB)</a>"
            )
            send_telegram_message(token, chat_id, thread_id, fallback_text)

        print(f"Successfully posted GoPlay {tag_name} release to Telegram community!")

    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8", errors="replace")
        print(f"::error::Telegram API HTTPError {e.code}: {e.reason} - {error_body}")
        sys.exit(1)
    except Exception as e:
        print(f"::error::Failed to send release to Telegram: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()

