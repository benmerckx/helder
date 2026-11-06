# The pdf lane's corpus (tests/pdf/corpus/*.pdf), made by real writers so
# helder.pdf reads what they write: ReportLab (the standard 14 fonts not
# embedded, an embedded Type 1 font, RC4 encryption, CMYK, dashes, a JPEG),
# pypdf (AES-128 and AES-256 encryption, object and xref streams),
# LibreOffice (TrueType subsets, a table, images), and PDF written by hand
# (a Type 3 font, an inline image, a shading, a tiling pattern, a damaged
# xref), and pages as they come from the world: a scanned page (a JPEG of
# a page of text, a little rotated and noisy), a JPX image and a CCITT G4
# scan (helder decodes neither yet: tests/pdf/known.txt), CJK text
# (LibreOffice: Type 0 fonts, Identity-H), a long document (120 pages),
# form fields (ReportLab's AcroForm: widgets with appearance streams).
# Everything in it is this repository's or public domain (Bitstream
# Charter: its license allows redistribution). Run again when it changes,
# then the references (tests/pdf/pdfjs.mjs):
#
#   python3 tests/pdf/corpus.py      (reportlab, pypdf with cryptography, soffice)
import io, os, subprocess, tempfile, zlib
from reportlab.pdfgen import canvas
from reportlab.lib.colors import CMYKColor, Color
from reportlab.pdfbase import pdfmetrics
from pypdf import PdfReader, PdfWriter
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import random

OUT = os.path.join(os.path.dirname(__file__), "corpus")
os.makedirs(OUT, exist_ok=True)
W, H = 360, 240

def standard(path, encrypt=None):
    c = canvas.Canvas(path, pagesize=(W, H), encrypt=encrypt)
    c.setFillColorRGB(0.95, 0.96, 0.98); c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFont("Helvetica-Bold", 20); c.setFillColorRGB(0.1, 0.2, 0.5); c.drawString(20, 200, "Helvetica Bold, 20 pt")
    c.setFont("Times-Roman", 16); c.setFillColorRGB(0, 0, 0); c.drawString(20, 172, "Times Roman: the quick brown fox")
    c.setFont("Courier", 12); c.drawString(20, 150, "Courier 12: 0123456789 {}[]")
    c.setStrokeColor(CMYKColor(0, 0.8, 0.9, 0)); c.setLineWidth(6); c.setDash(12, 6); c.line(20, 120, 340, 120)
    c.setDash(); c.setFillColor(CMYKColor(0.8, 0.1, 0, 0.1)); c.circle(80, 60, 40, fill=1, stroke=0)
    c.setFillColor(Color(0.9, 0.2, 0.3, alpha=0.6)); c.roundRect(110, 25, 120, 70, 14, fill=1, stroke=0)
    c.setStrokeColorRGB(0.2, 0.6, 0.2); c.setLineWidth(3); c.setLineJoin(1)
    p = c.beginPath(); p.moveTo(250, 30); p.curveTo(280, 120, 320, 0, 340, 90); c.drawPath(p, stroke=1, fill=0)
    c.showPage(); c.save()

def type1(path):
    d = "/usr/share/fonts/X11/Type1/"
    face = pdfmetrics.EmbeddedType1Face(d + "c0648bt_.afm", d + "c0648bt_.pfb")
    pdfmetrics.registerTypeFace(face)
    pdfmetrics.registerFont(pdfmetrics.Font("CharterBT", face.name, "WinAnsiEncoding"))
    c = canvas.Canvas(path, pagesize=(W, H))
    c.setFillColorRGB(1, 1, 1); c.rect(0, 0, W, H, fill=1, stroke=0)
    c.setFillColorRGB(0, 0, 0)
    c.setFont("CharterBT", 28); c.drawString(20, 180, "Charter, Type 1")
    c.setFont("CharterBT", 16); c.drawString(20, 140, "Embedded: eexec, charstrings")
    c.drawString(20, 110, "accents: éèê üö Åç")
    c.setFont("CharterBT", 48); c.setFillColorRGB(0.6, 0.1, 0.2); c.drawString(20, 40, "Qg&fi")
    c.showPage(); c.save()

def office(path):
    html = """<html><body style="font-family:'DejaVu Sans'">
<h1 style="color:#1e3a8a">LibreOffice writer</h1>
<p>A paragraph in <b>bold</b>, <i>italic</i> and <span style="font-family:'DejaVu Serif'">serif</span> text, with <span style="color:#be123c">colour</span>.</p>
<table border="1" cellpadding="4" style="border-collapse:collapse"><tr><th>Script</th><th>Text</th></tr>
<tr><td>Greek</td><td>Ελληνικά</td></tr><tr><td>Cyrillic</td><td>Кириллица</td></tr><tr><td>Mono</td><td style="font-family:'DejaVu Sans Mono'">mono 0123</td></tr></table>
</body></html>"""
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "office.html")
        open(src, "w").write(html)
        subprocess.run(["soffice", "--headless", "--convert-to", "pdf:writer_web_pdf_Export", "--outdir", t, src], check=True, capture_output=True)
        open(path, "wb").write(open(os.path.join(t, "office.pdf"), "rb").read())

def aes(src, path, algorithm):
    r = PdfReader(src); w = PdfWriter()
    for p in r.pages: w.add_page(p)
    w.encrypt(user_password="", owner_password="owner", algorithm=algorithm)
    with open(path, "wb") as f: w.write(f)

def streams(src, path):
    # (object streams and an xref stream: pypdf's compressed writer)
    r = PdfReader(src); w = PdfWriter()
    for p in r.pages: w.add_page(p)
    w.compress_identical_objects()
    for p in w.pages: p.compress_content_streams()
    with open(path, "wb") as f: w.write(f)

def raw(path, damaged=False):
    # a Type 3 font (two glyphs drawn as paths), an inline image, an axial shading (sh), a tiling pattern
    objs = []
    def obj(s): objs.append(s if isinstance(s, bytes) else s.encode("latin-1")); return len(objs)
    def stream(d, data): return obj(b"<< " + d.encode() + b" /Length " + str(len(data)).encode() + b" >>\nstream\n" + data + b"\nendstream")
    sq = stream("", b"1000 0 0 0 1000 1000 d1 100 100 m 900 100 l 900 900 l 100 900 l h f")
    tri = stream("", b"1000 0 0 0 1000 1000 d1 100 100 m 900 100 l 500 900 l h f")
    font = obj("<< /Type /Font /Subtype /Type3 /FontBBox [0 0 1000 1000] /FontMatrix [0.001 0 0 0.001 0 0] /CharProcs << /sq %d 0 R /tri %d 0 R >> /Encoding << /Type /Encoding /Differences [65 /sq /tri] >> /FirstChar 65 /LastChar 66 /Widths [1100 1100] >>" % (sq, tri))
    fn = obj("<< /FunctionType 2 /Domain [0 1] /C0 [0.9 0.2 0.1] /C1 [0.1 0.3 0.9] /N 1 >>")
    sh = obj("<< /ShadingType 2 /ColorSpace /DeviceRGB /Coords [20 20 160 20] /Function %d 0 R /Extend [true true] >>" % fn)
    cell = stream("/Type /Pattern /PatternType 1 /PaintType 1 /TilingType 1 /BBox [0 0 20 20] /XStep 20 /YStep 20 /Resources << >>", b"0 0.6 0.3 rg 0 0 10 10 re f 1 0.8 0 rg 10 10 10 10 re f")
    img = bytes([255, 0, 0, 0, 255, 0, 0, 0, 255, 255, 255, 0])
    content = (b"1 1 1 rg 0 0 360 240 re f q 20 20 140 90 re W n /S0 sh Q "
               b"q /Pattern cs /P0 scn 190 20 150 90 re f Q "
               b"0 0 0 rg BT /F0 40 Tf 20 150 Td 3 Tr 0 Tr (ABAB) Tj ET "
               b"q 120 0 0 60 220 150 cm BI /W 2 /H 2 /BPC 8 /CS /RGB ID " + img + b" EI Q")
    cont = stream("", content)
    page = obj("<< /Type /Page /Parent 999 0 R /MediaBox [0 0 360 240] /Contents %d 0 R /Resources << /Font << /F0 %d 0 R >> /Shading << /S0 %d 0 R >> /Pattern << /P0 %d 0 R >> >> >>" % (cont, font, sh, cell))
    pages = obj("<< /Type /Pages /Kids [%d 0 R] /Count 1 >>" % page)
    objs[page - 1] = objs[page - 1].replace(b"999 0 R", b"%d 0 R" % pages)
    cat = obj("<< /Type /Catalog /Pages %d 0 R >>" % pages)
    out = io.BytesIO(); out.write(b"%PDF-1.4\n"); offs = []
    for i, o in enumerate(objs):
        offs.append(out.tell()); out.write(b"%d 0 obj\n" % (i + 1) + o + b"\nendobj\n")
    x = out.tell(); out.write(b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1))
    for o in offs: out.write(b"%010d 00000 n \n" % (o + (37 if damaged else 0)))
    out.write(b"trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, cat, x + (11 if damaged else 0)))
    open(path, "wb").write(out.getvalue())

def image_page(path, w, h, extra, data, pw=W, ph=H):
    # a page of one image XObject, written by hand (the filters ReportLab does not write)
    objs = []
    def obj(b): objs.append(b); return len(objs)
    img = obj(b"<< /Type /XObject /Subtype /Image /Width %d /Height %d %s /Length %d >>\nstream\n" % (w, h, extra, len(data)) + data + b"\nendstream")
    content = b"q %d 0 0 %d 0 0 cm /Im0 Do Q" % (pw, ph)
    cont = obj(b"<< /Length %d >>\nstream\n" % len(content) + content + b"\nendstream")
    obj(b"<< /Type /Page /Parent 4 0 R /MediaBox [0 0 %d %d] /Contents %d 0 R /Resources << /XObject << /Im0 %d 0 R >> >> >>" % (pw, ph, cont, img))
    obj(b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>")
    obj(b"<< /Type /Catalog /Pages 4 0 R >>")
    out = io.BytesIO(); out.write(b"%PDF-1.5\n"); offs = []
    for i, o in enumerate(objs): offs.append(out.tell()); out.write(b"%d 0 obj\n" % (i + 1) + o + b"\nendobj\n")
    x = out.tell(); out.write(b"xref\n0 %d\n0000000000 65535 f \n" % (len(objs) + 1))
    for o in offs: out.write(b"%010d 00000 n \n" % o)
    out.write(b"trailer\n<< /Size %d /Root 5 0 R >>\nstartxref\n%d\n%%%%EOF\n" % (len(objs) + 1, x)); open(path, "wb").write(out.getvalue())

LINES = ["A scanned page of text, as a copier makes it:", "a little rotated, a little noisy, grey,", "a JPEG of it on a page of its own.", "0123456789 ABCDEFGHIJKLM nopqrstuvwxyz"]

def page_bitmap(dpi, mode="L"):
    k = dpi / 72; img = Image.new(mode, (int(W * k), int(H * k)), 255 if mode == "L" else 1)
    d = ImageDraw.Draw(img); f = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf", int(14 * k))
    for i, l in enumerate(LINES): d.text((int(20 * k), int((30 + i * 28) * k)), l, font=f, fill=0)
    d.rectangle([int(20 * k), int(150 * k), int(340 * k), int(220 * k)], outline=0, width=int(2 * k))
    return img

def scanned(path):
    random.seed(3)
    img = page_bitmap(150).rotate(0.6, resample=Image.BICUBIC, fillcolor=250).filter(ImageFilter.GaussianBlur(0.6))
    img = Image.eval(img, lambda v: max(0, min(255, int(v * 0.92 + 12))))
    px = img.load()
    for _ in range(4000): px[random.randrange(img.width), random.randrange(img.height)] = random.randrange(150, 255)
    b = io.BytesIO(); img.save(b, "JPEG", quality=70)
    image_page(path, img.width, img.height, b"/ColorSpace /DeviceGray /BitsPerComponent 8 /Filter /DCTDecode", b.getvalue())

def jpx(path):
    img = page_bitmap(100).convert("RGB")
    d = ImageDraw.Draw(img); d.ellipse([60, 220, 200, 300], fill=(200, 40, 60)); d.ellipse([260, 220, 420, 300], fill=(30, 120, 220))
    b = io.BytesIO(); img.save(b, "JPEG2000", quality_mode="rates", quality_layers=[30])
    image_page(path, img.width, img.height, b"/ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /JPXDecode", b.getvalue())

def ccitt(path):
    img = page_bitmap(200, "1")
    t = io.BytesIO(); img.save(t, "TIFF", compression="group4", strip_size=2**30); tif = Image.open(io.BytesIO(t.getvalue()))
    off, n = tif.tag_v2[273][0], tif.tag_v2[279][0]
    image_page(path, img.width, img.height, b"/ColorSpace /DeviceGray /BitsPerComponent 1 /Filter /CCITTFaxDecode /DecodeParms << /K -1 /Columns %d /Rows %d /BlackIs1 false >>" % (img.width, img.height), t.getvalue()[off:off + n])

def cjk(path):
    html = """<html><body>
<h2 style="font-family:'IPAGothic'">日本語のテキスト</h2>
<p style="font-family:'IPAGothic'">これは日本語の段落です。ひらがな、カタカナ、漢字。</p>
<p style="font-family:'WenQuanYi Zen Hei'">这是中文段落：简体字，标点符号。</p>
<p style="font-family:'WenQuanYi Zen Hei'">한국어 문장도 있습니다.</p>
</body></html>"""
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "cjk.html")
        open(src, "w").write(html)
        subprocess.run(["soffice", "--headless", "--convert-to", "pdf:writer_web_pdf_Export", "--outdir", t, src], check=True, capture_output=True)
        open(path, "wb").write(open(os.path.join(t, "cjk.pdf"), "rb").read())

def long(path):
    random.seed(5)
    words = "the of and to in is that for it as with was on be by this are from at or an have not which".split()
    c = canvas.Canvas(path, pagesize=(W, H))
    for p in range(120):
        c.setFont("Helvetica-Bold", 14); c.drawString(20, 210, "Chapter %d" % (p + 1))
        c.setFont("Times-Roman", 10)
        for i in range(14): c.drawString(20, 185 - i * 12, " ".join(random.choice(words) for _ in range(12)))
        c.setFont("Helvetica", 8); c.drawString(170, 8, str(p + 1)); c.showPage()
    c.save()

def forms(path):
    c = canvas.Canvas(path, pagesize=(W, H))
    c.setFont("Helvetica", 12); c.drawString(20, 210, "A form, its fields as ReportLab writes them")
    f = c.acroForm
    c.drawString(20, 175, "Name"); f.textfield(name="name", value="Ada Lovelace", x=90, y=168, width=200, height=22, borderColor=Color(0.2, 0.3, 0.6), fillColor=Color(0.93, 0.95, 1), fontSize=12)
    c.drawString(20, 140, "Agree"); f.checkbox(name="agree", x=90, y=134, size=18, checked=True, buttonStyle="check", borderColor=Color(0.2, 0.3, 0.6))
    c.drawString(20, 105, "Colour"); f.choice(name="colour", value="Green", options=["Red", "Green", "Blue"], x=90, y=98, width=120, height=22, fontSize=12)
    f.radio(name="size", value="s", selected=True, x=90, y=60, size=16, buttonStyle="circle"); f.radio(name="size", value="m", selected=False, x=120, y=60, size=16, buttonStyle="circle")
    c.drawString(20, 63, "Size")
    c.showPage(); c.save()

standard(f"{OUT}/standard-fonts.pdf")
standard(f"{OUT}/rc4-128.pdf", encrypt=__import__("reportlab.lib.pdfencrypt", fromlist=["StandardEncryption"]).StandardEncryption("", "owner", strength=128))
type1(f"{OUT}/type1-charter.pdf")
office(f"{OUT}/libreoffice.pdf")
aes(f"{OUT}/standard-fonts.pdf", f"{OUT}/aes-128.pdf", "AES-128")
aes(f"{OUT}/libreoffice.pdf", f"{OUT}/aes-256.pdf", "AES-256")
streams(f"{OUT}/type1-charter.pdf", f"{OUT}/object-streams.pdf")
raw(f"{OUT}/type3-shading-pattern.pdf")
raw(f"{OUT}/damaged-xref.pdf", damaged=True)
scanned(f"{OUT}/scanned.pdf")
jpx(f"{OUT}/jpx.pdf")
ccitt(f"{OUT}/ccitt.pdf")
cjk(f"{OUT}/cjk.pdf")
long(f"{OUT}/long-120.pdf")
forms(f"{OUT}/forms.pdf")
print("corpus.py:", sorted(os.listdir(OUT)))
