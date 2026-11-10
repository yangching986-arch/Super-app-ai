"""Hybrid AI Super App - Phase 1-2 backend (free-only, auto fallback).
Run: pip install fastapi uvicorn httpx && uvicorn main:app --reload
Keys: set env GEMINI_API_KEY, GROQ_API_KEY, CEREBRAS_API_KEY, OPENROUTER_API_KEY, MISTRAL_API_KEY
"""
import os, time
import httpx
from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from db import Base, engine, get_db, User, Conversation, Message
from auth import router as auth_router, current_user
from pydantic import BaseModel

app = FastAPI(title="Hybrid AI Super App")
Base.metadata.create_all(engine)
app.include_router(auth_router)

# Free limits change often: keep model IDs and limits here, not in code.
MODELS = {
    "gemini":   {"name": "Gemini Flash", "base": "https://generativelanguage.googleapis.com/v1beta/openai",
                 "model": "gemini-2.5-flash", "env": "GEMINI_API_KEY", "free": True, "rpm": 10},
    "groq":     {"name": "Llama 70B (Groq)", "base": "https://api.groq.com/openai/v1",
                 "model": "llama-3.3-70b-versatile", "env": "GROQ_API_KEY", "free": True, "rpm": 30},
    "cerebras": {"name": "Cerebras", "base": "https://api.cerebras.ai/v1",
                 "model": "llama-3.3-70b", "env": "CEREBRAS_API_KEY", "free": True, "rpm": 30},
    "deepseek": {"name": "DeepSeek (free)", "base": "https://openrouter.ai/api/v1",
                 "model": "deepseek/deepseek-chat-v3-0324:free", "env": "OPENROUTER_API_KEY", "free": True, "rpm": 20},
    "mistral":  {"name": "Mistral", "base": "https://api.mistral.ai/v1",
                 "model": "mistral-small-latest", "env": "MISTRAL_API_KEY", "free": True, "rpm": 30},
    "claude":   {"name": "Claude", "free": False},   # needs user's own key (Phase 6)
    "grok":     {"name": "Grok", "free": False},     # needs user's own key (Phase 6)
}

_cooldown: dict[str, float] = {}  # model id -> time until usable again


class ChatIn(BaseModel):
    message: str
    model: str | None = None      # None = smart router
    free_only: bool = True
    conversation_id: int | None = None
    user_keys: dict[str, str] = {}  # custom keys, used only if provided


def route(message: str) -> list[str]:
    """Smart router: ordered candidates by question type."""
    m = message.lower()
    if any(w in m for w in ("code", "bug", "python", "function", "কোড")):
        order = ["mistral", "groq", "cerebras", "gemini", "deepseek"]
    elif len(message) > 3000:
        order = ["gemini", "deepseek", "mistral", "groq", "cerebras"]
    else:
        order = ["groq", "cerebras", "gemini", "mistral", "deepseek"]
    return order


def key_for(mid: str, body: ChatIn) -> str | None:
    return body.user_keys.get(mid) or os.getenv(MODELS[mid].get("env", ""), None)


async def call(mid: str, key: str, message: str) -> str:
    cfg = MODELS[mid]
    async with httpx.AsyncClient(timeout=60) as c:
        r = await c.post(
            f"{cfg['base']}/chat/completions",
            headers={"Authorization": f"Bearer {key}"},
            json={"model": cfg["model"], "messages": [{"role": "user", "content": message}]},
        )
    if r.status_code == 429:
        raise RuntimeError("quota")
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


@app.get("/models")
def models():
    now = time.time()
    out = []
    for mid, cfg in MODELS.items():
        status = "needs_key" if not cfg["free"] else (
            "limited" if _cooldown.get(mid, 0) > now else "free")
        out.append({"id": mid, "name": cfg["name"], "status": status})
    return out


async def run_chat(body: ChatIn):
    order = [body.model] if body.model else []
    order += [m for m in route(body.message) if m not in order]
    tried = []
    for mid in order:
        cfg = MODELS.get(mid)
        if not cfg or "base" not in cfg:
            continue
        if body.free_only and not cfg["free"]:
            continue
        if _cooldown.get(mid, 0) > time.time():
            continue
        key = key_for(mid, body)
        if not key:
            continue
        try:
            text = await call(mid, key, body.message)
            return {"answer": text, "model": cfg["name"], "fallback": bool(tried), "tried": tried}
        except Exception:
            _cooldown[mid] = time.time() + 60  # rest this provider for 1 minute
            tried.append(cfg["name"])
    return {"answer": None, "error": "All free models are busy. Try again in a minute.", "tried": tried}


@app.post("/chat")
async def chat(body: ChatIn, user: User = Depends(current_user), db: Session = Depends(get_db)):
    conv = db.get(Conversation, body.conversation_id) if body.conversation_id else None
    if conv and conv.user_id != user.id:
        raise HTTPException(404, "Conversation not found.")
    if not conv:
        conv = Conversation(user_id=user.id, title=body.message[:40])
        db.add(conv)
        db.flush()
    db.add(Message(conv_id=conv.id, role="user", content=body.message))
    res = await run_chat(body)
    if res.get("answer"):
        db.add(Message(conv_id=conv.id, role="assistant", content=res["answer"], model=res["model"]))
    db.commit()
    res["conversation_id"] = conv.id
    return res


@app.get("/conversations")
def conversations(user: User = Depends(current_user), db: Session = Depends(get_db)):
    rows = db.query(Conversation).filter_by(user_id=user.id).order_by(Conversation.id.desc()).limit(100).all()
    return [{"id": c.id, "title": c.title} for c in rows]


@app.get("/conversations/{cid}")
def conversation(cid: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    c = db.get(Conversation, cid)
    if not c or c.user_id != user.id:
        raise HTTPException(404, "Conversation not found.")
    msgs = db.query(Message).filter_by(conv_id=cid).order_by(Message.id).all()
    return [{"role": m.role, "content": m.content, "model": m.model} for m in msgs]


@app.delete("/conversations/{cid}")
def delete_conversation(cid: int, user: User = Depends(current_user), db: Session = Depends(get_db)):
    c = db.get(Conversation, cid)
    if not c or c.user_id != user.id:
        raise HTTPException(404, "Conversation not found.")
    db.query(Message).filter_by(conv_id=cid).delete()
    db.delete(c)
    db.commit()
    return {"deleted": cid}
