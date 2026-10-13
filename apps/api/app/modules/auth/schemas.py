from pydantic import BaseModel


class LoginRequest(BaseModel):
    method: str = "phone"
    phone: str | None = None
    code: str | None = None
    oauth_code: str | None = None


class RefreshRequest(BaseModel):
    refresh_token: str
