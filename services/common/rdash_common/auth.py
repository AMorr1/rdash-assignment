from datetime import UTC, datetime, timedelta

import jwt
from fastapi import Header, HTTPException, status


def verify_bearer_token(
    auth_header: str | None,
    *,
    secret: str,
    audience: str,
    issuer: str,
) -> dict:
    if not auth_header or not auth_header.startswith("Bearer "):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="missing bearer token")
    token = auth_header.removeprefix("Bearer ").strip()
    try:
        return jwt.decode(token, secret, algorithms=["HS256"], audience=audience, issuer=issuer)
    except jwt.PyJWTError as exc:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="invalid token") from exc


def mint_service_token(secret: str, issuer: str, audience: str, ttl_seconds: int = 300) -> str:
    now = datetime.now(UTC)
    payload = {
        "iss": issuer,
        "aud": audience,
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=ttl_seconds)).timestamp()),
        "scope": "registry.read",
    }
    return jwt.encode(payload, secret, algorithm="HS256")


async def require_user_token(
    authorization: str | None = Header(default=None),
    x_forwarded_user: str | None = Header(default=None),
) -> dict:
    if x_forwarded_user:
        return {"sub": x_forwarded_user, "source": "edge"}
    raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="edge auth required")

