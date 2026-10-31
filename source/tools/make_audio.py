"""合成原創奇幻「靈獸卡牌對戰」的 26 個音效與 4 首背景音樂，
輸出 16-bit 單聲道 WAV（SR=22050）到 assets/audio/。全部由程式（numpy）產生，沒有版權問題。

音效：峰值正規化到約 0.8，頭 3ms 淡入、尾 8ms 淡出避免爆音。
  介面／卡牌：click draw play energy evolve shuffle pack rare turn buy error coin star
  招式屬性：atk_fire atk_water atk_leaf atk_thunder atk_rock atk_normal
  狀態：hit ko heal burn paralyze；結果：win lose
背景音樂：峰值約 0.5，每首 45～60 秒，音符與殘響會「繞回開頭」疊加，所以可無縫循環。
  bgm_menu（C 大調輕快冒險，主選單／商店）  bgm_battle（A 小調，推進感，鼓＋貝斯）
  bgm_boss（D 小調，更快更激昂的冠軍戰）    bgm_victory（C 大調，明亮凱旋）
每首都有旋律、和弦進行（4 小節一個樂句，樂句再組成曲式）、貝斯、琶音、鼓。
用法：python tools/make_audio.py
"""
import wave
from pathlib import Path

import numpy as np

SR = 22050
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio"
rng = np.random.default_rng(2026)


# ───────── 基本工具 ─────────
def t_axis(dur):
    return np.arange(int(SR * dur)) / SR


def osc(kind, freq, dur, duty=0.5):
    ph = np.cumsum(np.broadcast_to(freq, t_axis(dur).shape) / SR)
    f = ph % 1.0
    if kind == "square":
        return np.where(f < duty, 1.0, -1.0)
    if kind == "tri":
        return 4.0 * np.abs(f - 0.5) - 1.0
    if kind == "saw":
        return 2.0 * f - 1.0
    return np.sin(2 * np.pi * ph)


def noise(dur):
    return rng.uniform(-1, 1, len(t_axis(dur)))


def lowpass(sig, k=8):
    return np.convolve(sig, np.ones(k) / k, "same")


def hp(sig, k=8):
    return sig - lowpass(sig, k)


def bp(sig, lo=3, hi=30):
    return lowpass(sig, lo) - lowpass(sig, hi)


def env(n, attack=0.005, release=0.05):
    t = np.arange(n) / SR
    e = np.minimum(1.0, t / max(attack, 1e-4)) * np.exp(-t / max(release, 1e-4))
    return e * np.clip((n / SR - t) / 0.004, 0, 1)


def midi(m):
    return 440.0 * 2 ** ((m - 69) / 12) if m > 0 else 0.0


def sweep(f0, f1, dur, kind="sine"):
    return osc(kind, np.linspace(f0, f1, int(SR * dur)), dur)


def tone(m, dur, kind="sine", attack=0.005, release=0.15):
    n = int(SR * dur)
    f = midi(m)
    if f <= 0:
        return np.zeros(n)
    s = osc(kind, f, dur) + 0.3 * osc("sine", f * 2, dur)
    return s * env(n, attack, release)


def seq(ms, step, kind="sine", attack=0.005, release=0.15):
    return np.concatenate([tone(m, step, kind, attack, release) for m in ms])


def bell(freq, dur, decay=0.25):
    """鐘聲：非整數倍泛音，指數衰減。"""
    n = int(SR * dur)
    s = sum(a * osc("sine", freq * r, dur) for r, a in ((1, 1), (2.76, 0.45), (5.4, 0.2), (8.9, 0.08)))
    return s * env(n, 0.002, decay)


def brass(m, dur, attack=0.02, release=None):
    n = int(SR * dur)
    f = midi(m)
    s = lowpass(osc("saw", f, dur) + 0.6 * osc("square", f * 1.004, dur), 5)
    return s * env(n, attack, release or dur * 0.8)


def place(buf, sig, t0):
    """把 sig 疊到 buf 的 t0 秒處（不繞回，超出就截掉）。"""
    p = int(SR * t0)
    if p >= len(buf):
        return
    seg = sig[: len(buf) - p]
    buf[p:p + len(seg)] += seg


def save(name, sig, vol=0.8, fade=True):
    sig = np.asarray(sig, dtype=np.float64)
    if fade:
        a, b = int(SR * 0.003), int(SR * 0.008)
        sig = sig.copy()
        sig[:a] *= np.linspace(0, 1, a)
        sig[-b:] *= np.linspace(1, 0, b)
    data = (sig / (np.max(np.abs(sig)) or 1.0) * vol * 32767).astype(np.int16)
    OUT.mkdir(parents=True, exist_ok=True)
    with wave.open(str(OUT / f"{name}.wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())
    print(f"{name}.wav  {len(data) / SR:.2f}s")


# ───────── 音效 ─────────
def sfx():
    # click：按鈕輕點
    d = 0.1
    save("click", osc("tri", 1500, d) * env(int(SR * d), 0.001, 0.015) + 0.3 * hp(noise(d), 3) * env(int(SR * d), 0.0005, 0.005))

    # draw：抽牌，紙張滑動（帶通噪音，中間最響）
    d = 0.3
    n = int(SR * d)
    sl = bp(noise(d), 3, 25) * np.sin(np.pi * np.linspace(0, 1, n)) ** 1.5
    save("draw", sl + 0.15 * hp(noise(d), 4) * np.sin(np.pi * np.linspace(0, 1, n)) ** 3)

    # play：出牌拍在桌上
    d = 0.25
    n = int(SR * d)
    thump = sweep(190, 70, d) * env(n, 0.001, 0.07)
    slap = lowpass(noise(d), 5) * env(n, 0.0005, 0.02)
    save("play", thump + 0.8 * slap)

    # energy：附加能量，上升閃亮
    up = seq([76, 81, 84, 88, 93], 0.07, "sine", 0.003, 0.15)
    sh = seq([88, 93, 96, 100, 105], 0.07, "tri", 0.003, 0.1) * 0.3
    tail = bell(midi(93), 0.35, 0.12) * 0.5
    buf = np.zeros(len(up) + len(tail))
    place(buf, up + sh, 0)
    place(buf, tail, 0.3)
    save("energy", buf)

    # evolve：上升琶音＋閃光
    arp = [60, 64, 67, 72, 76, 79, 84, 88, 91, 96]
    buf = np.zeros(int(SR * 1.15))
    for i, m in enumerate(arp):
        place(buf, tone(m, 0.18, "tri", 0.002, 0.07) * (0.5 + 0.05 * i), i * 0.065)
    for m, a in ((72, 1.0), (79, 0.8), (84, 0.8), (88, 0.7), (96, 0.5)):
        place(buf, bell(midi(m), 0.5, 0.3) * a * 0.5, 0.68)
    glit = hp(noise(0.5), 2) * np.exp(-t_axis(0.5) / 0.15) * (0.6 + 0.4 * np.sin(2 * np.pi * 30 * t_axis(0.5)))
    place(buf, glit * 0.25, 0.68)
    save("evolve", buf)

    # atk_fire：火焰轟
    d = 0.8
    n = int(SR * d)
    roar = lowpass(noise(d), 6) * env(n, 0.03, 0.3)
    crack = (rng.random(n) > 0.995) * rng.uniform(-1, 1, n) * np.exp(-t_axis(d) / 0.35)
    crack = lowpass(crack, 3) * 3
    sub = sweep(130, 45, d) * env(n, 0.01, 0.2)
    save("atk_fire", roar * 0.9 + crack * 0.5 + sub * 0.7)

    # atk_water：水花潑濺（噪音沖刷＋氣泡）
    d = 0.7
    n = int(SR * d)
    splash = bp(noise(d), 2, 18) * env(n, 0.005, 0.18)
    buf = splash.copy()
    for _ in range(9):
        f0 = rng.uniform(500, 1100)
        bd = rng.uniform(0.05, 0.1)
        b = sweep(f0, f0 * 1.8, bd) * env(int(SR * bd), 0.003, 0.03)
        place(buf, b * 0.5, rng.uniform(0.02, 0.5))
    save("atk_water", buf)

    # atk_leaf：葉片颯颯（高頻噪音快速起伏）
    d = 0.55
    n = int(SR * d)
    flutter = np.convolve(rng.uniform(0, 1, n), np.ones(180) / 180, "same")
    flutter = flutter / flutter.max()
    swoosh = np.sin(np.pi * np.linspace(0, 1, n)) ** 1.2
    save("atk_leaf", hp(noise(d), 5) * (0.4 + 0.8 * flutter) * swoosh)

    # atk_thunder：電擊劈啪
    d = 0.65
    n = int(SR * d)
    zap = sweep(3500, 250, 0.12, "saw") * env(int(SR * 0.12), 0.001, 0.05)
    buf = np.zeros(n)
    place(buf, zap, 0)
    for _ in range(14):
        bd = rng.uniform(0.01, 0.03)
        burst = hp(noise(bd), 2) * env(int(SR * bd), 0.0005, 0.01)
        place(buf, burst * rng.uniform(0.4, 1.0), rng.uniform(0.0, 0.5))
    buzz = osc("square", 85 + 15 * np.sin(2 * np.pi * 7 * t_axis(d)), d) * env(n, 0.002, 0.25)
    boom = lowpass(noise(d), 12) * env(n, 0.02, 0.2)
    save("atk_thunder", buf + 0.3 * buzz + 0.5 * boom)

    # atk_rock：岩石重擊（兩下低沉撞擊＋碎石）
    d = 0.6
    n = int(SR * d)
    buf = np.zeros(n)
    for t0, g in ((0, 1.0), (0.17, 0.8)):
        hit = sweep(150, 38, 0.35) * env(int(SR * 0.35), 0.001, 0.1) + 0.9 * lowpass(noise(0.35), 10) * env(int(SR * 0.35), 0.0005, 0.05)
        place(buf, hit * g, t0)
    for _ in range(10):
        bd = 0.03
        place(buf, bp(noise(bd), 2, 6) * env(int(SR * bd), 0.001, 0.01) * 0.4, rng.uniform(0.2, 0.55))
    save("atk_rock", buf)

    # atk_normal：一般揮擊（噪音上掃＋短促撞擊）
    d = 0.32
    n = int(SR * d)
    sw = bp(noise(d), 2, 14) * (np.linspace(0, 1, n) ** 2) * np.clip((d - t_axis(d)) / 0.12, 0, 1)
    thwack = (sweep(260, 90, 0.12) + 0.6 * lowpass(noise(0.12), 4)) * env(int(SR * 0.12), 0.0005, 0.04)
    buf = sw * 0.8
    place(buf, thwack * 1.2, 0.17)
    save("atk_normal", buf)

    # hit：受傷撞擊
    d = 0.22
    n = int(SR * d)
    save("hit", sweep(240, 70, d, "square") * 0.5 * env(n, 0.0005, 0.05) + lowpass(noise(d), 4) * env(n, 0.0005, 0.04))

    # ko：擊倒，下降音＋碰
    d = 1.0
    n = int(SR * d)
    fall = sweep(520, 60, 0.7, "saw") * env(int(SR * 0.7), 0.005, 0.35)
    fall = lowpass(fall, 4)
    buf = np.zeros(n)
    place(buf, fall * 0.8, 0)
    thud = (sweep(120, 40, 0.3) + 0.7 * lowpass(noise(0.3), 10)) * env(int(SR * 0.3), 0.001, 0.1)
    place(buf, thud * 1.1, 0.55)
    save("ko", buf)

    # heal：回復，柔和上升
    buf = np.zeros(int(SR * 0.95))
    for i, m in enumerate([72, 76, 79, 84, 88]):
        place(buf, (tone(m, 0.45, "sine", 0.03, 0.18) + 0.3 * tone(m + 12, 0.45, "sine", 0.04, 0.12)) * 0.6, i * 0.1)
    save("heal", buf)

    # coin：擲硬幣叮（兩聲高音鐘）
    buf = np.zeros(int(SR * 0.7))
    place(buf, bell(2093, 0.4, 0.09), 0)
    place(buf, bell(2794, 0.5, 0.14) * 0.8, 0.07)
    save("coin", buf)

    # shuffle：洗牌，許多短小的帶通噪音顆粒
    d = 0.85
    buf = np.zeros(int(SR * d))
    for i in range(34):
        gd = rng.uniform(0.02, 0.04)
        g = bp(noise(gd), 2, 14) * env(int(SR * gd), 0.002, 0.01)
        t0 = 0.02 + i * 0.022 + rng.uniform(0, 0.01)
        place(buf, g * rng.uniform(0.5, 1.0) * (0.6 + 0.4 * np.sin(np.pi * i / 34)), t0)
    save("shuffle", buf)

    # pack：拆卡包，撕開（鋸齒狀噪音漸響）＋啵
    d = 0.7
    n = int(SR * d)
    jag = np.repeat(rng.uniform(0.2, 1.0, n // 90 + 1), 90)[:n]
    tear = hp(noise(d), 3) * jag * np.linspace(0.3, 1, n) * np.clip((0.55 - t_axis(d)) / 0.05, 0, 1)
    buf = tear.copy()
    pop = sweep(300, 900, 0.1) * env(int(SR * 0.1), 0.001, 0.03)
    place(buf, pop * 0.6, 0.56)
    place(buf, bell(1760, 0.3, 0.08) * 0.3, 0.56)
    save("pack", buf)

    # rare：稀有卡閃亮和弦
    buf = np.zeros(int(SR * 1.2))
    for i, m in enumerate([72, 76, 79, 83, 88, 91]):
        place(buf, bell(midi(m), 1.0, 0.45) * (1.0 - 0.07 * i), i * 0.06)
    glit = hp(noise(1.0), 2) * np.exp(-t_axis(1.0) / 0.3) * (0.5 + 0.5 * np.sin(2 * np.pi * 22 * t_axis(1.0)))
    place(buf, glit * 0.12, 0.1)
    save("rare", buf)

    # turn：換回合提示音（兩聲柔鐘）
    buf = np.zeros(int(SR * 0.7))
    place(buf, bell(midi(79), 0.4, 0.14), 0)
    place(buf, bell(midi(86), 0.55, 0.2), 0.15)
    save("turn", buf)

    # burn：灼傷嘶嘶（高頻噪音＋啪啪聲＋下滑）
    d = 0.75
    n = int(SR * d)
    hiss = hp(noise(d), 4) * env(n, 0.02, 0.3) * (0.7 + 0.3 * np.sin(2 * np.pi * 16 * t_axis(d)))
    crk = (rng.random(n) > 0.997) * rng.uniform(-1, 1, n) * np.exp(-t_axis(d) / 0.4)
    warb = sweep(500, 220, d, "tri") * env(n, 0.01, 0.25) * 0.25
    save("burn", hiss + lowpass(crk, 2) * 3 + warb)

    # paralyze：麻痺滋滋（脈衝電流）
    d = 0.65
    n = int(SR * d)
    pulse = (np.sin(2 * np.pi * 24 * t_axis(d)) > 0).astype(float)
    buzz = osc("square", 120 + 40 * np.sin(2 * np.pi * 11 * t_axis(d)), d) * 0.6 + hp(noise(d), 2)
    zaps = np.zeros(n)
    for _ in range(8):
        zd = 0.03
        place(zaps, sweep(2800, 700, zd, "saw") * env(int(SR * zd), 0.0005, 0.01), rng.uniform(0, 0.55))
    save("paralyze", buzz * pulse * env(n, 0.005, 0.4) * 0.8 + zaps * 0.5)

    # buy：購買金幣（三下叮＋金幣沙沙）
    buf = np.zeros(int(SR * 0.65))
    for i, f in enumerate((1568, 2093, 2637)):
        place(buf, bell(f, 0.35, 0.1) * (0.9 - 0.1 * i), i * 0.07)
    place(buf, hp(noise(0.12), 3) * env(int(SR * 0.12), 0.002, 0.04) * 0.3, 0.0)
    save("buy", buf)

    # error：錯誤低嗶（兩聲低方波）
    one = lowpass(osc("square", 196, 0.13), 3) * env(int(SR * 0.13), 0.003, 0.2)
    two = lowpass(osc("square", 147, 0.18), 3) * env(int(SR * 0.18), 0.003, 0.2)
    buf = np.zeros(int(SR * 0.4))
    place(buf, one, 0)
    place(buf, two, 0.16)
    save("error", buf)

    # win：勝利短號角（< 2 秒）
    notes = [(67, 0.13), (67, 0.13), (67, 0.13), (72, 0.38), (70, 0.17), (72, 0.17), (76, 0.7)]
    buf = np.zeros(int(SR * 1.85))
    t0 = 0.0
    for m, dr in notes:
        place(buf, brass(m, dr + 0.05, 0.015, dr * 0.9), t0)
        t0 += dr
    t_last = t0 - 0.7
    for m in (60, 64, 67, 72):
        place(buf, brass(m, 0.9, 0.03, 0.9) * 0.4, t_last)
    place(buf, bell(midi(88), 0.6, 0.3) * 0.4, t_last)
    save("win", buf)

    # lose：失敗下行短句（< 2 秒）
    notes = [(67, 0.3), (64, 0.3), (62, 0.3), (55, 0.8)]
    buf = np.zeros(int(SR * 1.75))
    t0 = 0.0
    for m, dr in notes:
        vib = midi(m) * (1 + 0.012 * np.sin(2 * np.pi * 5 * t_axis(dr + 0.05)))
        n = int(SR * (dr + 0.05))
        s = lowpass(osc("saw", vib, dr + 0.05), 6) * env(n, 0.02, dr * 0.7)
        place(buf, s, t0)
        t0 += dr
    save("lose", buf)

    # star：得到星徽，亮叮
    buf = np.zeros(int(SR * 0.8))
    place(buf, bell(2637, 0.7, 0.22), 0)
    place(buf, bell(3951, 0.5, 0.15) * 0.5, 0.08)
    place(buf, bell(1319, 0.7, 0.3) * 0.4, 0)
    save("star", buf)


# ───────── 背景音樂 ─────────
def wadd(buf, sig, pos):
    """把 sig 疊到 buf 的 pos 取樣處，超過尾端的部分繞回開頭（無縫循環的關鍵）。"""
    n = len(buf)
    pos %= n
    if len(sig) >= n:
        sig = sig[:n]
    end = pos + len(sig)
    if end <= n:
        buf[pos:end] += sig
    else:
        k = n - pos
        buf[pos:] += sig[:k]
        buf[:len(sig) - k] += sig[k:]


def drum_samples():
    kick = sweep(125, 46, 0.24) * env(int(SR * 0.24), 0.001, 0.09)
    snare = (hp(noise(0.2), 3) * 0.8 + osc("sine", 190, 0.2) * 0.5) * env(int(SR * 0.2), 0.001, 0.055)
    hat = hp(noise(0.06), 4) * env(int(SR * 0.06), 0.0005, 0.014)
    ohat = hp(noise(0.16), 4) * env(int(SR * 0.16), 0.0005, 0.05)
    clap = bp(noise(0.15), 2, 12) * env(int(SR * 0.15), 0.001, 0.04)
    return kick, snare, hat, ohat, clap


KICK, SNARE, HAT, OHAT, CLAP = drum_samples()


def lead_note(m, dur, kind):
    n = int(SR * dur)
    f = midi(m)
    vib = f * (1 + 0.005 * np.sin(2 * np.pi * 5.5 * t_axis(dur)))
    if kind == "flute":
        s = osc("sine", vib, dur) + 0.3 * osc("tri", vib * 2, dur) + 0.12 * osc("square", vib, dur)
        return s * env(n, 0.02, dur * 0.7)
    if kind == "saw":
        s = lowpass(osc("saw", vib, dur) + 0.5 * osc("square", vib * 1.006, dur), 5)
        return s * env(n, 0.008, dur * 0.65)
    # brass
    s = lowpass(osc("saw", vib, dur) + 0.7 * osc("saw", vib * 1.007, dur) + 0.4 * osc("square", vib * 0.5, dur), 4)
    return s * env(n, 0.015, dur * 0.8)


def song(name, bpm, form, lead="flute", bass="walk", drums="light", arp="up", pad=0.2, arp_gain=0.2, lead_gain=0.4):
    """form：樂句清單，每個樂句 = (四個和弦, 旋律)。
    和弦 = (根音 MIDI, 'M' 或 'm')；旋律 = [(MIDI, 八分音符數), ...]，MIDI=0 為休止，每樂句剛好 32 個八分音符。"""
    e8 = 60 / bpm / 2
    step = int(round(SR * e8))
    bar = 8 * step
    n_bars = 4 * len(form)
    buf = np.zeros(bar * n_bars)
    bi = 0
    for chords, mel in form:
        assert sum(d for _, d in mel) == 32, (name, sum(d for _, d in mel))
        # 和弦：墊音、琶音、貝斯
        for c, (root, q) in enumerate(chords):
            tri = [root, root + (4 if q == "M" else 3), root + 7]
            pos = (bi + c) * bar
            dur_bar = bar / SR
            p = sum(osc("saw", midi(m), dur_bar + 0.15) for m in tri) / 3.0
            p = lowpass(p, 22) * np.minimum(1.0, t_axis(dur_bar + 0.15) / 0.12) * np.clip((dur_bar + 0.15 - t_axis(dur_bar + 0.15)) / 0.15, 0, 1)
            wadd(buf, p * pad, pos)
            pat = {"up": [0, 1, 2, 3, 2, 1, 2, 1], "pulse": [0, 2, 1, 2, 0, 2, 1, 2], "sparkle": [2, 3, 2, 1, 3, 2, 1, 0]}[arp]
            notes = tri + [tri[0] + 12]
            for k, idx in enumerate(pat):
                a = tone(notes[idx] + 12, e8 * 1.6, "tri", 0.002, 0.14)
                wadd(buf, a * arp_gain * (1.0 if k % 2 == 0 else 0.7), pos + k * step)
            r = root - 24
            if bass == "walk":  # 主音—五度，四分音符
                for k, m in ((0, r), (2, r), (4, r + 7), (6, r + 12 if q == "M" else r + 7)):
                    wadd(buf, tone(m, e8 * 2.2, "tri", 0.006, 0.22) * 0.5, pos + k * step)
            elif bass == "drive":  # 八分音符推進，高低八度跳動
                for k in range(8):
                    m = r + (12 if k in (3, 7) else 0)
                    b = lowpass(osc("saw", midi(m), e8 * 1.1), 4) * env(int(SR * e8 * 1.1), 0.003, 0.11)
                    wadd(buf, b * 0.5, pos + k * step)
            else:  # "gallop" 馬蹄節奏：長短短
                for k, m in enumerate([r, r, r + 12, r, r, r + 12, r + 7, r + 12]):
                    b = lowpass(osc("saw", midi(m), e8 * 1.1), 4) * env(int(SR * e8 * 1.1), 0.003, 0.09)
                    wadd(buf, b * 0.5, pos + k * step)
            # 鼓
            for k in range(8):
                kp = pos + k * step
                if drums == "light":
                    if k in (0, 4):
                        wadd(buf, KICK * 0.55, kp)
                    if k in (2, 6):
                        wadd(buf, CLAP * 0.4, kp)
                    if k % 2 == 1:
                        wadd(buf, HAT * 0.25, kp)
                elif drums == "battle":
                    if k in (0, 4) or (k == 5 and c % 2 == 1):
                        wadd(buf, KICK * 0.8, kp)
                    if k in (2, 6):
                        wadd(buf, SNARE * 0.6, kp)
                    wadd(buf, HAT * (0.3 if k % 2 == 0 else 0.2), kp)
                    if c == 3 and k == 7:
                        wadd(buf, OHAT * 0.3, kp)
                elif drums == "boss":
                    if k in (0, 1, 4) or (k == 5 and c % 2 == 1) or (k == 7 and c == 3):
                        wadd(buf, KICK * 0.85, kp)
                    if k in (2, 6):
                        wadd(buf, SNARE * 0.7, kp)
                    wadd(buf, HAT * 0.28, kp)
                    wadd(buf, HAT * 0.18, kp + step // 2)
                    if c == 3 and k >= 6:
                        wadd(buf, SNARE * 0.35, kp + step // 2)
                else:  # "victory"
                    if k in (0, 4):
                        wadd(buf, KICK * 0.7, kp)
                    if k in (2, 6):
                        wadd(buf, SNARE * 0.5, kp)
                    wadd(buf, HAT * 0.22, kp)
                    if k % 2 == 1:
                        wadd(buf, OHAT * 0.18, kp)
        # 旋律
        i = 0
        for m, d in mel:
            if m > 0:
                wadd(buf, lead_note(m, e8 * d, lead) * lead_gain, (bi * 8 + i) * step)
            i += d
        bi += 4
    f = np.tanh(buf * 1.1)  # 軟限幅，避免疊加過載
    save(f"bgm_{name}", f, 0.5, fade=False)


def bgm():
    # ── 主選單／商店：C 大調，輕快冒險 ──
    C, G, Am, F, Em, Dm = (60, "M"), (55, "M"), (57, "m"), (53, "M"), (52, "m"), (50, "m")
    mA = ([C, G, Am, F],
          [(76, 2), (79, 2), (84, 3), (83, 1), (79, 2), (74, 2), (79, 2), (83, 2), (81, 2), (84, 2), (81, 2), (76, 2), (77, 3), (81, 1), (79, 2), (0, 2)])
    mA2 = ([C, G, F, G],
           [(76, 2), (79, 2), (84, 3), (86, 1), (83, 2), (79, 2), (74, 4), (77, 2), (81, 2), (84, 2), (81, 2), (79, 3), (83, 1), (86, 4)])
    mB = ([Am, F, C, G],
          [(81, 2), (81, 1), (84, 1), (88, 2), (84, 2), (84, 2), (81, 2), (77, 2), (81, 2), (79, 2), (84, 2), (88, 3), (84, 1), (83, 2), (79, 2), (74, 2), (79, 2)])
    mB2 = ([Am, F, G, C],
           [(81, 2), (81, 1), (84, 1), (88, 2), (84, 2), (84, 2), (81, 2), (86, 2), (84, 2), (83, 2), (86, 2), (83, 2), (79, 2), (84, 6), (0, 2)])
    song("menu", 112, [mA, mA2, mB, mB2, mA, mA2], lead="flute", bass="walk", drums="light", arp="up", pad=0.2, arp_gain=0.2, lead_gain=0.42)

    # ── 對戰：A 小調，推進感 ──
    Am, F, C, G, Dm, E = (57, "m"), (53, "M"), (60, "M"), (55, "M"), (50, "m"), (52, "M")
    bA = ([Am, F, C, G],
          [(81, 2), (81, 1), (84, 1), (83, 2), (81, 2), (77, 2), (77, 1), (81, 1), (79, 2), (77, 2), (79, 2), (79, 1), (84, 1), (83, 2), (79, 2), (74, 2), (79, 2), (83, 2), (86, 2)])
    bB = ([F, G, Am, E],
          [(84, 2), (81, 2), (77, 2), (81, 2), (83, 2), (79, 2), (74, 2), (79, 2), (81, 3), (84, 1), (88, 2), (84, 2), (83, 2), (80, 2), (83, 2), (88, 2)])
    bC = ([Dm, Am, F, E],
          [(86, 2), (86, 1), (89, 1), (88, 2), (86, 2), (84, 2), (84, 1), (88, 1), (86, 2), (84, 2), (81, 2), (84, 2), (89, 2), (84, 2), (83, 2), (80, 2), (76, 2), (80, 2)])
    bD = ([F, G, Am, E],
          [(89, 2), (88, 2), (86, 2), (84, 2), (83, 2), (86, 2), (91, 2), (86, 2), (88, 2), (84, 2), (81, 2), (84, 2), (83, 1), (84, 1), (83, 2), (80, 2), (76, 2)])
    song("battle", 138, [bA, bB, bA, bC, bD, bB, bA, bC], lead="saw", bass="drive", drums="battle", arp="pulse", pad=0.17, arp_gain=0.16, lead_gain=0.36)

    # ── 冠軍戰：D 小調，更激昂 ──
    Dm, Bb, C, A, Gm, F = (62, "m"), (58, "M"), (60, "M"), (57, "M"), (55, "m"), (53, "M")
    zA = ([Dm, Bb, C, A],
          [(74, 1), (74, 1), (77, 1), (81, 1), (79, 2), (77, 2), (74, 1), (74, 1), (77, 1), (82, 1), (81, 2), (77, 2), (72, 1), (72, 1), (76, 1), (79, 1), (84, 2), (79, 2), (73, 2), (76, 2), (81, 2), (85, 2)])
    zB = ([Gm, Dm, Bb, A],
          [(79, 2), (82, 2), (86, 2), (82, 2), (81, 2), (77, 2), (74, 2), (77, 2), (82, 2), (86, 2), (89, 3), (86, 1), (85, 4), (81, 2), (76, 2)])
    zC = ([Dm, C, Bb, A],
          [(86, 1), (86, 1), (89, 1), (93, 1), (91, 2), (89, 2), (84, 1), (84, 1), (88, 1), (91, 1), (91, 2), (88, 2), (82, 1), (82, 1), (86, 1), (89, 1), (94, 2), (89, 2), (88, 2), (85, 2), (81, 2), (85, 2)])
    zD = ([Gm, F, A, Dm],
          [(82, 2), (79, 2), (82, 2), (86, 2), (81, 2), (77, 2), (81, 2), (84, 2), (85, 2), (88, 2), (93, 2), (88, 2), (86, 6), (0, 2)])
    song("boss", 150, [zA, zB, zA, zC, zB, zC, zA, zD], lead="brass", bass="gallop", drums="boss", arp="pulse", pad=0.2, arp_gain=0.15, lead_gain=0.34)

    # ── 凱旋：C 大調，明亮 ──
    C, F, G, Am, Dm, Em = (60, "M"), (53, "M"), (55, "M"), (57, "m"), (50, "m"), (52, "m")
    vA = ([C, F, G, C],
          [(79, 2), (84, 2), (88, 2), (84, 2), (84, 2), (89, 2), (88, 2), (84, 2), (83, 2), (86, 2), (91, 2), (86, 2), (84, 4), (79, 2), (84, 2)])
    vB = ([Am, Dm, G, C],
          [(81, 2), (84, 2), (88, 2), (84, 2), (86, 2), (89, 2), (86, 2), (81, 2), (83, 2), (86, 2), (83, 2), (79, 2), (84, 2), (88, 2), (91, 4)])
    vC = ([F, G, C, C],
          [(89, 3), (88, 1), (86, 2), (84, 2), (86, 3), (84, 1), (83, 2), (79, 2), (84, 2), (88, 2), (91, 2), (96, 2), (91, 2), (88, 2), (84, 4)])
    song("victory", 124, [vA, vB, vC, vA, vB, vC], lead="brass", bass="walk", drums="victory", arp="sparkle", pad=0.2, arp_gain=0.2, lead_gain=0.36)


if __name__ == "__main__":
    sfx()
    bgm()
