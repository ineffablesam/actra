from __future__ import annotations

import base64
import json
import re
from collections.abc import Awaitable, Callable
from typing import Any

import structlog
from google import genai
from google.genai import types as genai_types

from src.config import Settings
from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "gemini"

INTENT_SYSTEM = """ You are Actra, a voice AI assistant. Analyze the user's request and return ONLY valid JSON with this exact schema - no markdown, no explanation, JSON only:
{ "intent": "send_email" | "create_event" | "read_emails" | "check_calendar" | "slack_workspace" | "github_issues" | "github_repo_search" | "github_fix_pr" | "unknown" | "unsupported",
  "required_providers": ["google_gmail", "google_calendar", "slack", "github"],
  "confidence": 0.0-1.0,
  "entities": {
    "to": "person name or email if mentioned",
    "subject": "inferred subject line",
    "topic": "what the message is about",
    "date": "any date/time mentioned",
    "body_hints": ["key points to include"],
    "channel": "Slack channel name if mentioned",
    "repo_owner": "GitHub org or user (e.g. facebook)",
    "repo_name": "repository name (e.g. react)",
    "issue_number": "numeric issue number if mentioned",
    "search_query": "repository search keywords if user wants to find a repo"
  },
  "reasoning": "why these providers are needed, or why the request is out of scope",
  "user_message": "when intent is unsupported: one short friendly sentence the user will hear"
}

Hard rules:
- Actra integrations: google_gmail (email), google_calendar (calendar), slack (Slack workspace), github (repos, issues, pull requests via Token Vault).
- Any request to read, list, summarize, or identify the latest or recent email (inbox, unread, "who wrote", "last message") MUST use intent "read_emails" and include "google_gmail" in required_providers.
- Requests about Slack: listing channels, what's in Slack, team/workspace, messages in a channel, posting to Slack, or "check Slack" MUST use intent "slack_workspace" and include "slack" in required_providers.
- GitHub: list issues, open issues in a repo, get issue details → intent "github_issues" and required_providers ["github"]. Include repo_owner and repo_name when the user names org/repo (e.g. "issues in facebook/react"). If they say "this repo", "the repo", or "my repo" without owner/name, still use "github_issues" with required_providers ["github"] but leave repo_owner and repo_name empty — Actra will ask which repository. Never invent owner/name the user did not say.
- GitHub: search or find repositories, "show me repos about X" → intent "github_repo_search" and required_providers ["github"]; set search_query from the user request. If they only say "search repos" with no topic, still use github_repo_search with empty or vague search_query.
- GitHub: fix an issue, implement a change, open a PR, patch code, "create a pull request" for a repo/issue → intent "github_fix_pr" and required_providers ["github"]. Include repo_owner, repo_name, and issue_number when possible; if any are missing, use github_fix_pr anyway and leave entities empty for missing fields.
- GitHub follow-ups: phrases like "fix it", "fix the issue", "open a PR for that" right after listing or discussing issues still map to "github_fix_pr". Include repo_owner/repo_name if the user named a repo earlier in the thread; issue_number may be omitted if they only refer to "the issue" — the server can infer from recent turns.
- In required_providers, use ONLY these exact strings when needed: "google_gmail", "google_calendar", "slack", "github". Never invent other provider IDs.
- If the user asks for anything that needs another app or service not listed above (examples: Teams-only, Google Drive-only, Photos, Spotify, banking, generic web search, SMS, WhatsApp, Notion, Jira-only without GitHub), set intent to "unsupported", required_providers to [], and put a warm, concise user_message explaining limits and one example of what they can ask instead.
- If the request is vague or chit-chat with no integrations data needed, use intent "unknown" and required_providers []. """


class GeminiService:
    def __init__(self, settings: Settings) -> None:
        self._settings = settings
        self._client: genai.Client | None = None
        if settings.gemini_api_key:
            self._client = genai.Client(api_key=settings.gemini_api_key)

    async def analyze_intent(self, text: str) -> dict[str, Any]:
        if not self._settings.gemini_api_key or self._client is None:
            logger.warning(
                "gemini_config_missing",
                service=_SERVICE,
                operation="analyze_intent",
                reason="GEMINI_API_KEY not set or client not initialized",
            )
            return {
                "intent": "unknown",
                "required_providers": [],
                "confidence": 0.0,
                "entities": {},
                "reasoning": "GEMINI_API_KEY not configured",
                "user_message": "",
            }
        prompt = f"{INTENT_SYSTEM}\n\nUser said:\n{text}\n"
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
            )
            raw = (resp.text or "").strip()
            return self._parse_json_response(raw)
        except Exception as e:
            logger.error(
                "gemini_analyze_intent_failed",
                service=_SERVICE,
                operation="analyze_intent",
                model=self._settings.gemini_model,
                **err_ctx(e),
                exc_info=True,
            )
            return {
                "intent": "unknown",
                "required_providers": [],
                "confidence": 0.0,
                "entities": {},
                "reasoning": str(e),
                "user_message": "",
            }

    def _parse_json_response(self, raw: str) -> dict[str, Any]:
        raw = raw.strip()
        fence = re.search(r"```(?:json)?\s*([\s\S]*?)```", raw)
        if fence:
            raw = fence.group(1).strip()
        try:
            return json.loads(raw)
        except json.JSONDecodeError as e:
            logger.error(
                "gemini_intent_json_parse_failed",
                service=_SERVICE,
                operation="parse_intent_json",
                raw_preview=raw[:400],
                **err_ctx(e),
                exc_info=True,
            )
            return {
                "intent": "unknown",
                "required_providers": [],
                "confidence": 0.0,
                "entities": {},
                "reasoning": f"Model returned invalid JSON: {e}",
                "user_message": "",
            }

    async def unsupported_capability_reply(
        self,
        *,
        user_text: str,
        reasoning: str | None,
        invalid_providers: list[str] | None,
    ) -> str:
        """Spoken reply when the user asks for capabilities outside Gmail/Calendar."""
        system = (
            "You are Actra, a concise voice assistant. You may use light Markdown when it helps readability: "
            "**bold**, short bullet lists, inline `code` for identifiers or paths. Avoid heavy headings or long documents. "
            "The user asked for something you cannot do: Actra integrates Gmail, Google Calendar, Slack, and GitHub. "
            "Be warm, brief (2-4 sentences). Acknowledge their request, explain the limit, "
            "and suggest something you can do (email, calendar, Slack, GitHub repos and issues, drafts)."
        )
        parts = [f"User said: {user_text}"]
        if reasoning:
            parts.append(f"Analysis: {reasoning}")
        if invalid_providers:
            parts.append(f"Invalid or unavailable integrations mentioned: {', '.join(invalid_providers)}")
        prompt = f"{system}\n\n" + "\n".join(parts)
        if not self._settings.gemini_api_key or self._client is None:
            return (
                "I can help with Gmail, Google Calendar, Slack, and GitHub — email, your schedule, "
                "your workspace, or repositories and issues. Ask me anytime."
            )
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
            )
            return (resp.text or "").strip()
        except Exception as e:
            logger.error(
                "gemini_unsupported_reply_failed",
                service=_SERVICE,
                operation="unsupported_capability_reply",
                model=self._settings.gemini_model,
                **err_ctx(e),
                exc_info=True,
            )
            return (
                "I can connect to Gmail, Google Calendar, Slack, and GitHub. "
                "Try asking me to send an email, check your calendar, something about Slack, or GitHub issues."
            )

    async def draft_full_text(
        self,
        *,
        user_text: str,
        intent: str,
        context_snippets: dict[str, Any],
        memory_context: str | None = None,
    ) -> str:
        system = (
            "You are Actra, a natural voice assistant. Use light Markdown when it helps: **bold**, bullet lists, "
            "inline `code` for names or paths, short fenced blocks only for snippets. Sound human: warm, clear, and direct — "
            "never robotic or like a status message. "
            "When Context includes gmail (a list of messages with from, subject, date, snippet), "
            "use it to answer. For 'latest' or 'last' email with no specific search, use the first "
            "item (newest first). Mention sender and subject; summarize the snippet in your own words. "
            "Do not say you are retrieving, loading, or checking — you already have the data. "
            "If gmail is an empty list but gmail_search_note is present, follow that note: "
            "do not say there is no email from that sender everywhere — only that this search "
            "did not match; suggest Promotions, Updates, or Spam, or different wording. "
            "If the list is empty and there is no gmail_search_note, say the inbox looks empty. "
            "When Context includes calendar events, summarize them helpfully. "
            "When Context includes slack: use team name and channels_sample for listing channels. "
            "If recent_messages is a non-empty list (each item has from, text), use it for questions about "
            "the latest message, recent messages, or what was said — newest first. Quote or paraphrase "
            "the actual text; do not invent messages. If recent_messages is empty but messages_error or "
            "messages_note explains why, say that briefly. "
            "do not invent channels or messages not shown in Context. "
            "When Context includes github: for repo_search, summarize matching repositories (name, description). "
            "For issues, summarize titles and numbers; if a single issue detail is present, summarize its body briefly. "
            "If Context.github contains error missing_repo or github_clarify, you do not have issue data — do not list issues; "
            "give a short helpful line only if the Context asks you to (normally the server handles this separately)."
        )
        parts: list[str] = [system]
        if memory_context:
            parts.append(memory_context)
        parts.append(f"\n\nContext: {context_snippets}\n\nUser request: {user_text}\nIntent: {intent}\n")
        prompt = "\n".join(parts)
        if not self._settings.gemini_api_key or self._client is None:
            logger.warning(
                "gemini_config_missing",
                service=_SERVICE,
                operation="draft_full_text",
                reason="GEMINI_API_KEY not set",
            )
            return "Actra needs GEMINI_API_KEY configured on the server to draft responses."
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
            )
            return (resp.text or "").strip()
        except Exception as e:
            logger.error(
                "gemini_draft_full_text_failed",
                service=_SERVICE,
                operation="draft_full_text",
                model=self._settings.gemini_model,
                **err_ctx(e),
                exc_info=True,
            )
            return f"I hit an error while drafting: {e}"

    _GITHUB_FOLLOWUP_KINDS: dict[str, str] = {
        "need_repo": (
            "The user asked about GitHub issues or a repository but did not name which repo. "
            "Reply with light Markdown if useful (**bold** or `owner/repo`). Be warm and brief (2–4 sentences). "
            "Ask which repository they mean, using the standard GitHub form owner/name "
            "(for example octocat/Hello-World). Offer to list issues once they share it."
        ),
        "ambiguous_this_repo": (
            "The user said things like “this repo”, “the repo”, or “my repo” but did not name owner/name, "
            "so you cannot know which GitHub repository they mean. "
            "Light Markdown is fine. Be friendly and brief. "
            "Explain you need the repo in owner/name form, give one short example, and invite them to say it."
        ),
        "need_search_query": (
            "The user wanted to search GitHub repositories but did not say what to search for. "
            "Briefly ask what topic, language, or name they want to find."
        ),
        "need_fix_details": (
            "The user wants to fix an issue or open a PR on GitHub but did not give both a repository (owner/name) "
            "and an issue number. Ask for what is missing in one warm message; use `owner/repo` or **bold** sparingly if helpful; "
            "give an example like: fix issue 12 in octocat/Hello-World."
        ),
    }

    async def github_followup_reply(
        self,
        *,
        user_text: str,
        kind: str,
        memory_context: str | None = None,
    ) -> str:
        """Natural follow-up when GitHub intent is missing owner/repo, search terms, or issue number."""
        instruction = self._GITHUB_FOLLOWUP_KINDS.get(
            kind,
            self._GITHUB_FOLLOWUP_KINDS["need_repo"],
        )
        parts = [instruction, f"\nUser said: {user_text}"]
        if memory_context:
            parts.append(
                f"\nRecent conversation context (may mention a repo — use only if it clearly names owner/name):\n{memory_context}"
            )
        prompt = "\n".join(parts)
        if not self._settings.gemini_api_key or self._client is None:
            if kind == "ambiguous_this_repo":
                return (
                    "I’m not sure which repository you mean yet. "
                    "Tell me the repo in owner/name form — for example octocat/Hello-World — "
                    "and I can list the issues."
                )
            if kind == "need_search_query":
                return "What should I search for on GitHub? For example a topic, language, or project name."
            if kind == "need_fix_details":
                return (
                    "To open a fix pull request, I need the repository as owner/name and the issue number — "
                    "for example: fix issue 12 in octocat/Hello-World."
                )
            return (
                "Which GitHub repository should I use? Say it like owner/name — for example octocat/Hello-World."
            )
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
            )
            return (resp.text or "").strip()
        except Exception as e:
            logger.error(
                "gemini_github_followup_failed",
                service=_SERVICE,
                operation="github_followup_reply",
                kind=kind,
                **err_ctx(e),
                exc_info=True,
            )
            return (
                "Which GitHub repository do you mean? Use owner/name — for example octocat/Hello-World — "
                "and I’ll pull the issues."
            )

    async def emit_stream_chunks(
        self,
        full_text: str,
        on_chunk: Callable[[str], Awaitable[None]],
    ) -> None:
        """Emit agent_stream chunk deltas (whitespace-separated words)."""
        try:
            words = full_text.split()
            if not words:
                await on_chunk("")
                return
            for w in words:
                await on_chunk(w + " ")
        except Exception as e:
            logger.error(
                "gemini_emit_stream_failed",
                service=_SERVICE,
                operation="emit_stream_chunks",
                **err_ctx(e),
                exc_info=True,
            )
            raise

    async def emit_stream_code_lines(
        self,
        full_text: str,
        on_chunk: Callable[[str], Awaitable[None]],
    ) -> None:
        """Stream code with line-oriented chunks for a smoother code preview."""
        try:
            lines = full_text.splitlines()
            if not lines and full_text:
                await on_chunk(full_text)
                return
            for i, line in enumerate(lines):
                suffix = "\n" if i < len(lines) - 1 or full_text.endswith("\n") else ""
                await on_chunk(line + suffix)
        except Exception as e:
            logger.error(
                "gemini_emit_code_stream_failed",
                service=_SERVICE,
                operation="emit_stream_code_lines",
                **err_ctx(e),
                exc_info=True,
            )
            raise

    _GITHUB_PR_JSON_SYSTEM = (
        "You are a senior software engineer. Return ONLY valid JSON — no markdown fences, no commentary. "
        "Put file bytes in file_content_base64 (standard base64, single line, no spaces) so the JSON stays valid. "
        "Never put raw multi-line file text inside a JSON string.\n"
        "Schema:\n"
        "{\n"
        '  "explanation": "Short plain-text summary for the user (what you will change and why).",\n'
        '  "file_path": "relative/path/in/repo.ext",\n'
        '  "file_content_base64": "BASE64 of UTF-8 file bytes (one line).",\n'
        '  "commit_message": "One-line conventional commit message.",\n'
        '  "pr_title": "Concise PR title.",\n'
        '  "pr_body": "Markdown PR description; link the issue with #N if issue number known.",\n'
        '  "head_branch": "branch-name-lowercase-with-hyphens"\n'
        "}\n"
        "Rules: make minimal, correct changes. If the repo or issue is unclear, still propose a small "
        "reasonable fix (e.g. docs or a tiny helper). head_branch must start with actra-fix-."
    )

    def _parse_github_pr_patch_json(self, raw: str) -> dict[str, Any]:
        """Parse PR patch JSON; decode ``file_content_base64`` into ``file_content``."""
        raw = raw.strip()
        fence = re.search(r"```(?:json)?\s*([\s\S]*?)```", raw)
        if fence:
            raw = fence.group(1).strip()
        try:
            data = json.loads(raw)
        except json.JSONDecodeError as e:
            logger.error(
                "gemini_github_pr_patch_json_parse_failed",
                service=_SERVICE,
                operation="parse_github_pr_patch_json",
                raw_preview=raw[:500],
                **err_ctx(e),
                exc_info=True,
            )
            return {
                "error": f"invalid_json: {e}",
                "explanation": "The patch response was not valid JSON. Try again.",
                "file_path": "actra-error.txt",
                "file_content": f"# JSON parse error: {e}\n",
                "commit_message": "chore: error",
                "pr_title": "Error",
                "pr_body": str(e),
                "head_branch": "actra-fix-error",
            }
        if not isinstance(data, dict):
            return {
                "error": "invalid_shape",
                "explanation": "The model did not return a JSON object.",
                "file_path": "actra-error.txt",
                "file_content": "# Invalid response\n",
                "commit_message": "chore: error",
                "pr_title": "Error",
                "pr_body": "",
                "head_branch": "actra-fix-error",
            }
        out: dict[str, Any] = dict(data)
        b64_val = out.get("file_content_base64") or out.get("file_content_b64")
        if isinstance(b64_val, str) and b64_val.strip():
            try:
                out["file_content"] = base64.b64decode(b64_val).decode("utf-8")
            except (ValueError, UnicodeDecodeError) as dec_e:
                logger.warning(
                    "gemini_github_pr_base64_decode_failed",
                    service=_SERVICE,
                    **err_ctx(dec_e),
                )
                out["file_content"] = str(out.get("file_content") or "")
        elif isinstance(out.get("file_content"), str):
            pass
        else:
            out["file_content"] = ""
        return out

    async def generate_github_pr_patch(
        self,
        *,
        user_request: str,
        issue_title: str,
        issue_body: str,
        repo_full_name: str,
        default_branch: str,
    ) -> dict[str, Any]:
        """Structured patch proposal for opening a GitHub PR."""
        if not self._settings.gemini_api_key or self._client is None:
            return {
                "error": "GEMINI_API_KEY not configured",
                "explanation": "Server is missing Gemini configuration.",
                "file_path": "README.md",
                "file_content": "# Patch unavailable\n",
                "commit_message": "chore: placeholder",
                "pr_title": "Placeholder",
                "pr_body": "Configure GEMINI_API_KEY.",
                "head_branch": "actra-fix-placeholder",
            }
        prompt = (
            f"{self._GITHUB_PR_JSON_SYSTEM}\n\n"
            f"Repository: {repo_full_name} (default branch: {default_branch})\n"
            f"Issue title: {issue_title}\n"
            f"Issue body:\n{issue_body}\n\n"
            f"User request:\n{user_request}\n"
        )
        try:
            resp = await self._client.aio.models.generate_content(
                model=self._settings.gemini_model,
                contents=prompt,
                config=genai_types.GenerateContentConfig(max_output_tokens=16384),
            )
            raw = (resp.text or "").strip()
            return self._parse_github_pr_patch_json(raw)
        except Exception as e:
            logger.error(
                "gemini_github_pr_patch_failed",
                service=_SERVICE,
                operation="generate_github_pr_patch",
                **err_ctx(e),
                exc_info=True,
            )
            return {
                "error": str(e),
                "explanation": "Could not generate a patch.",
                "file_path": "actra-error.txt",
                "file_content": f"Error: {e}\n",
                "commit_message": "chore: error",
                "pr_title": "Error",
                "pr_body": str(e),
                "head_branch": "actra-fix-error",
            }
