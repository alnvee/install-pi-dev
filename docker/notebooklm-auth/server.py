import os
import subprocess
from pathlib import Path

from fastmcp import FastMCP


AUTH_DIR = Path(os.environ.get("NOTEBOOKLM_AUTH_DIR", "/root/.notebooklm-mcp-cli"))

mcp = FastMCP("NotebookLM Auth Helper")


@mcp.tool()
def notebooklm_login(mode: str = "login") -> dict[str, str]:
    AUTH_DIR.mkdir(parents=True, exist_ok=True)

    if mode not in {"login", "check", "manual"}:
        raise ValueError('mode must be one of: login, check, manual')

    command = ["nlm", "login"]
    if mode == "check":
        command.append("--check")
    elif mode == "manual":
        command.append("--manual")

    result = subprocess.run(command, check=False, capture_output=True, text=True)

    if result.returncode != 0:
        error_text = result.stderr.strip() or result.stdout.strip() or "NotebookLM login failed"
        raise RuntimeError(error_text)

    return {"status": "ok", "message": result.stdout.strip() or "NotebookLM login completed"}


if __name__ == "__main__":
    mcp.run()
