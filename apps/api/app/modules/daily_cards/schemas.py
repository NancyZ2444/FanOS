from pydantic import BaseModel, Field


class DrawRequest(BaseModel):
    draw_request_id: str = Field(min_length=1, max_length=100)
