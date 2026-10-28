import os
import glob
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont
from fontTools import subset

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.environ.get("NOTO_SANS_SC_VF", r"C:/Windows/Fonts/NotoSansSC-VF.ttf")
OUT_DIR = os.path.join(ROOT, "frontend", "assets", "fonts")
os.makedirs(OUT_DIR, exist_ok=True)

chars = set()
for pattern in ("frontend/lib/**/*.dart", "backend/src/**/*.rs"):
    for path in glob.glob(os.path.join(ROOT, pattern), recursive=True):
        with open(path, encoding="utf-8") as f:
            chars.update(f.read())

# ASCII printable
chars.update(chr(c) for c in range(0x20, 0x7F))

# Common CJK punctuation and symbols
chars.update("，。、；：？！“”‘’（）【】《》〈〉…—·～￥％＃＠＆＊＋－／＝｜＼＾｀｛｝［］×÷≤≥≈±°√∞∑∫")

# GB2312 level 1 (3755 most common hanzi)
for hi in range(0xB0, 0xD8):
    for lo in range(0xA1, 0xFF):
        try:
            chars.add(bytes([hi, lo]).decode("gb2312"))
        except Exception:
            pass

text = "".join(sorted(chars))
charset_path = os.path.join(OUT_DIR, "charset.txt")
with open(charset_path, "w", encoding="utf-8") as f:
    f.write(text)
print("unique chars:", len(chars))

for weight, name in ((400, "Regular"), (700, "Bold")):
    var = TTFont(SRC)
    inst = instantiateVariableFont(var, {"wght": weight})
    tmp = os.path.join(OUT_DIR, f"_tmp_{name}.ttf")
    inst.save(tmp)

    opts = subset.Options()
    opts.layout_features = ["*"]
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.drop_tables += ["DSIG"]

    font = subset.load_font(tmp, opts)
    sub = subset.Subsetter(options=opts)
    sub.populate(text=text)
    sub.subset(font)
    out = os.path.join(OUT_DIR, f"NotoSansSC-{name}.ttf")
    subset.save_font(font, out, opts)
    font.close()
    inst.close()
    var.close()
    try:
        os.remove(tmp)
    except OSError:
        pass
    print(name, os.path.getsize(out) // 1024, "KB")

os.remove(charset_path)
