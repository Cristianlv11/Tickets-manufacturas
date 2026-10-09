import os
from datetime import datetime, timedelta

from fastapi import Depends, Request
from jose import jwt, JWTError
from passlib.context import CryptContext
from sqlalchemy.orm import Session

import models
from database import get_db

# En Railway se debe definir JWT_SECRET; la clave fija solo queda como respaldo para desarrollo local
SECRET_KEY = os.getenv("JWT_SECRET") or "super_secret_key_change_in_production"
ALGORITHM = "HS256"
DEFAULT_ADMIN_PASSWORD = "admin123"

# Cookies con Secure solo cuando corre en Railway (HTTPS)
COOKIE_SECURE = bool(os.getenv("RAILWAY_ENVIRONMENT"))

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain_password, hashed_password):
    return pwd_context.verify(plain_password, hashed_password)


def get_password_hash(password):
    return pwd_context.hash(password)


def create_access_token(data: dict, minutes: int = 24 * 60):
    to_encode = data.copy()
    expire = datetime.utcnow() + timedelta(minutes=minutes)
    to_encode.update({"exp": expire})
    return jwt.encode(to_encode, SECRET_KEY, algorithm=ALGORITHM)


def decode_token(token: str):
    try:
        return jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])
    except JWTError:
        return None


def get_current_user(request: Request, db: Session = Depends(get_db)):
    token = request.cookies.get("access_token")
    if not token:
        return None
    if token.startswith("Bearer "):
        token = token[7:]
    payload = decode_token(token)
    if not payload or payload.get("scope"):
        return None
    username = payload.get("sub")
    if username is None:
        return None
    return db.query(models.User).filter(models.User.username == username).first()


def get_current_admin(user: models.User = Depends(get_current_user)):
    if not user or user.role != models.UserRole.ADMIN:
        return None
    return user
