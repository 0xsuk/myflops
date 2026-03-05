from __future__ import annotations

import inspect
from dataclasses import dataclass
from typing import Any

import numpy as np

from . import ir
from . import lang as tl
from .lowering.llvm import lower_to_llvm
from .runtime.cuda import CudaRuntime


def _is_array_like(value: Any) -> bool:
    return hasattr(value, "__array_interface__")


def _dtype_to_ir(value: Any) -> str:
    if _is_array_like(value):
        dt = np.asarray(value).dtype
        if dt == np.float32:
            return "f32"
        raise TypeError(f"unsupported array dtype: {dt}")
    if isinstance(value, int):
        return "i32"
    raise TypeError(f"unsupported kernel argument type: {type(value)!r}")


@dataclass(frozen=True)
class _Compiled:
    ptx: str
    name: str
    block_size: int
    arg_specs: tuple[ir.ArgSpec, ...]


class _Launcher:
    def __init__(self, kernel: Kernel, grid_spec: Any) -> None:
        self._kernel = kernel
        self._grid_spec = grid_spec

    def __call__(self, *args: Any, **meta: Any) -> None:
        compiled = self._kernel._compile(args, meta)
        grid = self._grid_spec(meta) if callable(self._grid_spec) else self._grid_spec
        if isinstance(grid, int):
            grid = (grid,)
        if not isinstance(grid, tuple) or len(grid) == 0:
            raise TypeError("grid must be an int, tuple, or callable returning a tuple")
        CudaRuntime().launch(
            ptx=compiled.ptx,
            kernel_name=compiled.name,
            host_args=args,
            arg_specs=compiled.arg_specs,
            grid=grid,
            block=(compiled.block_size, 1, 1),
        )


class Kernel:
    def __init__(self, fn: Any) -> None:
        self.fn = fn
        self.sig = inspect.signature(fn)
        self.name = fn.__name__
        self._cache: dict[tuple[Any, ...], _Compiled] = {}

    def __getitem__(self, grid_spec: Any) -> _Launcher:
        return _Launcher(self, grid_spec)

    def _compile(self, args: tuple[Any, ...], meta: dict[str, Any]) -> _Compiled:
        block_size = int(meta.get("BLOCK_SIZE", 256))
        dtype_sig = tuple(_dtype_to_ir(a) for a in args)
        cache_key = (dtype_sig, block_size)
        if cache_key in self._cache:
            return self._cache[cache_key]

        kernel_ir = self._trace(args, meta)
        llvm_ir = lower_to_llvm(kernel_ir)
        ptx = CudaRuntime().compile_llvm_to_ptx(llvm_ir)
        compiled = _Compiled(
            ptx=ptx,
            name=self.name,
            block_size=block_size,
            arg_specs=kernel_ir.args,
        )
        self._cache[cache_key] = compiled
        return compiled

    def _trace(self, args: tuple[Any, ...], meta: dict[str, Any]) -> ir.KernelIR:
        params = list(self.sig.parameters.values())
        if len(args) > len(params):
            raise TypeError("too many positional arguments")

        tl._ACTIVE_TRACE = tl._TraceState()
        try:
            call_positional: list[Any] = []
            arg_specs: list[ir.ArgSpec] = []

            runtime_arg_index = 0
            for i, param in enumerate(params):
                if param.name in meta:
                    continue
                if runtime_arg_index >= len(args):
                    raise TypeError(
                        f"missing runtime argument for parameter '{param.name}'"
                    )
                value = args[runtime_arg_index]
                runtime_arg_index += 1

                dtype = _dtype_to_ir(value)
                kind = "ptr" if _is_array_like(value) else "scalar"
                spec = ir.ArgSpec(name=param.name, index=i, kind=kind, dtype=dtype)  # type: ignore[arg-type]
                arg_specs.append(spec)

                if kind == "ptr":
                    symbol = tl.Pointer(ir.PtrExpr(spec, ir.Const(0)))
                else:
                    symbol = tl.Value(ir.ArgRef(spec))
                call_positional.append(symbol)

            self.fn(*call_positional, **meta)

            stores = tuple(tl._ACTIVE_TRACE.stores)
            if not stores:
                raise ValueError("kernel did not emit any tl.store operations")
            return ir.KernelIR(
                name=self.name,
                args=tuple(arg_specs),
                stores=stores,
                block_size=int(meta.get("BLOCK_SIZE", 256)),
            )
        finally:
            tl._ACTIVE_TRACE = None


def kernel(fn: Any) -> Kernel:
    return Kernel(fn)
