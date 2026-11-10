import os, datetime as dt
from sqlalchemy import create_engine, Column, Integer, String, Text, DateTime, ForeignKey
from sqlalchemy.orm import sessionmaker, declarative_base

# Production (PostgreSQL): postgresql+psycopg2://USER:PASS@HOST:5432/DBNAME
# If DATABASE_URL is not set, a local SQLite file is used so you can test quickly.
DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./app.db")
engine = create_engine(DATABASE_URL, pool_pre_ping=True)
SessionLocal = sessionmaker(bind=engine, autoflush=False)
Base = declarative_base()
now = lambda: dt.datetime.utcnow()


class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True)
    email = Column(String(255), unique=True, index=True, nullable=False)
    name = Column(String(100), nullable=False)
    pw_hash = Column(String(300), nullable=False)
    role = Column(String(20), default="user")  # "user" | "admin" (Phase 8)
    created = Column(DateTime, default=now)


class Conversation(Base):
    __tablename__ = "conversations"
    id = Column(Integer, primary_key=True)
    user_id = Column(Integer, ForeignKey("users.id"), index=True, nullable=False)
    title = Column(String(120), default="New chat")
    created = Column(DateTime, default=now)


class Message(Base):
    __tablename__ = "messages"
    id = Column(Integer, primary_key=True)
    conv_id = Column(Integer, ForeignKey("conversations.id"), index=True, nullable=False)
    role = Column(String(10), nullable=False)  # user | assistant
    content = Column(Text, nullable=False)
    model = Column(String(60))
    created = Column(DateTime, default=now)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
