from __future__ import annotations

import ctypes
import ctypes.util
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import numpy as np

from .. import ir


class CudaError(RuntimeError):
    pass


@dataclass
class _LoadedKernel:
    context: ctypes.c_void_p
    module: ctypes.c_void_p
    function: ctypes.c_void_p


class CudaRuntime:
    def __init__(self) -> None:
        lib_name = ctypes.util.find_library("cuda")
        if lib_name is None:
            raise RuntimeError("CUDA driver library not found (libcuda)")
        self.cuda = ctypes.CDLL(lib_name)
        self._declare_signatures()

    def _declare_signatures(self) -> None:
        self.cuda.cuInit.argtypes = [ctypes.c_uint]
        self.cuda.cuInit.restype = ctypes.c_int

        self.cuda.cuDeviceGet.argtypes = [ctypes.POINTER(ctypes.c_int), ctypes.c_int]
        self.cuda.cuDeviceGet.restype = ctypes.c_int

        self.cuda.cuCtxCreate_v2.argtypes = [
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_uint,
            ctypes.c_int,
        ]
        self.cuda.cuCtxCreate_v2.restype = ctypes.c_int

        self.cuda.cuCtxDestroy_v2.argtypes = [ctypes.c_void_p]
        self.cuda.cuCtxDestroy_v2.restype = ctypes.c_int

        self.cuda.cuModuleLoadData.argtypes = [
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_void_p,
        ]
        self.cuda.cuModuleLoadData.restype = ctypes.c_int

        self.cuda.cuModuleUnload.argtypes = [ctypes.c_void_p]
        self.cuda.cuModuleUnload.restype = ctypes.c_int

        self.cuda.cuModuleGetFunction.argtypes = [
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.c_void_p,
            ctypes.c_char_p,
        ]
        self.cuda.cuModuleGetFunction.restype = ctypes.c_int

        self.cuda.cuMemAlloc_v2.argtypes = [
            ctypes.POINTER(ctypes.c_uint64),
            ctypes.c_size_t,
        ]
        self.cuda.cuMemAlloc_v2.restype = ctypes.c_int

        self.cuda.cuMemFree_v2.argtypes = [ctypes.c_uint64]
        self.cuda.cuMemFree_v2.restype = ctypes.c_int

        self.cuda.cuMemcpyHtoD_v2.argtypes = [
            ctypes.c_uint64,
            ctypes.c_void_p,
            ctypes.c_size_t,
        ]
        self.cuda.cuMemcpyHtoD_v2.restype = ctypes.c_int

        self.cuda.cuMemcpyDtoH_v2.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint64,
            ctypes.c_size_t,
        ]
        self.cuda.cuMemcpyDtoH_v2.restype = ctypes.c_int

        self.cuda.cuLaunchKernel.argtypes = [
            ctypes.c_void_p,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_uint,
            ctypes.c_void_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.POINTER(ctypes.c_void_p),
        ]
        self.cuda.cuLaunchKernel.restype = ctypes.c_int

        self.cuda.cuCtxSynchronize.argtypes = []
        self.cuda.cuCtxSynchronize.restype = ctypes.c_int

    def _check(self, code: int, message: str) -> None:
        if code != 0:
            raise CudaError(f"{message} (CUDA error code={code})")

    def compile_llvm_to_ptx(self, llvm_ir: str) -> str:
        llc = Path("/usr/bin/llc")
        if not llc.exists():
            maybe = shutil_which("llc")
            if maybe is None:
                raise RuntimeError("llc is required to compile LLVM IR to PTX")
            llc = Path(maybe)

        with tempfile.TemporaryDirectory(prefix="tritonish_") as td:
            ll_path = Path(td) / "kernel.ll"
            ptx_path = Path(td) / "kernel.ptx"
            ll_path.write_text(llvm_ir, encoding="ascii")
            cmd = [
                str(llc),
                "-O3",
                "-march=nvptx64",
                "-mcpu=sm_70",
                str(ll_path),
                "-o",
                str(ptx_path),
            ]
            proc = subprocess.run(cmd, capture_output=True, text=True)
            if proc.returncode != 0:
                raise RuntimeError(f"llc failed:\n{proc.stderr}")
            return ptx_path.read_text(encoding="ascii")

    def _load_kernel(self, ptx: str, kernel_name: str) -> _LoadedKernel:
        self._check(self.cuda.cuInit(0), "cuInit failed")

        dev = ctypes.c_int()
        self._check(self.cuda.cuDeviceGet(ctypes.byref(dev), 0), "cuDeviceGet failed")

        ctx = ctypes.c_void_p()
        self._check(
            self.cuda.cuCtxCreate_v2(ctypes.byref(ctx), 0, dev), "cuCtxCreate failed"
        )

        module = ctypes.c_void_p()
        ptx_buf = ctypes.create_string_buffer(ptx.encode("ascii"))
        self._check(
            self.cuda.cuModuleLoadData(
                ctypes.byref(module), ctypes.cast(ptx_buf, ctypes.c_void_p)
            ),
            "cuModuleLoadData failed",
        )

        func = ctypes.c_void_p()
        self._check(
            self.cuda.cuModuleGetFunction(
                ctypes.byref(func), module, kernel_name.encode("ascii")
            ),
            "cuModuleGetFunction failed",
        )
        return _LoadedKernel(context=ctx, module=module, function=func)

    def launch(
        self,
        *,
        ptx: str,
        kernel_name: str,
        host_args: tuple[Any, ...],
        arg_specs: tuple[ir.ArgSpec, ...],
        grid: tuple[int, ...],
        block: tuple[int, int, int],
    ) -> None:
        loaded = self._load_kernel(ptx=ptx, kernel_name=kernel_name)
        try:
            device_ptrs: list[int] = []
            arg_cells: list[Any] = []
            kernel_params: list[ctypes.c_void_p] = []
            host_arrays: list[np.ndarray] = []

            for spec, value in zip(arg_specs, host_args, strict=True):
                if spec.kind == "ptr":
                    arr = np.asarray(value, dtype=np.float32, order="C")
                    host_arrays.append(arr)
                    nbytes = arr.nbytes
                    dptr = ctypes.c_uint64()
                    self._check(
                        self.cuda.cuMemAlloc_v2(ctypes.byref(dptr), nbytes),
                        "cuMemAlloc failed",
                    )
                    device_ptrs.append(dptr.value)
                    self._check(
                        self.cuda.cuMemcpyHtoD_v2(
                            dptr.value,
                            arr.ctypes.data_as(ctypes.c_void_p),
                            nbytes,
                        ),
                        "cuMemcpyHtoD failed",
                    )
                    ptr_cell = ctypes.c_uint64(dptr.value)
                    arg_cells.append(ptr_cell)
                    kernel_params.append(
                        ctypes.cast(ctypes.byref(ptr_cell), ctypes.c_void_p)
                    )
                else:
                    scalar = ctypes.c_int(int(value))
                    arg_cells.append(scalar)
                    kernel_params.append(
                        ctypes.cast(ctypes.byref(scalar), ctypes.c_void_p)
                    )

            kparams_arr = (ctypes.c_void_p * len(kernel_params))(*kernel_params)

            gx = int(grid[0])
            gy = int(grid[1]) if len(grid) > 1 else 1
            gz = int(grid[2]) if len(grid) > 2 else 1
            bx, by, bz = map(int, block)

            self._check(
                self.cuda.cuLaunchKernel(
                    loaded.function,
                    gx,
                    gy,
                    gz,
                    bx,
                    by,
                    bz,
                    0,
                    None,
                    kparams_arr,
                    None,
                ),
                "cuLaunchKernel failed",
            )
            self._check(self.cuda.cuCtxSynchronize(), "cuCtxSynchronize failed")

            ptr_iter = iter(device_ptrs)
            for spec, value in zip(arg_specs, host_args, strict=True):
                if spec.kind != "ptr":
                    continue
                arr = np.asarray(value, dtype=np.float32, order="C")
                dptr = next(ptr_iter)
                self._check(
                    self.cuda.cuMemcpyDtoH_v2(
                        arr.ctypes.data_as(ctypes.c_void_p), dptr, arr.nbytes
                    ),
                    "cuMemcpyDtoH failed",
                )
                if isinstance(value, np.ndarray):
                    value[...] = arr

            for dptr in device_ptrs:
                self._check(self.cuda.cuMemFree_v2(dptr), "cuMemFree failed")
        finally:
            self.cuda.cuModuleUnload(loaded.module)
            self.cuda.cuCtxDestroy_v2(loaded.context)


def shutil_which(program: str) -> str | None:
    import shutil

    return shutil.which(program)
