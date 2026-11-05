# The pdf lane's corpus (tests/pdf/corpus/*.pdf), made by real writers so
# helder.pdf reads what they write: ReportLab (the standard 14 fonts not
# embedded, an embedded Type 1 font, RC4 encryption, CMYK, dashes, a JPEG),
# pypdf (AES-128 and AES-256 encryption, object and xref streams),
# LibreOffice (TrueType subsets, a table, images), and PDF written by hand
# (a Type 3 font, an inline image, a shading, a tiling pattern, a damaged
# xref). Everything in it is this repository's or public domain (Bitstream
# Charter: its license allows redistribution). Run again when it changes,
# then the references (tests/pdf/pdfjs.mjs):
#
#   python3 tests/pdf/corpus.py      (reportlab, pypdf with cryptography, soffice)
import io, os, subprocess, tempfile, zlib
from reportlab.pdfgen import canvas
from reportlab.lib.colors import CMYKColor, Color
from reportlab.pdfbase import pdfmetrics
from pypdf import PdfReader, PdfWriter

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

standard(f"{OUT}/standard-fonts.pdf")
standard(f"{OUT}/rc4-128.pdf", encrypt=__import__("reportlab.lib.pdfencrypt", fromlist=["StandardEncryption"]).StandardEncryption("", "owner", strength=128))
type1(f"{OUT}/type1-charter.pdf")
office(f"{OUT}/libreoffice.pdf")
aes(f"{OUT}/standard-fonts.pdf", f"{OUT}/aes-128.pdf", "AES-128")
aes(f"{OUT}/libreoffice.pdf", f"{OUT}/aes-256.pdf", "AES-256")
streams(f"{OUT}/type1-charter.pdf", f"{OUT}/object-streams.pdf")
raw(f"{OUT}/type3-shading-pattern.pdf")
raw(f"{OUT}/damaged-xref.pdf", damaged=True)
print("corpus.py:", sorted(os.listdir(OUT)))
