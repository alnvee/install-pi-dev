import os
import subprocess
from pathlib import Path

from notebooklm_tools.mcp.server import main, mcp


AUTH_DIR = Path(os.environ.get("NOTEBOOKLM_AUTH_DIR", "/root/.notebooklm-mcp-cli"))


def _normalize_mode(mode: str) -> str:
    normalized = (mode or "check").strip().lower()
    aliases = {"status": "check"}
    return aliases.get(normalized, normalized)


@mcp.tool()
def notebooklm_login(mode: str = "check") -> dict[str, str]:
    """Run the NotebookLM login helper inside the same MCP container."""
    AUTH_DIR.mkdir(parents=True, exist_ok=True)

    normalized_mode = _normalize_mode(mode)
    if normalized_mode not in {"login", "check", "manual"}:
        raise ValueError("mode must be one of: login, check, manual")

    command = ["nlm", "login"]
    if normalized_mode == "check":
        command.append("--check")
    elif normalized_mode == "manual":
        command.append("--manual")

    result = subprocess.run(command, check=False, capture_output=True, text=True)

    if result.returncode != 0:
        error_text = result.stderr.strip() or result.stdout.strip() or "NotebookLM login failed"
        raise RuntimeError(error_text)

    summary = result.stdout.strip() or f"NotebookLM auth {normalized_mode} completed"
    return {"status": "ok", "mode": normalized_mode, "message": summary}


if __name__ == "__main__":
    main()
