# tritonish DSL 使い方

このドキュメントは `dsl/tritonish` の最小PoCの使い方です。

## 前提

- NVIDIA GPU (CUDA Driverが使える環境)
- `llc` (LLVM) がインストール済み
- Python 3.10+
- `numpy`

## 実行例 (vector add)

リポジトリルートで実行:

```bash
PYTHONPATH=dsl python dsl/examples/vector_add.py
```

成功すると、`max error: ...` が表示されます。

## カーネル定義の基本

```python
from tritonish import kernel
from tritonish import lang as tl

@kernel
def vec_add(x_ptr, y_ptr, out_ptr, n, BLOCK_SIZE: int):
    pid = tl.program_id(0)
    offsets = pid * BLOCK_SIZE + tl.arange(0, BLOCK_SIZE)
    mask = offsets < n
    x = tl.load(x_ptr + offsets, mask=mask, other=0.0)
    y = tl.load(y_ptr + offsets, mask=mask, other=0.0)
    tl.store(out_ptr + offsets, x + y, mask=mask)
```

## 起動方法

```python
import numpy as np
from tritonish import lang as tl

n = 1024
x = np.random.rand(n).astype(np.float32)
y = np.random.rand(n).astype(np.float32)
out = np.zeros_like(x)

block_size = 256
vec_add[(tl.cdiv(n, block_size),)](x, y, out, n, BLOCK_SIZE=block_size)
```

`vec_add[(grid,)](...)` の `grid` はブロック数です。

## 現在の制約

- CUDA/NVIDIAのみ
- ポインタ引数は `float32` 配列のみ
- スカラ引数は `int32` のみ
- `tl.program_id(axis=0)` のみ
- マスク付き `tl.load` は対応する `tl.store` と同じmaskを使うケースのみ

## テスト

```bash
PYTHONPATH=dsl python -m pytest dsl/tests/test_lowering.py -q
```
