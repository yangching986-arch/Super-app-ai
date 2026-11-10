"""Hybrid AI Super App API. Phase 6-9 backend."""
import os, time
from typing import Optional
import httpx
from cryptography.fernet import Fernet, InvalidToken
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from sqlalchemy import func
from db import Base, engine, get_db, User, Conversation, Message, UserAPIKey
from auth import router as auth_router, current_user, admin_user

app = FastAPI(title="Hybrid AI Super App", version="2.0.0")
# Set CORS_ORIGINS to comma-separated trusted origins in production.
origins = [x.strip() for x in os.getenv("CORS_ORIGINS", "*").split(",")]
app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=False,
                   allow_methods=["GET","POST","DELETE","PUT"], allow_headers=["Authorization","Content-Type"])
Base.metadata.create_all(engine)
app.include_router(auth_router)

# OpenAI-compatible providers. Provider/model IDs may change; review vendor docs.
MODELS = {
 "gemini":{"name":"Gemini Flash","base":"https://generativelanguage.googleapis.com/v1beta/openai","model":"gemini-2.5-flash","env":"GEMINI_API_KEY","free":True},
 "groq":{"name":"Llama (Groq)","base":"https://api.groq.com/openai/v1","model":"llama-3.3-70b-versatile","env":"GROQ_API_KEY","free":True},
 "cerebras":{"name":"Cerebras","base":"https://api.cerebras.ai/v1","model":"llama-3.3-70b","env":"CEREBRAS_API_KEY","free":True},
 "deepseek":{"name":"DeepSeek via OpenRouter","base":"https://openrouter.ai/api/v1","model":"deepseek/deepseek-chat-v3-0324:free","env":"OPENROUTER_API_KEY","free":True},
 "mistral":{"name":"Mistral","base":"https://api.mistral.ai/v1","model":"mistral-small-latest","env":"MISTRAL_API_KEY","free":True},
 "grok":{"name":"Grok","base":"https://api.x.ai/v1","model":"grok-3-mini","env":None,"free":False},
 "claude":{"name":"Claude","base":"https://api.anthropic.com/v1","model":"claude-3-5-haiku-latest","env":None,"free":False,"anthropic":True},
}
_cooldown = {}
def encryptor():
    key = os.getenv("KEY_ENCRYPTION_SECRET")
    if not key:
        raise HTTPException(503, "Server key encryption is not configured.")
    try: return Fernet(key.encode())
    except Exception: raise HTTPException(500, "KEY_ENCRYPTION_SECRET must be a valid Fernet key.")

class ChatIn(BaseModel):
    message: str = Field(min_length=1, max_length=30000)
    model: Optional[str] = None
    free_only: bool = True
    conversation_id: Optional[int] = None
    coding_agent: bool = False

class KeyIn(BaseModel):
    provider: str
    api_key: str = Field(min_length=8, max_length=500)

def route(message: str):
    m=message.lower()
    if any(w in m for w in ("code","bug","python","function","কোড","ডিবাগ")):
        return ["mistral","groq","cerebras","gemini","deepseek","grok","claude"]
    if len(message)>3000: return ["gemini","deepseek","mistral","groq","cerebras","claude","grok"]
    return ["groq","cerebras","gemini","mistral","deepseek","grok","claude"]

def stored_key(db, user_id, provider):
    row=db.query(UserAPIKey).filter_by(user_id=user_id,provider=provider).first()
    if not row: return None
    try: return encryptor().decrypt(row.encrypted_key.encode()).decode()
    except (InvalidToken, ValueError): raise HTTPException(500,"Stored API key cannot be decrypted; check encryption secret.")

def get_key(mid, db, user):
    cfg=MODELS[mid]
    custom=stored_key(db,user.id,mid) if not cfg["free"] else None
    return custom or (os.getenv(cfg.get("env")) if cfg.get("env") else None)

async def provider_call(mid,key,message):
    cfg=MODELS[mid]
    async with httpx.AsyncClient(timeout=75) as c:
        if cfg.get("anthropic"):
            r=await c.post(cfg["base"]+"/messages",
              headers={"x-api-key":key,"anthropic-version":"2023-06-01","content-type":"application/json"},
              json={"model":cfg["model"],"max_tokens":4096,"messages":[{"role":"user","content":message}]})
            r.raise_for_status()
            return "".join(x.get("text","") for x in r.json().get("content",[]) if x.get("type")=="text")
        r=await c.post(cfg["base"]+"/chat/completions",
          headers={"Authorization":f"Bearer {key}"},
          json={"model":cfg["model"],"messages":[{"role":"user","content":message}]})
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"]

async def generate(mid,key,message):
    try: return await provider_call(mid,key,message)
    except httpx.HTTPStatusError as e:
        if e.response.status_code in (429,500,502,503,504): _cooldown[mid]=time.time()+45
        raise

@app.get("/health")
def health(): return {"status":"ok"}

@app.get("/models")
def models(user: User=Depends(current_user), db: Session=Depends(get_db)):
    out=[]
    for mid,cfg in MODELS.items():
        own=bool(db.query(UserAPIKey).filter_by(user_id=user.id,provider=mid).first()) if not cfg["free"] else False
        env=bool(os.getenv(cfg["env"])) if cfg.get("env") else False
        status="free" if cfg["free"] else ("configured" if own or env else "needs_key")
        if _cooldown.get(mid,0)>time.time(): status="limited"
        out.append({"id":mid,"name":cfg["name"],"status":status})
    return out

@app.put("/keys")
def save_key(b:KeyIn,user:User=Depends(current_user),db:Session=Depends(get_db)):
    if b.provider not in ("claude","grok"): raise HTTPException(400,"Only Claude and Grok personal keys are accepted here.")
    token=encryptor().encrypt(b.api_key.strip().encode()).decode()
    row=db.query(UserAPIKey).filter_by(user_id=user.id,provider=b.provider).first()
    if row: row.encrypted_key=token
    else: db.add(UserAPIKey(user_id=user.id,provider=b.provider,encrypted_key=token))
    db.commit()
    return {"saved":True,"provider":b.provider,"masked":"••••"+b.api_key[-4:]}

@app.get("/keys")
def list_keys(user:User=Depends(current_user),db:Session=Depends(get_db)):
    rows=db.query(UserAPIKey).filter_by(user_id=user.id).all()
    return [{"provider":r.provider,"configured":True,"updated":r.updated.isoformat() if r.updated else None} for r in rows]

@app.delete("/keys/{provider}")
def delete_key(provider:str,user:User=Depends(current_user),db:Session=Depends(get_db)):
    if provider not in ("claude","grok"): raise HTTPException(400,"Unsupported provider.")
    db.query(UserAPIKey).filter_by(user_id=user.id,provider=provider).delete()
    db.commit()
    return {"deleted":provider}

async def run_chat(body,user,db):
    order=([body.model] if body.model in MODELS else []) + [m for m in route(body.message) if m != body.model]
    if body.coding_agent:
        order=([body.model] if body.model in MODELS else []) + [m for m in ["mistral","groq","cerebras","gemini","deepseek","claude","grok"] if m != body.model]
        prompt=("You are a careful coding agent. First understand the task, then provide: "
                "1) brief plan, 2) complete changed files or precise patch, 3) commands/tests, "
                "4) risks and rollback. Never claim you executed code or tests. Do not request or reveal secrets. "
                "Do not perform destructive actions. User request:\n"+body.message)
    else: prompt=body.message
    tried=[]
    for mid in order:
        cfg=MODELS[mid]
        if body.free_only and not cfg["free"]: continue
        if _cooldown.get(mid,0)>time.time(): continue
        key=get_key(mid,db,user)
        if not key: continue
        try:
            answer=await generate(mid,key,prompt)
            return {"answer":answer,"model":cfg["name"],"fallback":bool(tried),"tried":tried}
        except Exception:
            tried.append(cfg["name"])
    return {"answer":None,"error":"Configured models are unavailable or their quota is exhausted. Check keys and try again.","tried":tried}

@app.post("/chat")
async def chat(body:ChatIn,user:User=Depends(current_user),db:Session=Depends(get_db)):
    conv=db.get(Conversation,body.conversation_id) if body.conversation_id else None
    if conv and conv.user_id!=user.id: raise HTTPException(404,"Conversation not found.")
    if not conv:
        conv=Conversation(user_id=user.id,title=body.message[:40]); db.add(conv); db.flush()
    db.add(Message(conv_id=conv.id,role="user",content=body.message))
    res=await run_chat(body,user,db)
    if res.get("answer"): db.add(Message(conv_id=conv.id,role="assistant",content=res["answer"],model=res["model"]))
    db.commit(); res["conversation_id"]=conv.id
    return res

@app.get("/conversations")
def conversations(user:User=Depends(current_user),db:Session=Depends(get_db)):
    rows=db.query(Conversation).filter_by(user_id=user.id).order_by(Conversation.id.desc()).limit(100).all()
    return [{"id":c.id,"title":c.title} for c in rows]

@app.get("/conversations/{cid}")
def conversation(cid:int,user:User=Depends(current_user),db:Session=Depends(get_db)):
    c=db.get(Conversation,cid)
    if not c or c.user_id!=user.id: raise HTTPException(404,"Conversation not found.")
    return [{"role":m.role,"content":m.content,"model":m.model} for m in db.query(Message).filter_by(conv_id=cid).order_by(Message.id).all()]

@app.delete("/conversations/{cid}")
def delete_conversation(cid:int,user:User=Depends(current_user),db:Session=Depends(get_db)):
    c=db.get(Conversation,cid)
    if not c or c.user_id!=user.id: raise HTTPException(404,"Conversation not found.")
    db.query(Message).filter_by(conv_id=cid).delete(); db.delete(c); db.commit()
    return {"deleted":cid}

# Phase 8: admin-only endpoints
@app.get("/admin/stats")
def admin_stats(_:User=Depends(admin_user),db:Session=Depends(get_db)):
    return {"users":db.query(func.count(User.id)).scalar(),
            "conversations":db.query(func.count(Conversation.id)).scalar(),
            "messages":db.query(func.count(Message.id)).scalar()}

@app.get("/admin/users")
def admin_users(_:User=Depends(admin_user),db:Session=Depends(get_db)):
    return [{"id":u.id,"name":u.name,"email":u.email,"role":u.role,"created":u.created.isoformat() if u.created else None}
            for u in db.query(User).order_by(User.id.desc()).limit(500).all()]

@app.put("/admin/users/{uid}/role")
def set_role(uid:int,role:str,user:User=Depends(admin_user),db:Session=Depends(get_db)):
    if role not in ("user","admin"): raise HTTPException(400,"Role must be user or admin.")
    target=db.get(User,uid)
    if not target: raise HTTPException(404,"User not found.")
    if target.id==user.id and role!="admin": raise HTTPException(400,"You cannot remove your own admin role.")
    target.role=role; db.commit()
    return {"id":uid,"role":role}

@app.delete("/admin/users/{uid}")
def remove_user(uid:int,user:User=Depends(admin_user),db:Session=Depends(get_db)):
    if uid==user.id: raise HTTPException(400,"You cannot delete your own account.")
    target=db.get(User,uid)
    if not target: raise HTTPException(404,"User not found.")
    conv_ids=[c.id for c in db.query(Conversation).filter_by(user_id=uid).all()]
    if conv_ids: db.query(Message).filter(Message.conv_id.in_(conv_ids)).delete(synchronize_session=False)
    db.query(Conversation).filter_by(user_id=uid).delete()
    db.query(UserAPIKey).filter_by(user_id=uid).delete()
    db.delete(target); db.commit()
    return {"deleted":uid}
