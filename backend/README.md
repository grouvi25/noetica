# Noetica backend

FastAPI service for registration-free web sessions, cloud sync, and AI-powered
roadmap/tools generation via the user's OmniRoute OpenAI-compatible gateway.

## Endpoints

- `GET /healthz` — liveness probe.
- `GET /healthz/llm` — reports LLM provider/model/status.
- `POST /auth/anonymous` — registration-free web session keyed by a stable browser id.
- `POST /auth/google` — legacy native Google sign-in.
- `POST /sync/pull`, `POST /sync/push` — per-user cloud sync.
- `POST /roadmap/generate` — goal + profile + axes → `{tasks, summary, model}`.

## Environment

| Variable | Required | Default | Description |
| --- | --- | --- | --- |
| `OMNIROUTE_API_KEY` | yes | — | OmniRoute API key. Kept server-side only. |
| `LLM_BASE_URL` | no | `https://freelance-gid.online/v1` | OpenAI-compatible gateway base URL. |
| `LLM_MODEL` | no | `zo/zo:anthropic/claude-opus-4-7` | Model id supported by OmniRoute. |
| `JWT_SECRET` | prod | auto-generated in `/data` | Signs Noetica session JWTs. |
| `DEV_SKIP_AUTH` | no | `false` | Dev-only bypass for local backend previews. |
| `CORS_ORIGINS` | no | `*` | Comma-separated list. |
| `PORT` | no | `8080` | HTTP port. |

All LLM calls use `stream: true` to avoid Cloudflare timeouts.

## Local dev

```bash
cd backend
uv pip install -e .  # or: pip install -e .
export OMNIROUTE_API_KEY=...
uvicorn app.main:app --reload --port 8080
```

## Deploy (Fly.io)

```bash
cd backend
fly deploy
fly secrets set OMNIROUTE_API_KEY=...
```
