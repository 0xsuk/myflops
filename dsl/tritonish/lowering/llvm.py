from __future__ import annotations

from dataclasses import dataclass

from .. import ir


def _infer_type(expr: ir.Expr) -> str:
    if isinstance(expr, ir.Const):
        return "f32" if isinstance(expr.value, float) else "i32"
    if isinstance(expr, ir.ProgramId | ir.LaneId):
        return "i32"
    if isinstance(expr, ir.ArgRef):
        return expr.arg.dtype
    if isinstance(expr, ir.Load):
        return "f32"
    if isinstance(expr, ir.Cmp):
        return "i1"
    if isinstance(expr, ir.Binary):
        lt = _infer_type(expr.lhs)
        rt = _infer_type(expr.rhs)
        if "f32" in (lt, rt):
            return "f32"
        return "i32"
    raise TypeError(f"cannot infer type for expression: {type(expr)!r}")


@dataclass
class _Builder:
    lines: list[str]
    temp_index: int = 0

    def tmp(self) -> str:
        name = f"%t{self.temp_index}"
        self.temp_index += 1
        return name

    def emit(self, line: str) -> None:
        self.lines.append(line)


def _collect_loads(expr: ir.Expr, out: list[ir.Load]) -> None:
    if isinstance(expr, ir.Load):
        out.append(expr)
        return
    if isinstance(expr, ir.Binary | ir.Cmp):
        _collect_loads(expr.lhs, out)
        _collect_loads(expr.rhs, out)


def _cast_to_f32(builder: _Builder, value: str, ty: str) -> str:
    if ty == "f32":
        return value
    casted = builder.tmp()
    builder.emit(f"  {casted} = sitofp i32 {value} to float")
    return casted


def _lower_expr(
    expr: ir.Expr, builder: _Builder, arg_map: dict[str, str]
) -> tuple[str, str]:
    if isinstance(expr, ir.Const):
        if isinstance(expr.value, float):
            return f"{float(expr.value):.8e}", "f32"
        return str(int(expr.value)), "i32"

    if isinstance(expr, ir.ProgramId):
        if expr.axis != 0:
            raise NotImplementedError("only program_id(axis=0) is supported")
        v = builder.tmp()
        builder.emit(f"  {v} = call i32 @llvm.nvvm.read.ptx.sreg.ctaid.x()")
        return v, "i32"

    if isinstance(expr, ir.LaneId):
        v = builder.tmp()
        builder.emit(f"  {v} = call i32 @llvm.nvvm.read.ptx.sreg.tid.x()")
        return v, "i32"

    if isinstance(expr, ir.ArgRef):
        return arg_map[expr.arg.name], expr.arg.dtype

    if isinstance(expr, ir.Binary):
        lv, lt = _lower_expr(expr.lhs, builder, arg_map)
        rv, rt = _lower_expr(expr.rhs, builder, arg_map)
        out_ty = "f32" if "f32" in (lt, rt) else "i32"
        if out_ty == "f32":
            lv = _cast_to_f32(builder, lv, lt)
            rv = _cast_to_f32(builder, rv, rt)
            out = builder.tmp()
            op_map = {
                "add": "fadd",
                "sub": "fsub",
                "mul": "fmul",
                "div": "fdiv",
            }
            builder.emit(f"  {out} = {op_map[expr.op]} float {lv}, {rv}")
            return out, "f32"

        out = builder.tmp()
        op_map = {
            "add": "add",
            "sub": "sub",
            "mul": "mul",
            "div": "sdiv",
        }
        builder.emit(f"  {out} = {op_map[expr.op]} i32 {lv}, {rv}")
        return out, "i32"

    if isinstance(expr, ir.Cmp):
        lv, lt = _lower_expr(expr.lhs, builder, arg_map)
        rv, rt = _lower_expr(expr.rhs, builder, arg_map)
        out = builder.tmp()
        if "f32" in (lt, rt):
            lv = _cast_to_f32(builder, lv, lt)
            rv = _cast_to_f32(builder, rv, rt)
            op_map = {
                "lt": "olt",
                "le": "ole",
                "gt": "ogt",
                "ge": "oge",
                "eq": "oeq",
                "ne": "one",
            }
            builder.emit(f"  {out} = fcmp {op_map[expr.op]} float {lv}, {rv}")
            return out, "i1"
        op_map = {
            "lt": "slt",
            "le": "sle",
            "gt": "sgt",
            "ge": "sge",
            "eq": "eq",
            "ne": "ne",
        }
        builder.emit(f"  {out} = icmp {op_map[expr.op]} i32 {lv}, {rv}")
        return out, "i1"

    if isinstance(expr, ir.Load):
        base = arg_map[expr.ptr.base.name]
        idx, idx_ty = _lower_expr(expr.ptr.offset, builder, arg_map)
        if idx_ty != "i32":
            raise TypeError("pointer offset must be i32")
        p = builder.tmp()
        builder.emit(
            f"  {p} = getelementptr inbounds float, float addrspace(1)* {base}, i32 {idx}"
        )
        v = builder.tmp()
        builder.emit(f"  {v} = load float, float addrspace(1)* {p}, align 4")
        return v, "f32"

    raise TypeError(f"unsupported expression node: {type(expr)!r}")


def lower_to_llvm(kernel: ir.KernelIR) -> str:
    ptr_args = [a for a in kernel.args if a.kind == "ptr"]
    scalar_args = [a for a in kernel.args if a.kind == "scalar"]

    for a in ptr_args:
        if a.dtype != "f32":
            raise TypeError("only f32 pointer args are supported")
    for a in scalar_args:
        if a.dtype != "i32":
            raise TypeError("only i32 scalar args are supported")

    params = []
    for a in kernel.args:
        if a.kind == "ptr":
            params.append(f"float addrspace(1)* %{a.name}")
        else:
            params.append(f"i32 %{a.name}")

    lines: list[str] = [
        'target triple = "nvptx64-nvidia-cuda"',
        "",
        "declare i32 @llvm.nvvm.read.ptx.sreg.ctaid.x() nounwind readnone",
        "declare i32 @llvm.nvvm.read.ptx.sreg.tid.x() nounwind readnone",
        "",
        f"define void @{kernel.name}({', '.join(params)}) {{",
        "entry:",
    ]

    builder = _Builder(lines=lines)
    arg_map = {a.name: f"%{a.name}" for a in kernel.args}

    for i, stmt in enumerate(kernel.stores):
        load_nodes: list[ir.Load] = []
        _collect_loads(stmt.value, load_nodes)
        for ld in load_nodes:
            if ld.mask is not None and ld.mask != stmt.mask:
                raise NotImplementedError(
                    "masked load is only supported when it uses the same mask as tl.store"
                )

        if stmt.mask is not None:
            m, mty = _lower_expr(stmt.mask, builder, arg_map)
            if mty != "i1":
                raise TypeError("store mask must lower to i1")
            builder.emit(f"  br i1 {m}, label %store_then_{i}, label %store_end_{i}")
            builder.emit(f"store_then_{i}:")

        value, vty = _lower_expr(stmt.value, builder, arg_map)
        if vty != "f32":
            value = _cast_to_f32(builder, value, vty)

        base = arg_map[stmt.ptr.base.name]
        idx, ity = _lower_expr(stmt.ptr.offset, builder, arg_map)
        if ity != "i32":
            raise TypeError("store pointer offset must be i32")

        p = builder.tmp()
        builder.emit(
            f"  {p} = getelementptr inbounds float, float addrspace(1)* {base}, i32 {idx}"
        )
        builder.emit(f"  store float {value}, float addrspace(1)* {p}, align 4")

        if stmt.mask is not None:
            builder.emit(f"  br label %store_end_{i}")
            builder.emit(f"store_end_{i}:")

    builder.emit("  ret void")
    builder.emit("}")
    builder.emit("")
    builder.emit("!nvvm.annotations = !{!0}")
    builder.emit(
        f'!0 = !{{void ({", ".join("float addrspace(1)*" if a.kind == "ptr" else "i32" for a in kernel.args)})* @{kernel.name}, !"kernel", i32 1}}'
    )
    return "\n".join(builder.lines) + "\n"
