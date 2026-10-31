"""把 Noto Sans TC（SIL OFL 開源授權，可隨遊戲散布）裁成只含遊戲用到的字，存到 assets/fonts/game_font.ttf。
網頁版讀不到系統字型，一定要內嵌字型；裁字後檔案從約 10 MB 降到幾百 KB。
另外收 Big5 常用字，玩家取名用。改了遊戲裡的中文字就要重跑：python tools/make_font.py
"""
import re
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

ROOT = Path(__file__).resolve().parent.parent
SRC_CANDIDATES = [
    Path("C:/Windows/Fonts/NotoSansTC-VF.ttf"),
    Path.home() / "AppData/Local/Microsoft/Windows/Fonts/NotoSansTC-VF.ttf",
]
OUT = ROOT / "assets" / "fonts" / "game_font.ttf"


def main() -> None:
    src = next((p for p in SRC_CANDIDATES if p.exists()), None)
    if src is None:
        raise SystemExit("找不到 NotoSansTC-VF.ttf，請先安裝 Noto Sans TC")
    chars = set(chr(c) for c in range(0x20, 0x7F))
    chars |= set("０１２３４５６７８９？□×－＋（）：，。！、／→・～％「」")
    for f in list((ROOT / "scripts").glob("*.gd")) + list((ROOT / "tests").glob("*.gd")):
        for lit in re.findall(r'"([^"]*)"', f.read_text(encoding="utf-8")):
            chars |= set(lit)
    # 保險：所有腳本裡出現的中日韓字元都收（字串跨行或組字時也不會漏）
    for f in (ROOT / "scripts").glob("*.gd"):
        chars |= {c for c in f.read_text(encoding="utf-8") if ord(c) > 0x2000}
    # 玩家自己取名字、線上對手名字會用到任何常用字：收 Big5 常用字（5401 字）
    for hi in range(0xA4, 0xC7):
        for lo in list(range(0x40, 0x7F)) + list(range(0xA1, 0xFF)):
            try:
                chars |= set(bytes([hi, lo]).decode("big5"))
            except UnicodeDecodeError:
                pass
    text = "".join(sorted(chars))
    font = TTFont(src)
    # 可變字型先固定在一般字重（400），再裁字
    if "fvar" in font:
        from fontTools.varLib import instancer
        font = instancer.instantiateVariableFont(font, {"wght": 500})
    opts = subset.Options()
    opts.layout_features = ["*"]
    sub = subset.Subsetter(opts)
    sub.populate(text=text)
    sub.subset(font)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    font.save(OUT)
    print(f"{len(text)} 字 → {OUT.name} {OUT.stat().st_size // 1024} KB（來源 {src}）")


if __name__ == "__main__":
    main()
