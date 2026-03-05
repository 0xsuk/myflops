# tritonish DSL (PoC)

Triton-like DSL PoC with:

- Python frontend (`@kernel`, `tl.program_id`, `tl.arange`, `tl.load`, `tl.store`)
- custom IR nodes
- LLVM IR lowering for NVPTX
- PTX compilation via `llc`
- CUDA Driver API launch via `ctypes`

## Example

Run:

```bash
PYTHONPATH=dsl python dsl/examples/vector_add.py
```

## Current constraints

- NVIDIA CUDA only
- pointer args: `float32` only
- scalar args: `int32` only
- `program_id(axis=0)` only
- masked loads are supported when the load mask equals the corresponding store mask
