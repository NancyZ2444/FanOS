from typing import Literal

from pydantic import BaseModel, Field, model_validator


class ScanFeedbackMetadata(BaseModel):
    scan_session_id: str = Field(min_length=1, max_length=100)
    detected_card_id: str = Field(min_length=1, max_length=100)
    group_id: str | None = Field(default=None, max_length=100)
    idol_id: str | None = Field(default=None, max_length=100)
    source: str | None = Field(default=None, max_length=100)
    source_mode: Literal["KNOWN", "UNCERTAIN", "OTHER"] | None = None
    source_entity_type: Literal["ALBUM", "EVENT", "OTHER"] | None = None
    source_entity_id: str | None = Field(default=None, max_length=100)
    source_version_id: str | None = Field(default=None, max_length=100)
    notes: str | None = Field(default=None, max_length=2000)

    @model_validator(mode="after")
    def source_reference(self):
        if bool(self.source_entity_type) != bool(self.source_entity_id):
            raise ValueError("Source entity type and ID must be supplied together")
        if self.source_version_id and not self.source_entity_id:
            raise ValueError("A version requires its source entity")
        if self.source_mode in {"UNCERTAIN", "OTHER"} and self.source_entity_id:
            raise ValueError("Unknown sources cannot claim an official entity")
        return self


class ConfirmedCard(BaseModel):
    detected_card_id: str
    card_id: str
    selected: bool = True
    add_to_wishlist: bool = False
    ensure_owned: bool = False

    @model_validator(mode="after")
    def unambiguous_ownership_action(self):
        if self.ensure_owned and self.selected:
            raise ValueError("Ensure owned cannot also increment ownership")
        return self


class ScanSelectionRequest(BaseModel):
    detected_card_ids: list[str] = Field(min_length=1, max_length=10)

    @model_validator(mode="after")
    def unique_regions(self):
        if len(set(self.detected_card_ids)) != len(self.detected_card_ids):
            raise ValueError("Each detected card can appear only once")
        return self


class ScanConfirmRequest(BaseModel):
    cards: list[ConfirmedCard] = Field(min_length=1, max_length=10)

    @model_validator(mode="after")
    def unique_regions(self):
        if len({card.detected_card_id for card in self.cards}) != len(self.cards):
            raise ValueError("Each detected card can appear only once")
        return self
