import os, hmac, hashlib, secrets, datetime as dt
import jwt
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPBearer
from pydantic import BaseModel
from sqlalchemy.orm import Session
from db import get_db, User

SECRET = os.getenv("JWT_SECRET", "change-me-in-production")
router = APIRouter(prefix="/auth", tags=["auth"])
bearer = HTTPBearer()


def hash_pw(pw: str, salt: str | None = None) -> str:
    salt = salt or secrets.token_hex(16)
    h = hashlib.pbkdf2_hmac("sha256", pw.encode(), bytes.fromhex(salt), 200_000).hex()
    return f"{salt}${h}"


def check_pw(pw: str, stored: str) -> bool:
    salt, h = stored.split("$")
    return hmac.compare_digest(hash_pw(pw, salt).split("$")[1], h)


def make_token(uid: int) -> str:
    exp = dt.datetime.utcnow() + dt.timedelta(days=30)
    return jwt.encode({"sub": str(uid), "exp": exp}, SECRET, "HS256")


def current_user(cred=Depends(bearer), db: Session = Depends(get_db)) -> User:
    try:
        uid = int(jwt.decode(cred.credentials, SECRET, ["HS256"])["sub"])
    except Exception:
        raise HTTPException(401, "Session expired. Please log in again.")
    user = db.get(User, uid)
    if not user:
        raise HTTPException(401, "Account not found.")
    return user


class RegisterIn(BaseModel):
    name: str
    email: str
    password: str


class LoginIn(BaseModel):
    email: str
    password: str


@router.post("/register")
def register(b: RegisterIn, db: Session = Depends(get_db)):
    email = b.email.strip().lower()
    if "@" not in email or len(b.password) < 8 or not b.name.strip():
        raise HTTPException(400, "Enter a name, a valid email and a password of 8+ characters.")
    if db.query(User).filter_by(email=email).first():
        raise HTTPException(400, "This email is already registered.")
    u = User(name=b.name.strip(), email=email, pw_hash=hash_pw(b.password))
    db.add(u)
    db.commit()
    return {"token": make_token(u.id), "name": u.name}


@router.post("/login")
def login(b: LoginIn, db: Session = Depends(get_db)):
    u = db.query(User).filter_by(email=b.email.strip().lower()).first()
    if not u or not check_pw(b.password, u.pw_hash):
        raise HTTPException(401, "Wrong email or password.")
    return {"token": make_token(u.id), "name": u.name}
