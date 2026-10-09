from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class GitCollectionError(Exception):
    detail: str

    def __str__(self) -> str:
        return self.detail


@dataclass(frozen=True, slots=True)
class ConfigurationError(Exception):
    detail: str

    def __str__(self) -> str:
        return self.detail


@dataclass(frozen=True, slots=True)
class ApiRequestError(Exception):
    detail: str

    def __str__(self) -> str:
        return self.detail


@dataclass(frozen=True, slots=True)
class OutputValidationError(Exception):
    detail: str

    def __str__(self) -> str:
        return self.detail
