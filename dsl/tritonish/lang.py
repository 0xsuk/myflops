from __future__ import annotations

from dataclasses import dataclass

from . import ir


class constexpr:
    pass


def _coerce_expr(value: ValueLike) -> ir.Expr:
    if isinstance(value, Value):
        return value.expr
    if isinstance(value, Pointer):
        return value.expr
    if isinstance(value, bool):
        return ir.Const(1 if value else 0)
    if isinstance(value, int | float):
        return ir.Const(value)
    raise TypeError(f"unsupported value type: {type(value)!r}")


ValueLike = "Value | Pointer | int | float | bool"


@dataclass(frozen=True)
class Value:
    expr: ir.Expr

    def _bin(self, op: str, other: ValueLike) -> Value:
        return Value(ir.Binary(op, self.expr, _coerce_expr(other)))

    def __add__(self, other: ValueLike) -> Value:
        return self._bin("add", other)

    def __radd__(self, other: ValueLike) -> Value:
        return Value(ir.Binary("add", _coerce_expr(other), self.expr))

    def __sub__(self, other: ValueLike) -> Value:
        return self._bin("sub", other)

    def __rsub__(self, other: ValueLike) -> Value:
        return Value(ir.Binary("sub", _coerce_expr(other), self.expr))

    def __mul__(self, other: ValueLike) -> Value:
        return self._bin("mul", other)

    def __rmul__(self, other: ValueLike) -> Value:
        return Value(ir.Binary("mul", _coerce_expr(other), self.expr))

    def __truediv__(self, other: ValueLike) -> Value:
        return self._bin("div", other)

    def __rtruediv__(self, other: ValueLike) -> Value:
        return Value(ir.Binary("div", _coerce_expr(other), self.expr))

    def _cmp(self, op: str, other: ValueLike) -> Value:
        return Value(ir.Cmp(op, self.expr, _coerce_expr(other)))

    def __lt__(self, other: ValueLike) -> Value:
        return self._cmp("lt", other)

    def __le__(self, other: ValueLike) -> Value:
        return self._cmp("le", other)

    def __gt__(self, other: ValueLike) -> Value:
        return self._cmp("gt", other)

    def __ge__(self, other: ValueLike) -> Value:
        return self._cmp("ge", other)

    def __eq__(self, other: object) -> Value:  # type: ignore[override]
        return Value(ir.Cmp("eq", self.expr, _coerce_expr(other)))

    def __ne__(self, other: object) -> Value:  # type: ignore[override]
        return Value(ir.Cmp("ne", self.expr, _coerce_expr(other)))


@dataclass(frozen=True)
class Pointer:
    expr: ir.PtrExpr

    def __add__(self, other: ValueLike) -> Pointer:
        return Pointer(
            ir.PtrExpr(
                self.expr.base, ir.Binary("add", self.expr.offset, _coerce_expr(other))
            )
        )

    def __radd__(self, other: ValueLike) -> Pointer:
        return self.__add__(other)


class _TraceState:
    def __init__(self) -> None:
        self.stores: list[ir.Store] = []


_ACTIVE_TRACE: _TraceState | None = None


def _require_trace() -> _TraceState:
    if _ACTIVE_TRACE is None:
        raise RuntimeError("tl.* can only be used while tracing a @kernel")
    return _ACTIVE_TRACE


def program_id(axis: int) -> Value:
    if axis != 0:
        raise NotImplementedError("only axis=0 is supported in this PoC")
    return Value(ir.ProgramId(axis))


def arange(start: int, end: int) -> Value:
    lane = ir.LaneId()
    if start == 0:
        return Value(lane)
    return Value(ir.Binary("add", lane, ir.Const(start)))


def load(ptr: Pointer, mask: Value | None = None, other: float = 0.0) -> Value:
    if not isinstance(ptr, Pointer):
        raise TypeError("tl.load expects a pointer expression")
    return Value(ir.Load(ptr.expr, mask.expr if mask is not None else None, other))


def store(ptr: Pointer, value: ValueLike, mask: Value | None = None) -> None:
    if not isinstance(ptr, Pointer):
        raise TypeError("tl.store expects a pointer expression")
    trace = _require_trace()
    trace.stores.append(
        ir.Store(
            ptr=ptr.expr, value=_coerce_expr(value), mask=mask.expr if mask else None
        )
    )


def cdiv(x: int, y: int) -> int:
    return (x + y - 1) // y


__all__ = [
    "constexpr",
    "Value",
    "Pointer",
    "program_id",
    "arange",
    "load",
    "store",
    "cdiv",
]
