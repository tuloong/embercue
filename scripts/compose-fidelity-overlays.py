#!/usr/bin/env python3
"""Normalize one captured rail and compare it with a caller-supplied video crop.

This tool never changes source images and deliberately scores geometry only;
compressed translucent video is not a trustworthy color oracle.
"""
import argparse
import json
import sys
from pathlib import Path

from PIL import Image, ImageChops


def fail(message):
    print(message, file=sys.stderr)
    raise SystemExit(1)


def parse_quad(value):
    try:
        values = tuple(int(part) for part in value.split(","))
    except ValueError:
        fail("reference rail must be x,y,width,height")
    if len(values) != 4 or values[2] <= 0 or values[3] <= 0:
        fail("reference rail must be x,y,width,height with positive size")
    return values


def parse_pair(value):
    try:
        values = tuple(int(part) for part in value.split(","))
    except ValueError:
        fail("pair must be x,y")
    if len(values) != 2:
        fail("pair must be x,y")
    return values


def opaque_content_box(image):
    """Return the alpha>=128 bounding box, excluding transparent corners."""
    alpha = image.getchannel("A")
    mask = alpha.point(lambda value: 255 if value >= 128 else 0)
    box = mask.getbbox()
    if box is None:
        fail("app capture has no alpha>=128 content")
    return box


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--reference", required=True)
    parser.add_argument("--app", required=True)
    parser.add_argument("--app-metrics", required=True)
    parser.add_argument("--reference-rail", required=True)
    parser.add_argument("--canvas", required=True)
    parser.add_argument("--right-margin", type=int, required=True)
    parser.add_argument("--vertical-center", type=int, required=True)
    parser.add_argument("--tolerance", type=int, default=8)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    reference_path, app_path, metrics_path, output = map(Path, (args.reference, args.app, args.app_metrics, args.output))
    if not all(path.is_file() for path in (reference_path, app_path, metrics_path)):
        fail("reference, app image, and app metrics must exist")
    if not output.is_absolute():
        fail("output must be absolute")
    canvas_w, canvas_h = parse_pair(args.canvas)
    rail_x, rail_y, rail_w, rail_h = parse_quad(args.reference_rail)
    metrics = json.loads(metrics_path.read_text())
    required = ("x", "y", "width", "height", "screenWidth", "screenHeight")
    if any(key not in metrics for key in required):
        fail("app metrics is missing x/y/width/height")
    app_x, app_y = float(metrics["x"]), float(metrics["y"])
    app_w, app_h = float(metrics["width"]), float(metrics["height"])
    screen_w, screen_h = float(metrics["screenWidth"]), float(metrics["screenHeight"])
    if screen_w <= 0 or screen_h <= 0:
        fail("app metrics has invalid screen dimensions")
    expected_x = canvas_w - args.right_margin - rail_w
    expected_y = args.vertical_center - rail_h / 2
    errors = {"rightOffset": abs((screen_w - (app_x + app_w)) - args.right_margin), "verticalCenter": abs((app_y + app_h / 2) - screen_h / 2), "width": abs(app_w - rail_w), "height": abs(app_h - rail_h)}
    if max(errors.values()) > args.tolerance:
        fail("rail geometry exceeds tolerance: " + json.dumps(errors, sort_keys=True))

    reference = Image.open(reference_path).convert("RGBA")
    app = Image.open(app_path).convert("RGBA")
    if rail_x < 0 or rail_y < 0 or rail_x + rail_w > reference.width or rail_y + rail_h > reference.height:
        fail("reference rail crop is outside reference image")
    reference_crop = reference.crop((rail_x, rail_y, rail_x + rail_w, rail_y + rail_h))
    content_box = opaque_content_box(app)
    content = app.crop(content_box)
    content_w, content_h = content.size
    if content_w <= 0 or content_h <= 0:
        fail("app capture content has invalid dimensions")
    scale_x, scale_y = content_w / app_w, content_h / app_h
    ratio = content_w / content_h
    expected_ratio = app_w / app_h
    if abs(scale_x - scale_y) > 0.01 or abs(ratio - expected_ratio) > 0.01:
        fail("app capture backing scale/ratio does not match window metrics: " + json.dumps({"content": [content_w, content_h], "metrics": [app_w, app_h], "scale": [scale_x, scale_y]}))
    app_canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    # Normalize only the rail's opaque content. Window shadows and transparent
    # padding are intentionally absent from the visual comparison.
    normalized = content.resize((rail_w, rail_h), Image.Resampling.LANCZOS)
    app_canvas.alpha_composite(normalized, (expected_x, int(expected_y)))
    reference_canvas = Image.new("RGBA", (canvas_w, canvas_h), (0, 0, 0, 0))
    reference_canvas.alpha_composite(reference_crop, (rail_x, rail_y))
    overlay = Image.blend(reference_canvas, app_canvas, 0.5)
    difference = ImageChops.difference(reference_canvas, app_canvas)
    side = Image.new("RGBA", (canvas_w * 2, canvas_h), (0, 0, 0, 0))
    side.alpha_composite(reference_canvas, (0, 0)); side.alpha_composite(app_canvas, (canvas_w, 0))
    output.mkdir(parents=True, exist_ok=False)
    app_canvas.save(output / "app-canvas.png")
    reference_crop.save(output / "reference-crop.png")
    side.save(output / "side-by-side.png")
    overlay.save(output / "overlay-50.png")
    difference.save(output / "difference.png")
    (output / "metrics.json").write_text(json.dumps({"expected": {"x": expected_x, "y": expected_y, "width": rail_w, "height": rail_h}, "observed": {"x": app_x, "y": app_y, "width": app_w, "height": app_h}, "captureContent": {"box": content_box, "width": content_w, "height": content_h, "backingScale": scale_x}, "errors": errors}, indent=2) + "\n")


if __name__ == "__main__":
    main()
