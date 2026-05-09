FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NOTEBOOKLM_MCP_TRANSPORT=stdio \
    HOME=/root

RUN pip install --no-cache-dir notebooklm-mcp-cli \
    && mkdir -p /root/.notebooklm-mcp-cli

VOLUME ["/root/.notebooklm-mcp-cli"]

CMD ["notebooklm-mcp"]

