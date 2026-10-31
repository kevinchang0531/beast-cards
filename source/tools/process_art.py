"""把 art_src/ 的 gpt-image-2 原圖處理成遊戲素材，存到 assets/images/。

- 卡圖（靈獸、能量、訓練家）：縮成 256×256 → assets/images/cards/
- 頭像：縮成 192×192 → assets/images/avatars/
- 背景（標題、對戰桌、選單）：裁成 1280×720；卡背裁成 300×420
- 卡包、金幣、屬性圖示：去洋紅 (#FF00FF) 背景 → 裁到物件範圍 → 縮圖
另存 art_src/_preview.png（全部縮圖拼一張）方便檢查。
用法：python tools/process_art.py
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_src"
OUT = ROOT / "assets" / "images"
sys.path.insert(0, str(ROOT / "tools"))
import gen_art  # noqa: E402


def latest(name: str) -> Path:
    files = sorted(SRC.glob(f"{name}_[0-9]*.png"))
    if not files:
        raise SystemExit(f"找不到 art_src/{name}_*.png")
    return files[-1]


def key_out(img: Image.Image) -> Image.Image:
    a = np.asarray(img.convert("RGB")).astype(np.float32)
    dist = np.sqrt(((a - np.array([255.0, 0.0, 255.0])) ** 2).sum(axis=2))
    alpha = np.clip((dist - 70.0) / 90.0, 0.0, 1.0)
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    excess = np.clip(np.minimum(r, b) - g, 0, None)
    edge = alpha < 0.999
    r[edge] -= excess[edge] * 0.9
    b[edge] -= excess[edge] * 0.9
    return Image.fromarray(np.dstack([np.clip(a, 0, 255), alpha * 255.0]).astype(np.uint8))


def crop_resize(img: Image.Image, longest: int) -> Image.Image:
    alpha = np.asarray(img)[..., 3]
    ys, xs = np.where(alpha > 25)
    img = img.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))
    scale = longest / max(img.size)
    return img.resize((max(1, round(img.width * scale)), max(1, round(img.height * scale))), Image.LANCZOS)


def cover(img: Image.Image, w: int, h: int) -> Image.Image:
    scale = max(w / img.width, h / img.height)
    img = img.resize((round(img.width * scale), round(img.height * scale)), Image.LANCZOS)
    x, y = (img.width - w) // 2, (img.height - h) // 2
    return img.crop((x, y, x + w, y + h))


def main() -> None:
    made = []

    def save(img, sub, name):
        d = OUT / sub
        d.mkdir(parents=True, exist_ok=True)
        img.save(d / f"{name}.png", optimize=True)
        made.append(img)

    for k in list(gen_art.BEASTS) + list(gen_art.ENERGY) + list(gen_art.TRAINERS):
        save(cover(Image.open(latest(k)).convert("RGB"), 256, 256), "cards", k)
    for k in gen_art.AVATARS:
        save(cover(Image.open(latest(k)).convert("RGB"), 192, 192), "avatars", k)
    for k in ("bg_title", "bg_battle", "bg_menu"):
        save(cover(Image.open(latest(k)).convert("RGB"), 1280, 720), "ui", k)
    save(cover(Image.open(latest("card_back")).convert("RGB"), 300, 420), "ui", "card_back")
    save(crop_resize(key_out(Image.open(latest("pack"))), 360), "ui", "pack")
    save(crop_resize(key_out(Image.open(latest("coin"))), 96), "ui", "coin")
    for k in gen_art.ICONS:
        save(crop_resize(key_out(Image.open(latest(k))), 64), "icons", k)

    # 預覽總覽圖
    cell = 128
    cols = 10
    rows = (len(made) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cell, rows * cell), (60, 60, 70, 255))
    for i, im in enumerate(made):
        t = im.convert("RGBA").copy()
        t.thumbnail((cell - 4, cell - 4))
        sheet.alpha_composite(t, ((i % cols) * cell + 2, (i // cols) * cell + 2))
    sheet.save(SRC / "_preview.png")
    print(f"處理 {len(made)} 張，預覽：art_src/_preview.png")


if __name__ == "__main__":
    main()
