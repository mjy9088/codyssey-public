from sqlalchemy.orm import DeclarativeBase, MappedAsDataclass


class Base(MappedAsDataclass, DeclarativeBase):
    """Base for mutable persisted records managed by SQLAlchemy."""
