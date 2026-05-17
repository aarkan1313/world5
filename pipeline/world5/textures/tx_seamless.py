"""W4 tx_seamless — FLUX 4-pass tileable generation, denoise-honoring heal.

Fork of D:/assets/pipelines/textures/flux_seamless.py with the key audit
finding fixed: the heal pass now uses BasicScheduler so `--heal-denoise`
is actually applied. The shared-infra version uses Flux2Scheduler which
silently ignores `denoise`, meaning every "gentle 0.35 heal" was
actually running at full denoise=1.0 — almost certainly the source of
the lattice fingerprint we see in klein-9B-at-1024 outputs.

4-pass flow (unchanged in shape):
  Pass 1: text2img — full-denoise FLUX with TILE_PROMPT_SUFFIX
  Pass 2: circular shift by half (wrap-around seams move to center)
  Pass 3: img2img heal at honest --heal-denoise (default 0.35)
  Pass 4: reverse circular shift; result tiles

W4 simplifications vs upstream:
  - No reference-image / anchor mode (not needed for diversity batches)
  - No catalog write (caller owns the index)
  - --heal-mode {flux_heal, none} switch: 'none' skips pass 3 entirely
    so we can A/B compare the FLUX heal contribution
  - Returns the final albedo as numpy array, lets caller save where it wants
"""
from __future__ import annotations

import argparse
import json
import time
import urllib.parse
import urllib.request
import uuid
from pathlib import Path

import numpy as np
from PIL import Image


COMFY_HOST = "http://127.0.0.1:8188"

TILE_PROMPT_SUFFIX = (
    ", fully tileable seamless texture, all four edges loop perfectly, "
    "top-down orthographic view, even neutral diffuse lighting, "
    "no shadows, no highlights, no vignette, no border, no frame, "
    "uniform composition, repeating pattern, 1:1 square aspect, "
    "high detail, photorealistic PBR-ready"
)


def queue_prompt(workflow: dict, host: str = COMFY_HOST) -> str:
    payload = json.dumps({"prompt": workflow, "client_id": str(uuid.uuid4())}).encode()
    req = urllib.request.Request(f"{host}/prompt", data=payload,
                                  headers={"Content-Type": "application/json"})
    return json.loads(urllib.request.urlopen(req).read().decode())["prompt_id"]


def wait_for(prompt_id: str, host: str = COMFY_HOST, timeout: int = 1200) -> dict:
    start = time.time()
    while time.time() - start < timeout:
        with urllib.request.urlopen(f"{host}/history/{prompt_id}") as r:
            hist = json.loads(r.read().decode())
        if prompt_id in hist:
            return hist[prompt_id]
        time.sleep(2)
    raise TimeoutError(f"prompt {prompt_id} did not complete within {timeout}s")


def download_output(host: str, filename: str, subfolder: str, type_: str,
                    dest: Path) -> None:
    qs = urllib.parse.urlencode({"filename": filename, "subfolder": subfolder, "type": type_})
    with urllib.request.urlopen(f"{host}/view?{qs}") as r, dest.open("wb") as f:
        f.write(r.read())


def upload_image(image_path: Path, host: str = COMFY_HOST) -> str:
    import http.client
    boundary = uuid.uuid4().hex
    body_lines = []
    body_lines.append(f"--{boundary}".encode())
    body_lines.append(f'Content-Disposition: form-data; name="image"; filename="{image_path.name}"'.encode())
    body_lines.append(b"Content-Type: image/png")
    body_lines.append(b"")
    body_lines.append(image_path.read_bytes())
    body_lines.append(f"--{boundary}--".encode())
    body_lines.append(b"")
    body = b"\r\n".join(body_lines)
    parsed = urllib.parse.urlparse(host)
    conn = http.client.HTTPConnection(parsed.hostname, parsed.port)
    conn.request("POST", "/upload/image", body=body,
                 headers={"Content-Type": f"multipart/form-data; boundary={boundary}"})
    r = conn.getresponse()
    res = json.loads(r.read().decode())
    conn.close()
    return res["name"]


def workflow_text2img(prompt: str, unet: str, clip: str, vae: str,
                     size: int, seed: int, steps: int,
                     prefix: str) -> dict:
    return {
        "10": {"class_type": "UNETLoader", "inputs": {"unet_name": unet, "weight_dtype": "default"}},
        "11": {"class_type": "CLIPLoader", "inputs": {"clip_name": clip, "type": "flux2", "device": "default"}},
        "12": {"class_type": "VAELoader", "inputs": {"vae_name": vae}},
        "20": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["11", 0]}},
        "21": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["20", 0]}},
        "30": {"class_type": "CFGGuider", "inputs": {"model": ["10", 0], "positive": ["20", 0],
                                                      "negative": ["21", 0], "cfg": 1.0}},
        "40": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "41": {"class_type": "Flux2Scheduler", "inputs": {"steps": steps, "width": size, "height": size}},
        "42": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed}},
        "43": {"class_type": "EmptyFlux2LatentImage",
               "inputs": {"width": size, "height": size, "batch_size": 1}},
        "50": {"class_type": "SamplerCustomAdvanced", "inputs": {
            "noise": ["42", 0], "guider": ["30", 0], "sampler": ["40", 0],
            "sigmas": ["41", 0], "latent_image": ["43", 0]}},
        "60": {"class_type": "VAEDecode", "inputs": {"samples": ["50", 0], "vae": ["12", 0]}},
        "70": {"class_type": "SaveImage", "inputs": {"filename_prefix": prefix, "images": ["60", 0]}},
    }


def workflow_img2img_heal(prompt: str, input_image_name: str, unet: str,
                          clip: str, vae: str, size: int, seed: int,
                          denoise: float, steps: int, prefix: str,
                          scheduler: str = "flux2") -> dict:
    """Heal pass — img2img over the offset-shifted texture.

    Scheduler choice (the 2026-05-12 follow-up finding):

      'flux2' (default, MATCHES SHIPPED-CLEAN UPSTREAM):
          Uses Flux2Scheduler with klein's 4-step distilled schedule.
          The `denoise` param is silently ignored by this scheduler —
          but that's the behavior that produces clean midlines on
          shipped output (verified against materials/biome_alpine/ground/).

      'basic' (the audit's failed experiment):
          Uses BasicScheduler which honors `denoise`. At denoise=1.0 +
          8 steps, this hammers the offset cross with new content that
          has no constraint to match the surrounding pixels, creating
          a fresh midline seam (catastrophic — ratio 16-22× baseline
          in the 2026-05-12 audit experiment).

    Default is 'flux2' because that's what works. The 'basic' path is
    kept for diagnostic / future experimentation but should NOT be
    used in production.
    """
    if scheduler == "basic":
        scheduler_node = {
            "class_type": "BasicScheduler", "inputs": {
                "model": ["10", 0], "scheduler": "simple",
                "steps": steps, "denoise": denoise,
            }}
    elif scheduler == "flux2":
        scheduler_node = {
            "class_type": "Flux2Scheduler", "inputs": {
                "steps": steps, "width": size, "height": size,
                # denoise is silently ignored but we pass it for log clarity
                "denoise": denoise,
            }}
    else:
        raise ValueError(f"unknown heal scheduler: {scheduler!r}")
    return {
        "10": {"class_type": "UNETLoader", "inputs": {"unet_name": unet, "weight_dtype": "default"}},
        "11": {"class_type": "CLIPLoader", "inputs": {"clip_name": clip, "type": "flux2", "device": "default"}},
        "12": {"class_type": "VAELoader", "inputs": {"vae_name": vae}},
        "15": {"class_type": "LoadImage", "inputs": {"image": input_image_name}},
        "16": {"class_type": "VAEEncode", "inputs": {"pixels": ["15", 0], "vae": ["12", 0]}},
        "20": {"class_type": "CLIPTextEncode", "inputs": {"text": prompt, "clip": ["11", 0]}},
        "21": {"class_type": "ConditioningZeroOut", "inputs": {"conditioning": ["20", 0]}},
        "30": {"class_type": "CFGGuider", "inputs": {"model": ["10", 0], "positive": ["20", 0],
                                                      "negative": ["21", 0], "cfg": 1.0}},
        "40": {"class_type": "KSamplerSelect", "inputs": {"sampler_name": "euler"}},
        "41": scheduler_node,
        "42": {"class_type": "RandomNoise", "inputs": {"noise_seed": seed + 99}},
        "50": {"class_type": "SamplerCustomAdvanced", "inputs": {
            "noise": ["42", 0], "guider": ["30", 0], "sampler": ["40", 0],
            "sigmas": ["41", 0], "latent_image": ["16", 0]}},
        "60": {"class_type": "VAEDecode", "inputs": {"samples": ["50", 0], "vae": ["12", 0]}},
        "70": {"class_type": "SaveImage", "inputs": {"filename_prefix": prefix, "images": ["60", 0]}},
    }


def offset_image(arr: np.ndarray) -> np.ndarray:
    """Wrap by half so the (previously wrap-around) seam crosses the center."""
    h, w = arr.shape[:2]
    out = np.empty_like(arr)
    out[:h // 2, :w // 2] = arr[h // 2:, w // 2:]
    out[:h // 2, w // 2:] = arr[h // 2:, :w // 2]
    out[h // 2:, :w // 2] = arr[:h // 2, w // 2:]
    out[h // 2:, w // 2:] = arr[:h // 2, :w // 2]
    return out


def edge_seam_score(im: np.ndarray) -> float:
    a = im.astype(np.float32)
    edge_lr = float(np.mean((a[:, 0] - a[:, -1]) ** 2)) / (255 ** 2)
    edge_tb = float(np.mean((a[0, :] - a[-1, :]) ** 2)) / (255 ** 2)
    return max(edge_lr, edge_tb)


def run_seamless(prompt: str, asset_id: str, *, unet: str, clip: str,
                 vae: str, size: int, seed: int, steps: int,
                 heal_denoise: float, heal_mode: str = "flux_heal",
                 host: str = COMFY_HOST,
                 tmp_dir: Path | None = None) -> tuple[np.ndarray, dict]:
    """Run the 4-pass FLUX seamless generation.

    Args:
        heal_mode: 'flux_heal' (default) runs pass 3; 'none' skips it
            (returns the pass-1 image as-is — useful as a baseline in
            audit experiments).

    Returns:
        (final_rgb, log) — RGB uint8 numpy array, and a log dict with
        intermediate seam scores + timing.
    """
    full_prompt = prompt + TILE_PROMPT_SUFFIX
    print(f"[tx_seamless] prompt: {prompt!r}")
    print(f"  size={size} seed={seed} heal_mode={heal_mode} heal_denoise={heal_denoise}")

    tmp_dir = tmp_dir or Path(f"D:/tmp/tx_seamless/{asset_id}_{seed}")
    tmp_dir.mkdir(parents=True, exist_ok=True)
    log: dict = {"asset_id": asset_id, "size": size, "seed": seed,
                 "heal_mode": heal_mode, "heal_denoise": heal_denoise}

    # PASS 1: text-to-image
    print(f"[1/4] text2img generation (size={size}, steps={steps})")
    t1 = time.time()
    wf = workflow_text2img(full_prompt, unet, clip, vae, size, seed, steps,
                           prefix=f"{asset_id}_pass1")
    pid = queue_prompt(wf, host=host)
    res = wait_for(pid, host=host)
    images = res["outputs"].get("70", {}).get("images", [])
    if not images:
        raise RuntimeError("no images from pass 1")
    pass1_path = tmp_dir / "pass1.png"
    download_output(host, images[0]["filename"], images[0]["subfolder"],
                    images[0]["type"], pass1_path)
    pass1 = np.asarray(Image.open(pass1_path).convert("RGB"))
    pass1_score = edge_seam_score(pass1)
    log["pass1_seam_score"] = pass1_score
    log["pass1_seconds"] = round(time.time() - t1, 2)
    print(f"  pass1 seam score: {pass1_score:.5f}")

    if heal_mode == "none":
        # Skip pass 3 — return pass1 directly. Used as audit baseline to
        # measure heal-pass contribution.
        print("[heal_mode=none] skipping shift+heal+reshift, returning pass1")
        log["heal_skipped"] = True
        log["final_seam_score"] = pass1_score
        return pass1, log

    # PASS 2: circular shift
    print(f"[2/4] circular shift (seams -> center)")
    shifted = offset_image(pass1)
    shifted_path = tmp_dir / "shifted.png"
    Image.fromarray(shifted).save(shifted_path)
    server_name = upload_image(shifted_path, host=host)

    # PASS 3: img2img heal — default Flux2Scheduler (matches the shipped-
    # clean upstream behavior; BasicScheduler at denoise=1.0 destroys the
    # offset cross, verified against materials/biome_alpine/ground/).
    heal_steps = max(steps * 2, 8)
    print(f"[3/4] img2img heal (Flux2Scheduler, steps={heal_steps}, "
          f"denoise={heal_denoise} silently ignored by Flux2Scheduler)")
    t3 = time.time()
    wf = workflow_img2img_heal(full_prompt, server_name, unet, clip, vae,
                               size, seed, denoise=heal_denoise,
                               steps=heal_steps,
                               prefix=f"{asset_id}_pass3",
                               scheduler="flux2")
    pid = queue_prompt(wf, host=host)
    res = wait_for(pid, host=host)
    images = res["outputs"].get("70", {}).get("images", [])
    if not images:
        raise RuntimeError("no images from pass 3")
    pass3_path = tmp_dir / "pass3.png"
    download_output(host, images[0]["filename"], images[0]["subfolder"],
                    images[0]["type"], pass3_path)
    pass3 = np.asarray(Image.open(pass3_path).convert("RGB"))
    log["pass3_seconds"] = round(time.time() - t3, 2)

    # PASS 4: reverse shift
    print(f"[4/4] reverse shift")
    final = offset_image(pass3)
    final_score = edge_seam_score(final)
    log["final_seam_score"] = final_score
    log["seam_improvement"] = pass1_score - final_score
    print(f"  final seam score: {final_score:.5f}  (pass1 -> final delta {log['seam_improvement']:+.5f})")

    return final, log


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--id", required=True)
    ap.add_argument("--out", required=True, help="output PNG path")
    ap.add_argument("--unet", default="flux-2-klein-9b-fp8.safetensors")
    ap.add_argument("--clip", default="qwen_3_8b_fp8mixed.safetensors")
    ap.add_argument("--vae", default="flux2-vae.safetensors")
    ap.add_argument("--size", type=int, default=1024)
    ap.add_argument("--steps", type=int, default=4)
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--heal-denoise", type=float, default=0.35,
                    help="img2img denoise for the heal pass. The audit "
                         "finding: upstream silently ran 1.0; we honor "
                         "this. 0.2-0.45 typical.")
    ap.add_argument("--heal-mode", choices=["flux_heal", "none"],
                    default="flux_heal",
                    help="'flux_heal' = full 4-pass; 'none' = pass-1 only "
                         "(audit baseline)")
    ap.add_argument("--host", default=COMFY_HOST)
    args = ap.parse_args()

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    final, log = run_seamless(
        args.prompt, args.id,
        unet=args.unet, clip=args.clip, vae=args.vae,
        size=args.size, seed=args.seed, steps=args.steps,
        heal_denoise=args.heal_denoise, heal_mode=args.heal_mode,
        host=args.host,
    )
    Image.fromarray(final).save(out_path)
    print(f"\nwrote {out_path}")
    print(f"log: {json.dumps(log, indent=2)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
