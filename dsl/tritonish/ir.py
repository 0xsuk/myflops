from __future__ import annotations

from dataclasses import dataclass
from typing import Literal


@dataclass(frozen=True)
class ArgSpec:
    name: str
    index: int
    kind: Literal["ptr", "scalar"]
    dtype: Literal["f32", "i32"]


class Expr:
    pass


@dataclass(frozen=True)
class Const(Expr):
    value: int | float


@dataclass(frozen=True)
class ArgRef(Expr):
    arg: ArgSpec


@dataclass(frozen=True)
class ProgramId(Expr):
    axis: int


@dataclass(frozen=True)
class LaneId(Expr):
    pass


@dataclass(frozen=True)
class Binary(Expr):
    op: Literal["add", "sub", "mul", "div"]
    lhs: Expr
    rhs: Expr


@dataclass(frozen=True)
class Cmp(Expr):
    op: Literal["lt", "le", "gt", "ge", "eq", "ne"]
    lhs: Expr
    rhs: Expr


@dataclass(frozen=True)
class PtrExpr(Expr):
    base: ArgSpec
    offset: Expr


@dataclass(frozen=True)
class Load(Expr):
    ptr: PtrExpr
    mask: Expr | None = None
    other: float = 0.0


@dataclass(frozen=True)
class Store:
    ptr: PtrExpr
    value: Expr
    mask: Expr | None = None


@dataclass(frozen=True)
class KernelIR:
    name: str
    args: tuple[ArgSpec, ...]
    stores: tuple[Store, ...]
    block_size: int
