"""Noetica backend — auth, cloud sync, and roadmap generation.

OpenAI-compatible LLM gateway (OpenRouter by default) sits behind
`/roadmap/generate`. We never log prompts or LLM responses — only status,
model, and counts.
"""

from __future__ import annotations

import logging
import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv
from fastapi import Depends, FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from . import db
from .auth import (
    AuthConfigError,
    CurrentUser,
    issue_jwt,
    upsert_anonymous_user,
    upsert_user_from_google,
    verify_google_id_token,
)
from .llm import LlmClient, LlmConfigError, LlmUpstreamError
from .schemas import (
    AxesRequest,
    AxesResponse,
    AxisDraft,
    CoachRequest,
    CoachResponse,
    HabitsPlan,
    HabitsRequest,
    KnowledgeIndexedNode,
    KnowledgeReindexRequest,
    KnowledgeReindexResponse,
    MenuPlan,
    MenuRecipeRequest,
    MenuRecipeResponse,
    MenuRequest,
    RoadmapRequest,
    RoadmapResponse,
)
from .sync import router as sync_router

load_dotenv()

logging.basicConfig(
    level=os.getenv("LOG_LEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(name)s - %(message)s",
)
logger = logging.getLogger("noetica.backend")


@asynccontextmanager
async def _lifespan(app: FastAPI):
    db.configure(os.getenv("NOETICA_DB_PATH", db.DEFAULT_DB_PATH))
    await db.init()
    logger.info("DB initialised at %s", db._db_path)  # noqa: SLF001
    yield


app = FastAPI(
    title="Noetica Backend",
    version="0.2.0",
    description="Auth + cloud sync + LLM roadmap generation.",
    lifespan=_lifespan,
)

_cors_raw = os.getenv("CORS_ORIGINS", "")
_cors_origins = [o.strip() for o in _cors_raw.split(",") if o.strip()]
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins if _cors_origins else ["*"],
    allow_credentials=True,
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["*"],
)


# ---------- /healthz, /auth ----------


@app.get("/healthz")
async def healthz() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/healthz/llm")
async def healthz_llm() -> dict[str, object]:
    """Diagnostic — reports whether the LLM client can initialise.

    Intentionally does NOT return the API key itself, just whether a
    backend is selected and what model/provider is in use.
    """
    from .llm import LlmClient, LlmConfigError
    try:
        client = LlmClient()
    except LlmConfigError as exc:
        return {"ok": False, "error": str(exc)}
    provider = "omniroute"
    if "freelance-gid.online" in (client.base_url or ""):
        provider = "omniroute"
    elif "groq" in (client.base_url or ""):
        provider = "groq"
    elif "generativelanguage" in (client.base_url or ""):
        provider = "gemini"
    elif "openai.com" in (client.base_url or ""):
        provider = "openai"
    return {
        "ok": True,
        "provider": provider,
        "model": client.model,
        "base_url": client.base_url,
    }


class GoogleAuthRequest(BaseModel):
    id_token: str


class AnonymousAuthRequest(BaseModel):
    client_id: str
    display_name: str | None = None


class AuthResponse(BaseModel):
    access_token: str
    token_type: str = "Bearer"
    user: dict


@app.post("/auth/google", response_model=AuthResponse)
async def auth_google(req: GoogleAuthRequest) -> AuthResponse:
    try:
        payload = verify_google_id_token(req.id_token)
    except AuthConfigError as exc:
        logger.error("Auth config error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    user = await upsert_user_from_google(payload)
    token = issue_jwt(user["id"])
    logger.info("auth_google ok user=%s", user["id"][:8])
    return AuthResponse(access_token=token, user=user)


@app.post("/auth/anonymous", response_model=AuthResponse)
async def auth_anonymous(req: AnonymousAuthRequest) -> AuthResponse:
    user = await upsert_anonymous_user(req.client_id, req.display_name)
    token = issue_jwt(user["id"])
    logger.info("auth_anonymous ok user=%s", user["id"][:8])
    return AuthResponse(access_token=token, user=user)


@app.get("/auth/me", response_model=dict)
async def auth_me(user: CurrentUser) -> dict:
    return user


# ---------- /sync ----------

app.include_router(sync_router)


# ---------- /roadmap, /onboarding (now require auth) ----------


@app.post("/roadmap/generate", response_model=RoadmapResponse)
async def generate_roadmap(
    request: RoadmapRequest,
    user: CurrentUser,
) -> RoadmapResponse:
    try:
        client = LlmClient()
    except LlmConfigError as exc:
        logger.error("LLM config error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    try:
        tasks, summary = await client.generate_roadmap(
            goal=request.goal,
            profile=request.profile,
            axes=request.axes,
            horizon_days=request.horizon_days,
            task_count=request.task_count,
            knowledge=request.knowledge,
        )
    except LlmUpstreamError as exc:
        logger.warning("LLM upstream error: status=%s", exc.status)
        raise HTTPException(
            status_code=502, detail="LLM upstream error.",
        ) from exc

    if not tasks:
        raise HTTPException(
            status_code=502,
            detail="LLM returned no usable tasks.",
        )

    logger.info(
        "Generated roadmap: user=%s model=%s tasks=%d axes=%d",
        user["id"][:8],
        client.model,
        len(tasks),
        len(request.axes),
    )
    return RoadmapResponse(
        model=client.model,
        tasks=tasks,
        summary=summary,
    )


@app.post("/onboarding/axes", response_model=AxesResponse)
async def generate_axes(
    request: AxesRequest,
    user: CurrentUser,
) -> AxesResponse:
    try:
        client = LlmClient()
    except LlmConfigError as exc:
        logger.error("LLM config error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    try:
        axes = await client.generate_axes(
            profile=request.profile,
            interests=request.interests,
            count=request.count,
            knowledge=request.knowledge,
            regen_hint=request.regen_hint,
            variation_seed=request.variation_seed,
        )
    except LlmUpstreamError as exc:
        logger.warning("LLM upstream error: status=%s", exc.status)
        # Return fallback axes instead of failing
        axes = [
            AxisDraft(
                name="Тело",
                symbol="◐",
                description="Физическое здоровье, спорт, питание, режим дня",
                color="#FF6B6B",
            ),
            AxisDraft(
                name="Ум",
                symbol="◑",
                description="Интеллектуальное развитие, обучение, навыки",
                color="#4ECDC4",
            ),
            AxisDraft(
                name="Душа",
                symbol="◒",
                description="Эмоциональное благополучие, отношения, творчество",
                color="#45B7D1",
            ),
        ]
        logger.info("Returning fallback axes due to LLM error")
        return AxesResponse(model="fallback", axes=axes)

    if len(axes) < 3:
        raise HTTPException(
            status_code=502,
            detail="LLM returned fewer than 3 usable axes.",
        )

    logger.info(
        "Generated axes: user=%s model=%s axes=%d interests=%d",
        user["id"][:8],
        client.model,
        len(axes),
        len(request.interests),
    )
    return AxesResponse(model=client.model, axes=axes)


# ---------- /tools/menu (Ассистент → Меню недели) ----------


@app.post("/tools/menu/generate", response_model=MenuPlan)
async def tools_menu_generate(
    request: MenuRequest,
    user: CurrentUser,
) -> MenuPlan:
    """Stage-1 — return a 7-day menu structure (no recipe steps).

    The client renders this into a preview table. Recipes are pulled
    on-demand via `/tools/menu/recipe` only for meals the user opens.
    """
    try:
        client = LlmClient()
    except LlmConfigError as exc:
        logger.error("LLM config error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    try:
        plan = await client.generate_menu_plan(
            goal=request.goal,
            servings=request.servings,
            restrictions=request.restrictions,
            extra_notes=request.extra_notes,
        )
    except LlmUpstreamError as exc:
        logger.warning("LLM menu upstream error: status=%s", exc.status)
        raise HTTPException(
            status_code=502, detail="LLM upstream error.",
        ) from exc

    if not plan.days:
        raise HTTPException(
            status_code=502, detail="LLM returned no days for the menu.",
        )

    logger.info(
        "Generated menu: user=%s model=%s days=%d goal=%s servings=%d",
        user["id"][:8],
        plan.model,
        len(plan.days),
        request.goal,
        request.servings,
    )
    return plan


@app.post("/tools/menu/recipe", response_model=MenuRecipeResponse)
async def tools_menu_recipe(
    request: MenuRecipeRequest,
    user: CurrentUser,
) -> MenuRecipeResponse:
    """Stage-2 — return a single full recipe rendered as markdown."""
    try:
        client = LlmClient()
    except LlmConfigError as exc:
        logger.error("LLM config error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    try:
        markdown = await client.generate_meal_recipe(
            meal_name=request.meal_name,
            ingredients=[i.model_dump() for i in request.ingredients],
            goal=request.goal,
            servings=request.servings,
        )
    except LlmUpstreamError as exc:
        logger.warning("LLM recipe upstream error: status=%s", exc.status)
        raise HTTPException(
            status_code=502, detail="LLM upstream error.",
        ) from exc

    logger.info(
        "Generated recipe: user=%s model=%s meal=%r ings=%d",
        user["id"][:8],
        client.model,
        request.meal_name[:40],
        len(request.ingredients),
    )
    return MenuRecipeResponse(model=client.model, markdown=markdown)


@app.post("/tools/habits/generate", response_model=HabitsPlan)
async def tools_habits_generate(
    request: HabitsRequest,
    user: CurrentUser,
) -> HabitsPlan:
    """Generate an N-day micro-habit plan from a free-form intent.

    Returns one tiny daily action per requested day. The client
    imports them as N due-dated tasks tagged with `challenge/<id>`.
    """
    try:
        client = LlmClient()
    except LlmConfigError as exc:
        logger.error("LLM config error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    try:
        plan = await client.generate_habits_plan(
            intent=request.intent,
            duration_days=request.duration_days,
            axis_hint=request.axis_hint,
            notes=request.notes,
        )
    except LlmUpstreamError as exc:
        logger.warning("LLM habits upstream error: status=%s", exc.status)
        raise HTTPException(
            status_code=502, detail="LLM upstream error.",
        ) from exc

    if len(plan.days) < request.duration_days:
        raise HTTPException(
            status_code=502,
            detail=(
                f"LLM returned {len(plan.days)} days but {request.duration_days} "
                "were requested."
            ),
        )

    logger.info(
        "Generated habits: user=%s model=%s days=%d",
        user["id"][:8],
        plan.model,
        len(plan.days),
    )
    return plan


@app.post("/coach/generate", response_model=CoachResponse)
async def generate_coach(
    request: CoachRequest,
    user: CurrentUser,
):
    """AI Coach — morning plan or evening reflection."""
    try:
        result = await llm.generate_coach(
            mode=request.mode,
            name=request.name,
            aspiration=request.aspiration,
            axes=request.axes,
            active_tasks=request.active_tasks,
            completed_today=request.completed_today,
            remaining=request.remaining,
            entries_today=request.entries_today,
            streak=request.streak,
        )
    except LlmConfigError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
    except LlmUpstreamError as exc:
        raise HTTPException(status_code=exc.status, detail=str(exc)) from exc

    mode = request.mode
    if mode == "morning":
        morning_data = {
            "greeting": result.get("greeting", ""),
            "focus": result.get("focus", ""),
            "tasks": result.get("tasks", []),
            "motivation": result.get("motivation", ""),
        }
        resp = CoachResponse(
            model=result.get("model", ""),
            mode=mode,
            morning=morning_data,
        )
    else:
        evening_data = {
            "summary": result.get("summary", ""),
            "wins": result.get("wins", []),
            "improvements": result.get("improvements", []),
            "encouragement": result.get("encouragement", ""),
        }
        resp = CoachResponse(
            model=result.get("model", ""),
            mode=mode,
            evening=evening_data,
        )

    logger.info(
        "Coach generated: user=%s mode=%s model=%s",
        user["id"][:8],
        mode,
        resp.model,
    )
    return resp


# ---------- /knowledge/reindex (Obsidian-style librarian) ----------


@app.post("/knowledge/reindex", response_model=KnowledgeReindexResponse)
async def reindex_knowledge(
    request: KnowledgeReindexRequest,
    user: CurrentUser,
) -> KnowledgeReindexResponse:
    note_ids = {n.id for n in request.notes if n.id}
    if not note_ids:
        return KnowledgeReindexResponse(model="empty", folders=[], nodes=[])

    try:
        client = LlmClient()
    except LlmConfigError as exc:
        logger.error("LLM config error: %s", exc)
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    notes_payload = [
        {
            "id": n.id,
            "title": n.title,
            "body": n.body,
            "tags": n.tags,
        }
        for n in request.notes
    ]

    try:
        raw = await client.generate_knowledge_index(
            notes_payload,
            max_folders=request.max_folders,
        )
    except LlmUpstreamError as exc:
        logger.warning("LLM upstream error in knowledge reindex: status=%s", exc.status)
        # Deterministic fallback so the UI keeps working.
        return KnowledgeReindexResponse(
            model="fallback",
            folders=["Untagged"],
            nodes=[
                KnowledgeIndexedNode(
                    id=n.id,
                    folder="Untagged",
                    summary=(n.title or n.body[:120]),
                    tags=n.tags,
                    related_ids=[],
                )
                for n in request.notes
            ],
        )

    # Normalise the LLM JSON. The model is told to keep the schema but
    # we still defensively clean every field.
    raw_folders = raw.get("folders") or []
    folder_names: list[str] = []
    seen_folders: set[str] = set()
    for f in raw_folders:
        if isinstance(f, dict):
            name = str(f.get("name", "")).strip()
        else:
            name = str(f).strip()
        if not name or name.lower() in seen_folders:
            continue
        seen_folders.add(name.lower())
        folder_names.append(name[:32])
    if not folder_names:
        folder_names = ["Misc"]

    raw_nodes = raw.get("nodes") or []
    nodes: list[KnowledgeIndexedNode] = []
    seen_ids: set[str] = set()
    folder_set_lower = {n.lower(): n for n in folder_names}
    for n in raw_nodes:
        if not isinstance(n, dict):
            continue
        nid = str(n.get("id", "")).strip()
        if not nid or nid not in note_ids or nid in seen_ids:
            continue
        seen_ids.add(nid)

        folder = str(n.get("folder", "")).strip()
        folder = folder_set_lower.get(folder.lower(), folder)
        if not folder:
            folder = folder_names[0]
        if folder not in folder_names:
            folder_names.append(folder)
            folder_set_lower[folder.lower()] = folder

        summary = str(n.get("summary", "")).strip()[:240]
        tags_raw = n.get("tags") or []
        tags = [str(t).strip()[:32] for t in tags_raw if str(t).strip()][:8]

        related_raw = n.get("related_ids") or []
        related: list[str] = []
        for r in related_raw:
            rs = str(r).strip()
            if rs and rs in note_ids and rs != nid and rs not in related:
                related.append(rs)
            if len(related) >= 3:
                break

        nodes.append(
            KnowledgeIndexedNode(
                id=nid,
                folder=folder,
                summary=summary,
                tags=tags,
                related_ids=related,
            )
        )

    # Make sure every input note is represented — fall back to the
    # first folder if the model dropped some.
    for n in request.notes:
        if n.id and n.id not in seen_ids:
            nodes.append(
                KnowledgeIndexedNode(
                    id=n.id,
                    folder=folder_names[0],
                    summary=(n.title or n.body[:120]),
                    tags=n.tags,
                    related_ids=[],
                )
            )

    logger.info(
        "Knowledge reindex: user=%s model=%s notes=%d folders=%d",
        user["id"][:8],
        raw.get("model", ""),
        len(nodes),
        len(folder_names),
    )

    return KnowledgeReindexResponse(
        model=str(raw.get("model", "")),
        folders=folder_names,
        nodes=nodes,
    )


_ = Depends  # silence unused import warning when no other Depends is used here
