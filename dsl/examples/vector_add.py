from __future__ import annotations

import numpy as np

from tritonish import kernel
from tritonish import lang as tl


@kernel
def vec_add(x_ptr, y_ptr, out_ptr, n, BLOCK_SIZE: int):
    block = int(BLOCK_SIZE)
    pid = tl.program_id(0)
    offsets = pid * block + tl.arange(0, block)
    mask = offsets < n
    x = tl.load(x_ptr + offsets, mask=mask, other=0.0)
    y = tl.load(y_ptr + offsets, mask=mask, other=0.0)
    tl.store(out_ptr + offsets, x + y, mask=mask)


def main() -> None:
    n = 1024
    x = np.random.rand(n).astype(np.float32)
    y = np.random.rand(n).astype(np.float32)
    out = np.zeros_like(x)
    block_size = 256

    vec_add[(tl.cdiv(n, block_size),)](x, y, out, n, BLOCK_SIZE=block_size)

    ref = x + y
    err = float(np.max(np.abs(out - ref)))
    print(f"max error: {err:.6e}")


if __name__ == "__main__":
    main()
