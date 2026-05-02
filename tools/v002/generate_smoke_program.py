#!/usr/bin/env python3
"""Generate deterministic pccx v002 runtime smoke programs.

The generated program is a handoff artifact for local validation and runtime
bring-up. It does not require model weights and does not represent hardware
execution.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path
from typing import Any


OPCODES = {
    "GEMV": 0x0,
    "GEMM": 0x1,
    "MEMCPY": 0x2,
    "MEMSET": 0x3,
    "CVO": 0x4,
}

DEST_CACHE = {
    "fmap_shape": 0,
    "weight_shape": 1,
}

CVO_FUNC = {
    "EXP": 0,
    "SQRT": 1,
    "GELU": 2,
    "SIN": 3,
    "COS": 4,
    "REDUCE_SUM": 5,
    "SCALE": 6,
    "RECIP": 7,
}


def git_value(args: list[str], default: str) -> str:
    try:
        return subprocess.check_output(
            ["git", *args],
            stderr=subprocess.DEVNULL,
            text=True,
        ).strip()
    except Exception:
        return default


def check_range(name: str, value: int, bits: int) -> int:
    if value < 0 or value >= (1 << bits):
        raise ValueError(f"{name}={value} does not fit in {bits} bits")
    return value


def encode_flags(findemax: int = 0, accm: int = 0, w_scale: int = 0) -> int:
    return (
        (check_range("findemax", findemax, 1) << 5)
        | (check_range("accm", accm, 1) << 4)
        | (check_range("w_scale", w_scale, 1) << 3)
    )


def encode_gemm_like(opcode: str, fields: dict[str, int]) -> int:
    body = (
        (check_range("dest_reg", fields["dest_reg"], 17) << 43)
        | (check_range("src_addr", fields["src_addr"], 17) << 26)
        | (check_range("flags", fields["flags"], 6) << 20)
        | (check_range("size_ptr_addr", fields["size_ptr_addr"], 6) << 14)
        | (check_range("shape_ptr_addr", fields["shape_ptr_addr"], 6) << 8)
        | (check_range("parallel_lane", fields["parallel_lane"], 5) << 3)
        | check_range("reserved", fields.get("reserved", 0), 3)
    )
    return (OPCODES[opcode] << 60) | body


def encode_memcpy(fields: dict[str, int]) -> int:
    body = (
        (check_range("from_device", fields["from_device"], 1) << 59)
        | (check_range("to_device", fields["to_device"], 1) << 58)
        | (check_range("dest_addr", fields["dest_addr"], 17) << 41)
        | (check_range("src_addr", fields["src_addr"], 17) << 24)
        | (check_range("aux_addr", fields["aux_addr"], 17) << 7)
        | (check_range("shape_ptr_addr", fields["shape_ptr_addr"], 6) << 1)
        | check_range("async", fields["async"], 1)
    )
    return (OPCODES["MEMCPY"] << 60) | body


def encode_memset(fields: dict[str, int]) -> int:
    body = (
        (check_range("dest_cache", fields["dest_cache"], 2) << 58)
        | (check_range("dest_addr", fields["dest_addr"], 6) << 52)
        | (check_range("a_value", fields["a_value"], 16) << 36)
        | (check_range("b_value", fields["b_value"], 16) << 20)
        | (check_range("c_value", fields["c_value"], 16) << 4)
        | check_range("reserved", fields.get("reserved", 0), 4)
    )
    return (OPCODES["MEMSET"] << 60) | body


def encode_cvo(fields: dict[str, int]) -> int:
    body = (
        (check_range("cvo_func", fields["cvo_func"], 4) << 56)
        | (check_range("src_addr", fields["src_addr"], 17) << 39)
        | (check_range("dst_addr", fields["dst_addr"], 17) << 22)
        | (check_range("length", fields["length"], 16) << 6)
        | (check_range("flags", fields["flags"], 5) << 1)
        | check_range("async", fields["async"], 1)
    )
    return (OPCODES["CVO"] << 60) | body


def instruction(opcode: str, label: str, fields: dict[str, int]) -> dict[str, Any]:
    if opcode in ("GEMM", "GEMV"):
        word = encode_gemm_like(opcode, fields)
    elif opcode == "MEMCPY":
        word = encode_memcpy(fields)
    elif opcode == "MEMSET":
        word = encode_memset(fields)
    elif opcode == "CVO":
        word = encode_cvo(fields)
    else:
        raise ValueError(f"unsupported opcode: {opcode}")

    return {
        "index": 0,
        "label": label,
        "opcode": opcode,
        "opcode_value": OPCODES[opcode],
        "word_hex": f"0x{word:016x}",
        "body_hex": f"0x{word & ((1 << 60) - 1):015x}",
        "fields": fields,
    }


def tiny_shape_lookup_program() -> dict[str, Any]:
    fmap_shape_ptr = 3
    gemv_shape_ptr = 9
    size_ptr_gemm = 1
    size_ptr_gemv = 2
    host_input_addr = 100
    gemm_src_addr = 300
    gemv_src_addr = 400
    gemm_result_addr = 512
    gemv_result_addr = 768
    cvo_result_addr = 896

    instructions = [
        instruction(
            "MEMSET",
            "program_fmap_shape_ptr3",
            {
                "dest_cache": DEST_CACHE["fmap_shape"],
                "dest_addr": fmap_shape_ptr,
                "a_value": 1,
                "b_value": 1,
                "c_value": 9,
                "reserved": 0,
            },
        ),
        instruction(
            "MEMSET",
            "program_fmap_shape_ptr9",
            {
                "dest_cache": DEST_CACHE["fmap_shape"],
                "dest_addr": gemv_shape_ptr,
                "a_value": 4,
                "b_value": 4,
                "c_value": 4,
                "reserved": 0,
            },
        ),
        instruction(
            "MEMCPY",
            "host_to_l2_fixture",
            {
                "from_device": 1,
                "to_device": 0,
                "dest_addr": host_input_addr,
                "src_addr": 0,
                "aux_addr": 0,
                "shape_ptr_addr": fmap_shape_ptr,
                "async": 0,
            },
        ),
        instruction(
            "GEMM",
            "l2_to_gemm_smoke",
            {
                "dest_reg": gemm_result_addr,
                "src_addr": gemm_src_addr,
                "flags": encode_flags(w_scale=1),
                "size_ptr_addr": size_ptr_gemm,
                "shape_ptr_addr": fmap_shape_ptr,
                "parallel_lane": 4,
                "reserved": 0,
            },
        ),
        instruction(
            "GEMV",
            "l2_to_gemv_smoke",
            {
                "dest_reg": gemv_result_addr,
                "src_addr": gemv_src_addr,
                "flags": encode_flags(accm=1),
                "size_ptr_addr": size_ptr_gemv,
                "shape_ptr_addr": gemv_shape_ptr,
                "parallel_lane": 4,
                "reserved": 0,
            },
        ),
        instruction(
            "CVO",
            "cvo_reduce_sum_smoke",
            {
                "cvo_func": CVO_FUNC["REDUCE_SUM"],
                "src_addr": gemv_result_addr,
                "dst_addr": cvo_result_addr,
                "length": 64,
                "flags": 0,
                "async": 0,
            },
        ),
        instruction(
            "MEMCPY",
            "l2_to_host_result",
            {
                "from_device": 0,
                "to_device": 1,
                "dest_addr": 0,
                "src_addr": cvo_result_addr,
                "aux_addr": 0,
                "shape_ptr_addr": fmap_shape_ptr,
                "async": 0,
            },
        ),
    ]

    for index, item in enumerate(instructions):
        item["index"] = index

    return {
        "schema_version": 1,
        "kind": "pccx_v002_runtime_smoke_program",
        "preset": "tiny-shape-lookup",
        "not_hardware_execution": True,
        "claim_boundary": {
            "kv260_inference_success": False,
            "gemma3n_e4b_hardware_execution": False,
            "timing_closed": False,
            "tokens_per_second_achieved": None,
            "target_tokens_per_second": 20,
        },
        "git": {
            "commit": git_value(["rev-parse", "HEAD"], "unknown"),
            "commit_short": git_value(["rev-parse", "--short=12", "HEAD"], "unknown"),
            "branch": git_value(["rev-parse", "--abbrev-ref", "HEAD"], "unknown"),
        },
        "target": {
            "board": "KV260",
            "architecture": "pccx v002",
            "isa_width_bits": 64,
            "program_boundary": "AXI-Lite command FIFO / ctrl_npu_decoder",
        },
        "shape_metadata": {
            "entries": [
                {
                    "name": "fmap_shape_ptr3",
                    "ptr": fmap_shape_ptr,
                    "x": 1,
                    "y": 1,
                    "z": 9,
                    "ceil_128b_words": 2,
                },
                {
                    "name": "fmap_shape_ptr9",
                    "ptr": gemv_shape_ptr,
                    "x": 4,
                    "y": 4,
                    "z": 4,
                    "ceil_128b_words": 8,
                },
            ]
        },
        "memory_regions": {
            "l2_input_fixture": {"base_addr": host_input_addr, "shape_ptr_addr": fmap_shape_ptr},
            "gemm_source": {"base_addr": gemm_src_addr, "shape_ptr_addr": fmap_shape_ptr},
            "gemv_source": {"base_addr": gemv_src_addr, "shape_ptr_addr": gemv_shape_ptr},
            "gemm_result": {"base_addr": gemm_result_addr, "shape_ptr_addr": fmap_shape_ptr},
            "gemv_result": {"base_addr": gemv_result_addr, "shape_ptr_addr": gemv_shape_ptr},
            "cvo_result": {"base_addr": cvo_result_addr},
        },
        "instructions": instructions,
    }


def validate_manifest(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise SystemExit(f"invalid manifest JSON: {exc}") from exc

    required_top = ["schema_version", "model", "runtime"]
    missing_top = [name for name in required_top if name not in data]
    if missing_top:
        raise SystemExit(f"manifest missing required fields: {', '.join(missing_top)}")

    required_paths = []
    model = data.get("model", {})
    runtime = data.get("runtime", {})
    for key in ("external_model_dir",):
        value = model.get(key)
        if not value:
            raise SystemExit(f"manifest model.{key} is required")
        required_paths.append((f"model.{key}", Path(value)))

    for key in ("bitstream", "runtime_bin"):
        value = runtime.get(key)
        if not value:
            raise SystemExit(f"manifest runtime.{key} is required")
        required_paths.append((f"runtime.{key}", Path(value)))

    missing_paths = [f"{name}={path}" for name, path in required_paths if not path.exists()]
    if missing_paths:
        raise SystemExit("manifest external assets not found: " + "; ".join(missing_paths))

    return {
        "manifest_path": str(path),
        "validated_external_paths": [name for name, _path in required_paths],
        "assets_copied": False,
    }


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def write_memh(path: Path, instructions: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [item["word_hex"][2:] for item in instructions]
    path.write_text("\n".join(lines) + "\n", encoding="ascii")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate deterministic pccx v002 runtime smoke programs."
    )
    parser.add_argument(
        "--preset",
        choices=["tiny-shape-lookup"],
        default="tiny-shape-lookup",
        help="program preset to generate",
    )
    parser.add_argument("--out", type=Path, help="output JSON path")
    parser.add_argument("--memh", type=Path, help="optional 64-bit instruction .memh path")
    parser.add_argument(
        "--manifest",
        type=Path,
        help="optional Gemma 3N E4B handoff manifest to validate before generation",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)

    if args.preset != "tiny-shape-lookup":
        raise SystemExit(f"unsupported preset: {args.preset}")

    payload = tiny_shape_lookup_program()
    if args.manifest:
        payload["external_manifest_validation"] = validate_manifest(args.manifest)

    if args.memh:
        write_memh(args.memh, payload["instructions"])
        payload["artifacts"] = {"memh": str(args.memh)}

    if args.out:
        write_json(args.out, payload)
    else:
        sys.stdout.write(json.dumps(payload, indent=2, sort_keys=True) + "\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
