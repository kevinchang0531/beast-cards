"""用 draw 技能（gpt-image-2, low）產生《靈獸卡牌對戰》的全部美術原圖，存到 art_src/。
靈獸、訓練家、道具全部原創（參考集換式卡牌對戰遊戲類型，不使用任何既有遊戲的角色或名稱）。
用法：python tools/gen_art.py [名稱 ...]   （不給名稱就全部；已經有圖的會跳過，加 --force 重畫）
"""
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "art_src"
DRAW = "draw.py"  # 改成你的生圖腳本路徑

STYLE = ("original fantasy creature trading card game illustration, cute and cool anime-inspired monster design, "
         "vivid saturated colors, soft cel shading, clean bold outlines, dynamic pose")
NOTEXT = "no text, no letters, no numbers, no logos, no card frame, no border"

# 靈獸：插圖填滿整張方形卡圖區（含屬性風格背景）
BEASTS = {
    "b_embertail": "a small cute orange fox cub with a flickering flame-tipped tail and ember freckles, sitting playfully, warm volcanic meadow background",
    "b_blazecrown": "a majestic tall fire fox king with a crown of blazing flames, nine burning tails fanned out, glowing amber eyes, erupting volcano background",
    "b_cindrake": "a small chubby red salamander lizard with a tiny fire on its head and big curious eyes, glowing lava rocks background",
    "b_infernadrake": "a fierce red and black winged fire dragon with molten cracks on its scales breathing a fire blast, burning sky background",
    "b_bubbotter": "a cute round blue river otter blowing a big soap bubble, splashing water, sunny river background",
    "b_tideblade": "a sleek heroic otter warrior riding a huge wave with water blades on its forearms, ocean storm background",
    "b_jellume": "a small glowing cyan jellyfish spirit with a happy face and ribbon tentacles, deep blue underwater background",
    "b_abysslume": "a huge mysterious bioluminescent deep sea jellyfish queen with a lantern crown and long glowing tentacles, dark abyss background",
    "b_sproutbun": "a fluffy green bunny with leaf ears and a little sprout growing on its head, flower field background",
    "b_bloomhare": "an elegant swift hare with a flower crown, petal-shaped ears and vine scarf, leaping, blooming forest background",
    "b_mushlet": "a tiny cute mushroom creature with a red spotted cap, stubby legs and rosy cheeks, mossy forest floor background",
    "b_oakwarden": "a giant gentle ancient tree guardian creature with a mossy bark body, mushroom shoulders and glowing green eyes, ancient forest background",
    "b_zapwing": "a small yellow sparrow chick with zigzag lightning feathers and crackling sparks, cloudy sky background",
    "b_stormtalon": "a mighty electric eagle with blue and gold feathers, lightning bolts streaming from its wings, thunderstorm background",
    "b_voltbug": "a cute round yellow beetle with a glowing battery-like abdomen and spark antennae, night grass background",
    "b_magbeetle": "a heavy armored magnetic stag beetle with huge electrified horns and metal plates, electric field background",
    "b_pebblet": "a cute round grey pebble creature with a happy face, tiny arms and a little moss tuft, rocky canyon background",
    "b_bouldergolem": "a huge rock golem made of stacked boulders with glowing orange cracks and massive fists, mountain cliff background",
    "b_crystaliz": "a small lizard with purple crystal spikes along its back and sparkly eyes, glittering cave background",
    "b_geodrake": "a powerful dragon armored with giant purple and teal crystals, roaring, crystal cavern background",
}
ENERGY = {
    "e_fire": "a glowing orb of pure fire energy with swirling flames, magical emblem, deep red background",
    "e_water": "a glowing orb of pure water energy with swirling waves and droplets, magical emblem, deep blue background",
    "e_leaf": "a glowing orb of pure nature energy with spinning green leaves and vines, magical emblem, deep green background",
    "e_thunder": "a glowing orb of pure lightning energy with crackling yellow bolts, magical emblem, dark purple background",
    "e_rock": "a glowing orb of pure earth energy with floating rocks and crystals, magical emblem, brown background",
}
TRAINERS = {
    "t_potion": "a fantasy healing potion bottle with glowing pink liquid and a heart-shaped stopper, sparkles, item illustration",
    "t_finder": "a magical brass compass radar device that detects glowing energy orbs, item illustration",
    "t_whistle": "a silver whistle on a red cord with motion swirl lines, item illustration",
    "t_band": "a red power headband glowing with orange aura and flame sparks, item illustration",
    "t_scroll": "an ancient summoning scroll unrolling with a glowing magic circle and a creature silhouette, item illustration",
    "t_bell": "a small golden cleansing bell ringing with soft blue healing light waves, item illustration",
    "t_journal": "an adventurer's travel journal open with maps and creature sketches, a compass and a pen beside it, item illustration",
    "t_notes": "a young scholar girl with round glasses reading glowing research notes in a library, original character, character illustration",
    "t_recycle": "a magic hourglass recycling glowing energy orbs in a circle of arrows, item illustration",
}
AVATARS = {
    "av_boy": "portrait bust of an energetic boy card battler with spiky brown hair, red jacket and a confident grin",
    "av_girl": "portrait bust of a cheerful girl card battler with pink twin tails, blue hoodie and a wink",
    "av_kid": "portrait bust of a curious little kid card battler with a green cap and big round eyes, smiling",
    "av_cool": "portrait bust of a cool teen card battler with silver hair, black coat and a calm smirk",
    "ai_mia": "portrait bust of a friendly young woman trainer with short orange hair, flower hairpin and an apron, smiling warmly",
    "ai_rocco": "portrait bust of a burly cheerful mountain climber trainer with a beard, bandana and backpack straps",
    "ai_luna": "portrait bust of a mysterious young woman trainer with long blue hair, star earrings and a cloak",
    "ai_drake": "portrait bust of a stern champion trainer with slicked black hair, a red cape and golden badge",
}
AV_STYLE = "anime style character portrait, vivid colors, clean outlines, soft gradient background, " + NOTEXT

SCENES = {
    "bg_title": ("epic wide fantasy landscape at sunrise with five elemental creatures silhouettes (fire fox, water otter, leaf bunny, "
                 "thunder eagle, rock golem) on floating islands, magical glowing card symbols in the sky, " + STYLE, "1536x1024"),
    "bg_battle": ("top-down view of a magical card battle arena table, glowing blue runic circles and card placement zones on dark "
                  "stone, elegant fantasy playmat, subtle, dark enough for cards to stand out, " + NOTEXT, "1536x1024"),
    "bg_menu": ("cozy fantasy card shop and battle club interior with shelves of glowing card packs, warm lights, wooden tables, "
                "soft focus background, " + NOTEXT, "1536x1024"),
    "card_back": ("ornate fantasy trading card back design, symmetric, a glowing five-pointed elemental star emblem in the center "
                  "with fire water leaf thunder rock colors, deep navy blue and gold filigree, " + "no text, no letters", "1024x1536"),
    "pack": ("a sealed fantasy envelope packet made of shiny holographic foil, decorated with a glowing five-pointed elemental star emblem, "
             "game item illustration, isolated on a perfectly flat solid pure magenta (#FF00FF) background, no text, no letters", "1024x1536"),
    "coin": ("a shiny gold coin with a star emblem, game icon, isolated on a perfectly flat solid pure magenta (#FF00FF) "
             "background, no text", "1024x1024"),
}
ICONS = {
    "i_fire": "a red flame", "i_water": "a blue water drop", "i_leaf": "a green leaf",
    "i_thunder": "a yellow lightning bolt", "i_rock": "a brown rock crystal", "i_any": "a white four-point star",
}


def jobs():
    out = {}
    for k, v in BEASTS.items():
        out[k] = (f"{v}, {STYLE}, illustration fills the whole square, {NOTEXT}", "1024x1024")
    for k, v in ENERGY.items():
        out[k] = (f"{v}, {STYLE}, fills the whole square, {NOTEXT}", "1024x1024")
    for k, v in TRAINERS.items():
        out[k] = (f"{v}, {STYLE}, colorful background fills the whole square, {NOTEXT}", "1024x1024")
    for k, v in AVATARS.items():
        out[k] = (f"{v}, {AV_STYLE}", "1024x1024")
    for k, (p, s) in SCENES.items():
        out[k] = (p, s)
    for k, v in ICONS.items():
        out[k] = (f"a simple glossy round game icon badge of {v}, flat vector style, bold outline, isolated on a perfectly flat "
                  f"solid pure magenta (#FF00FF) background, no text", "1024x1024")
    return out


def run(name, prompt, size):
    r = subprocess.run([sys.executable, DRAW, prompt, "--name", name, "--outdir", str(OUT), "--size", size,
                        "--quality", "low"], capture_output=True, text=True, encoding="utf-8", errors="replace")
    ok = any(OUT.glob(f"{name}_[0-9]*.png"))
    print(("OK  " if ok else "FAIL") + f" {name}" + ("" if ok else f"\n{r.stdout[-400:]}\n{r.stderr[-400:]}"), flush=True)
    return ok


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    force = "--force" in sys.argv
    todo = {k: v for k, v in jobs().items() if (not args or k in args)
            and (force or not any(OUT.glob(f"{k}_[0-9]*.png")))}
    print(f"要畫 {len(todo)} 張", flush=True)
    with ThreadPoolExecutor(6) as ex:
        res = list(ex.map(lambda kv: run(kv[0], *kv[1]), todo.items()))
    print(f"完成 {sum(res)}/{len(res)}")


if __name__ == "__main__":
    main()
