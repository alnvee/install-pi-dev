FROM python:3.13-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    NOTEBOOKLM_MCP_TRANSPORT=stdio \
    HOME=/root

RUN pip install --no-cache-dir fastmcp notebooklm-mcp-cli \
    && mkdir -p /root/.notebooklm-mcp-cli

COPY docker/notebooklm-auth/server.py /app/server.py

VOLUME ["/root/.notebooklm-mcp-cli"]

CMD ["python", "/app/server.py"]
