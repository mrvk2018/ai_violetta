#!/usr/bin/env python3
"""Merge Violetta sprites: keep original face/eyes, take lowered arm from Leonardo."""

from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter


PROJECT_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_ORIGINAL = PROJECT_ROOT / "assets" / "violetta_bodyfull.png"
DEFAULT_LEONARDO = PROJECT_ROOT / "assets" / "images" / "violetta_leonardo.png"
DEFAULT_OUTPUT = PROJECT_ROOT / "assets" / "images" / "violetta_hand_down.png"

CANVAS_SIZE = (375, 666)

# Face landmarks from Violetta3DRenderEngine (normalized, origin top-left).
LEFT_EYE_NORM = (0.3972, 0.2634)
RIGHT_EYE_NORM = (0.4736, 0.2686)
MOUTH_NORM = (0.4839, 0.3099)


def _character_mask(rgba: np.ndarray, background: str) -> np.ndarray:
    alpha = rgba[:, :, 3]
    rgb = rgba[:, :, :3]

    if background == "white":
        bg = (rgb[:, :, 0] > 240) & (rgb[:, :, 1] > 240) & (rgb[:, :, 2] > 240)
        return (alpha > 20) & ~bg

    bg = (rgb[:, :, 0] < 20) & (rgb[:, :, 1] < 20) & (rgb[:, :, 2] < 20)
    return (alpha > 20) & ~bg


def _bbox(mask: np.ndarray) -> tuple[int, int, int, int]:
    ys, xs = np.where(mask)
    if len(xs) == 0:
        raise RuntimeError("Character bounding box is empty.")
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def _rgba_array(image: Image.Image) -> np.ndarray:
    return np.array(image.convert("RGBA"), dtype=np.uint8)


def _to_image(array: np.ndarray) -> Image.Image:
    return Image.fromarray(array.astype(np.uint8), mode="RGBA")


def _is_background_pixel(red: int, green: int, blue: int, alpha: int) -> bool:
    return alpha > 20 and red > 240 and green > 240 and blue > 240


def _remove_white_background(image: Image.Image) -> Image.Image:
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    visited = np.zeros((height, width), dtype=bool)
    stack: list[tuple[int, int]] = []

    for x in range(width):
        stack.append((x, 0))
        stack.append((x, height - 1))
    for y in range(height):
        stack.append((0, y))
        stack.append((width - 1, y))

    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= width or y >= height or visited[y, x]:
            continue

        red, green, blue, alpha = pixels[x, y]
        if not _is_background_pixel(red, green, blue, alpha):
            continue

        visited[y, x] = True
        pixels[x, y] = (0, 0, 0, 0)
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))

    return rgba


def _align_leonardo_to_original(
    original: Image.Image,
    leonardo: Image.Image,
) -> Image.Image:
    original_rgba = _rgba_array(original)
    leonardo_rgba = _rgba_array(leonardo)

    orig_mask = _character_mask(original_rgba, "black")
    leo_mask = _character_mask(leonardo_rgba, "white")

    ox0, oy0, ox1, oy1 = _bbox(orig_mask)
    lx0, ly0, lx1, ly1 = _bbox(leo_mask)

    orig_w = ox1 - ox0 + 1
    orig_h = oy1 - oy0 + 1
    leo_w = lx1 - lx0 + 1
    leo_h = ly1 - ly0 + 1

    scale = orig_h / leo_h
    target_w = max(1, int(round(leo_w * scale)))
    target_h = max(1, int(round(leo_h * scale)))

    leo_crop = _remove_white_background(
        leonardo.crop((lx0, ly0, lx1 + 1, ly1 + 1))
    )
    leo_scaled = leo_crop.resize((target_w, target_h), Image.Resampling.LANCZOS)

    aligned = Image.new("RGBA", CANVAS_SIZE, (0, 0, 0, 0))
    paste_x = ox0 + (orig_w - target_w) // 2
    paste_y = oy1 - target_h + 1
    aligned.paste(leo_scaled, (paste_x, paste_y), leo_scaled.split()[3])
    return aligned


def _norm_to_px(norm: tuple[float, float], size: tuple[int, int]) -> tuple[int, int]:
    return int(round(norm[0] * size[0])), int(round(norm[1] * size[1]))


def _is_face_pixel(x: int, y: int, size: tuple[int, int]) -> bool:
    width, height = size
    left_eye = _norm_to_px(LEFT_EYE_NORM, size)
    right_eye = _norm_to_px(RIGHT_EYE_NORM, size)
    mouth = _norm_to_px(MOUTH_NORM, size)
    face_center_x = (left_eye[0] + right_eye[0] + mouth[0]) // 3
    face_center_y = (left_eye[1] + right_eye[1] + mouth[1]) // 3
    dx = (x - face_center_x) / 58.0
    dy = (y - face_center_y) / 72.0
    return (dx * dx) + (dy * dy) <= 1.0


def _composite_lowered_arm(
    original_rgba: np.ndarray,
    leonardo_rgba: np.ndarray,
) -> np.ndarray:
    result = original_rgba.copy()
    height, width = original_rgba.shape[:2]
    torso_x = 150
    size = (width, height)

    horizontal_shift = 14

    for y in range(228, height):
        for x in range(82, 196):
            source_x = min(max(x - horizontal_shift, 0), width - 1)

            if leonardo_rgba[y, source_x, 3] > 20:
                result[y, x] = leonardo_rgba[y, source_x]
                continue

            if y > 300 or original_rgba[y, x, 3] < 20:
                continue

            donor_y = 360
            while donor_y < 540 and leonardo_rgba[donor_y, source_x, 3] < 20:
                donor_y += 1

            if leonardo_rgba[donor_y, source_x, 3] > 20:
                result[y, x] = leonardo_rgba[donor_y, source_x]

    for y in range(198, 228):
        for x in range(82, 156):
            if _is_face_pixel(x, y, size):
                continue
            if original_rgba[y, x, 3] < 20:
                continue

            source_x = min(max(x - horizontal_shift, 0), width - 1)
            donor_y = 300
            while donor_y < 540 and leonardo_rgba[donor_y, source_x, 3] < 20:
                donor_y += 1

            if leonardo_rgba[donor_y, source_x, 3] > 20:
                result[y, x] = leonardo_rgba[donor_y, source_x]
                continue

            torso_pixel = leonardo_rgba[310, torso_x]
            if torso_pixel[3] > 20:
                result[y, x] = torso_pixel

    return result


def _restore_face(original_rgba: np.ndarray, merged_rgba: np.ndarray) -> np.ndarray:
    result = merged_rgba.copy()
    height, width = original_rgba.shape[:2]
    face_mask = Image.new("L", (width, height), 0)
    draw = ImageDraw.Draw(face_mask)

    left_eye = _norm_to_px(LEFT_EYE_NORM, (width, height))
    right_eye = _norm_to_px(RIGHT_EYE_NORM, (width, height))
    mouth = _norm_to_px(MOUTH_NORM, (width, height))
    face_center_x = (left_eye[0] + right_eye[0] + mouth[0]) // 3
    face_center_y = (left_eye[1] + right_eye[1] + mouth[1]) // 3
    draw.ellipse(
        (
            face_center_x - 58,
            face_center_y - 68,
            face_center_x + 58,
            face_center_y + 74,
        ),
        fill=255,
    )

    face_alpha = (
        np.array(face_mask.filter(ImageFilter.GaussianBlur(radius=1.0)), dtype=np.float32)
        / 255.0
    )
    face_alpha[:228, :] = 0.0
    face_alpha[:, :108] = 0.0
    face_alpha = face_alpha[:, :, None]

    result = (
        merged_rgba.astype(np.float32) * (1.0 - face_alpha)
        + original_rgba.astype(np.float32) * face_alpha
    )
    return np.clip(result, 0, 255).astype(np.uint8)


def merge_sprites(
    original_path: Path,
    leonardo_path: Path,
    output_path: Path,
) -> Path:
    original = Image.open(original_path).convert("RGBA")
    leonardo = Image.open(leonardo_path).convert("RGBA")

    if original.size != CANVAS_SIZE:
        original = original.resize(CANVAS_SIZE, Image.Resampling.LANCZOS)

    aligned_leonardo = _align_leonardo_to_original(original, leonardo)
    original_rgba = _rgba_array(original)
    leonardo_rgba = _rgba_array(aligned_leonardo)
    merged = _composite_lowered_arm(original_rgba, leonardo_rgba)
    merged = _restore_face(original_rgba, merged)

    # Preserve original black background outside the character silhouette.
    character = _character_mask(original_rgba, "black")[:, :, None]
    merged[:, :, 3] = np.where(character[:, :, 0], 255, 0)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    _to_image(merged).save(output_path)
    return output_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Merge Violetta sprite layers.")
    parser.add_argument("--original", type=Path, default=DEFAULT_ORIGINAL)
    parser.add_argument("--leonardo", type=Path, default=DEFAULT_LEONARDO)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    output = merge_sprites(args.original, args.leonardo, args.output)
    print(f"Merged sprite saved to: {output}")


if __name__ == "__main__":
    main()
