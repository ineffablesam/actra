from __future__ import annotations

import base64
from typing import Any

import httpx
import structlog

from src.utils.service_log import err_ctx

logger = structlog.get_logger(__name__)

_SERVICE = "github"
_API = "https://api.github.com"


def user_facing_github_error(exc: BaseException) -> str:
    """
    Map GitHub REST / httpx failures to a short message for WebSocket clients.

    ``403`` with *Resource not accessible by integration* usually means the token
    cannot write to that repo (org OAuth app approval, fine-grained token, or
    Auth0 GitHub connection not granting write access to the target org/repo).
    """
    if isinstance(exc, httpx.HTTPStatusError):
        r = exc.response
        status = r.status_code
        text = (r.text or "").lower()
        if status == 403:
            if "not accessible by integration" in text:
                return (
                    "GitHub refused to update this repository: the integration token cannot write here "
                    "(403). For organization repos, an org admin may need to approve the app or install "
                    "it with write access. Reconnect GitHub in Connected Accounts, or ensure your GitHub "
                    "OAuth app has access to this repository."
                )
            if "must have push access" in text or "write access" in text:
                return (
                    "GitHub refused: your account needs push access to this repository to open a pull request."
                )
        if status == 404:
            if "branch" in text and "not found" in text:
                return (
                    "GitHub could not find that branch for this repository. "
                    "If this keeps happening, try confirming the default branch name in the repo."
                )
            return "GitHub could not find that repository or path (check owner/name and visibility)."
        if status == 422:
            return "GitHub rejected the request (validation error). The branch or file may conflict; try again."
        if status == 409:
            if "does not match" in text:
                return (
                    "GitHub refused the file update (content changed on the branch). "
                    "Try again with a new branch; delete the old actra-fix-* branch on the repo if it is stuck."
                )
            return "GitHub conflict (409). The branch or file may have changed; try again."
    return f"Could not open pull request: {exc}"


class GitHubService:
    """GitHub REST API using an OAuth user access token (Auth0 Token Vault → federated token)."""

    def __init__(self) -> None:
        self._client = httpx.AsyncClient(
            base_url=_API,
            headers={"Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2022-11-28"},
            timeout=45.0,
        )

    async def aclose(self) -> None:
        await self._client.aclose()

    def _auth_headers(self, token: str) -> dict[str, str]:
        return {"Authorization": f"Bearer {token}"}

    async def search_repositories(self, token: str, query: str, *, per_page: int = 5) -> list[dict[str, Any]]:
        try:
            r = await self._client.get(
                "/search/repositories",
                params={"q": query, "per_page": per_page},
                headers=self._auth_headers(token),
            )
            r.raise_for_status()
            data = r.json()
            return list(data.get("items", []))
        except Exception as e:
            logger.error(
                "github_search_repos_failed",
                service=_SERVICE,
                operation="search_repositories",
                **err_ctx(e),
                exc_info=True,
            )
            raise

    async def list_issues(
        self,
        token: str,
        owner: str,
        repo: str,
        *,
        state: str = "open",
        per_page: int = 15,
    ) -> list[dict[str, Any]]:
        try:
            r = await self._client.get(
                f"/repos/{owner}/{repo}/issues",
                params={"state": state, "per_page": per_page},
                headers=self._auth_headers(token),
            )
            r.raise_for_status()
            raw = r.json()
            if not isinstance(raw, list):
                return []
            # Exclude pull requests (GitHub returns PRs as issues too)
            return [x for x in raw if not x.get("pull_request")]
        except Exception as e:
            logger.error(
                "github_list_issues_failed",
                service=_SERVICE,
                operation="list_issues",
                owner=owner,
                repo=repo,
                **err_ctx(e),
                exc_info=True,
            )
            raise

    async def get_issue(
        self,
        token: str,
        owner: str,
        repo: str,
        issue_number: int,
    ) -> dict[str, Any]:
        r = await self._client.get(
            f"/repos/{owner}/{repo}/issues/{issue_number}",
            headers=self._auth_headers(token),
        )
        r.raise_for_status()
        return r.json()

    async def get_default_branch(self, token: str, owner: str, repo: str) -> str:
        r = await self._client.get(f"/repos/{owner}/{repo}", headers=self._auth_headers(token))
        r.raise_for_status()
        data = r.json()
        return str(data.get("default_branch") or "main")

    async def ensure_branch_from_base(
        self,
        token: str,
        owner: str,
        repo: str,
        base_branch: str,
        head_branch: str,
    ) -> None:
        """
        Create ``head_branch`` at the same commit as ``base_branch`` if it does not exist.

        The Contents API does not create a missing branch for the first commit; refs must exist first.
        """
        headers = self._auth_headers(token)
        r_head = await self._client.get(
            f"/repos/{owner}/{repo}/git/ref/heads/{head_branch}",
            headers=headers,
        )
        if r_head.status_code == 200:
            return
        if r_head.status_code != 404:
            r_head.raise_for_status()

        r_base = await self._client.get(
            f"/repos/{owner}/{repo}/git/ref/heads/{base_branch}",
            headers=headers,
        )
        r_base.raise_for_status()
        base_obj = r_base.json().get("object") or {}
        base_sha = base_obj.get("sha")
        if not isinstance(base_sha, str) or not base_sha:
            raise RuntimeError(f"Could not resolve SHA for base branch {base_branch!r}")

        r_create = await self._client.post(
            f"/repos/{owner}/{repo}/git/refs",
            json={"ref": f"refs/heads/{head_branch}", "sha": base_sha},
            headers=headers,
        )
        if r_create.status_code in (200, 201):
            return
        if r_create.status_code == 422:
            r2 = await self._client.get(
                f"/repos/{owner}/{repo}/git/ref/heads/{head_branch}",
                headers=headers,
            )
            if r2.status_code == 200:
                return
        if r_create.status_code >= 400:
            logger.error(
                "github_create_ref_failed",
                service=_SERVICE,
                status=r_create.status_code,
                body=(r_create.text or "")[:500],
            )
        r_create.raise_for_status()

    async def create_branch_commit_and_pr(
        self,
        token: str,
        *,
        owner: str,
        repo: str,
        base_branch: str,
        head_branch: str,
        file_path: str,
        file_content: str,
        commit_message: str,
        pr_title: str,
        pr_body: str,
    ) -> dict[str, Any]:
        """
        Creates a new branch from default, adds/updates one file via Contents API, opens a PR.
        """
        headers = self._auth_headers(token)
        await self.ensure_branch_from_base(token, owner, repo, base_branch, head_branch)

        b64 = base64.b64encode(file_content.encode("utf-8")).decode("ascii")

        put_path = f"/repos/{owner}/{repo}/contents/{file_path}"
        put_body: dict[str, Any] = {
            "message": commit_message,
            "content": b64,
            "branch": head_branch,
        }

        # SHA must be from the **same branch** we commit to (head). Using base_branch breaks
        # when head already exists (e.g. retry) or diverged — GitHub returns 409 "does not match".
        r_get = await self._client.get(
            put_path,
            params={"ref": head_branch},
            headers=headers,
        )
        if r_get.status_code == 200:
            prev = r_get.json()
            sha = prev.get("sha")
            if isinstance(sha, str) and sha:
                put_body["sha"] = sha

        r_put = await self._client.put(put_path, json=put_body, headers=headers)
        if r_put.status_code >= 400:
            logger.error(
                "github_put_contents_failed",
                service=_SERVICE,
                status=r_put.status_code,
                body=(r_put.text or "")[:500],
            )
        r_put.raise_for_status()

        r_pr = await self._client.post(
            f"/repos/{owner}/{repo}/pulls",
            json={
                "title": pr_title,
                "head": head_branch,
                "base": base_branch,
                "body": pr_body,
            },
            headers=headers,
        )
        if r_pr.status_code >= 400:
            logger.error(
                "github_create_pr_failed",
                service=_SERVICE,
                status=r_pr.status_code,
                body=(r_pr.text or "")[:500],
            )
        r_pr.raise_for_status()
        pr_data = r_pr.json()
        return {
            "number": pr_data.get("number"),
            "html_url": pr_data.get("html_url"),
            "id": pr_data.get("id"),
            "head": head_branch,
            "base": base_branch,
        }
