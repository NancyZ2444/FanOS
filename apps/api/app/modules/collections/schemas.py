from pydantic import BaseModel, Field


class QuantityUpdate(BaseModel):
    quantity: int = Field(ge=0, le=999)


class AlbumCreate(BaseModel):
    name: str = Field(min_length=1, max_length=50)
    is_public: bool = False


class AlbumCardsUpdate(BaseModel):
    card_ids: list[str] = Field(max_length=500)
    revision: int | None = Field(default=None, ge=1)
