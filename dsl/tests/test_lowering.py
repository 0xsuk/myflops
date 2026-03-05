from __future__ import annotations

import numpy as np

from tritonish import kernel
from tritonish import lang as tl
from tritonish.lowering import lower_to_llvm


@kernel
def vec_add(x_ptr, y_ptr, out_ptr, n, BLOCK_SIZE: int):
    pid = tl.program_id(0)
    offsets = pid * BLOCK_SIZE + tl.arange(0, BLOCK_SIZE)
    mask = offsets < n
    x = tl.load(x_ptr + offsets, mask=mask, other=0.0)
    y = tl.load(y_ptr + offsets, mask=mask, other=0.0)
    tl.store(out_ptr + offsets, x + y, mask=mask)


def test_lower_to_llvm_contains_kernel_annotations() -> None:
    x = np.zeros(16, dtype=np.float32)
    y = np.zeros(16, dtype=np.float32)
    out = np.zeros(16, dtype=np.float32)
    ir = vec_add._trace((x, y, out, 16), {"BLOCK_SIZE": 16})
    llvm = lower_to_llvm(ir)
    assert 'target triple = "nvptx64-nvidia-cuda"' in llvm
    assert "define void @vec_add" in llvm
    assert "!nvvm.annotations" in llvm
