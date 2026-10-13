from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any


class SocialProvider(ABC):
    name: str

    @abstractmethod
    def fetch(
        self, cursor: str | None = None
    ) -> tuple[list[dict[str, Any]], str | None]: ...
