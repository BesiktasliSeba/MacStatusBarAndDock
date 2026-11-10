// test-previewpick.c: which viewer Finder's Quick Look window shows a file in (common/PreviewPick.h, 1.8.4.2 item 2): our own where it does better
// (pictures, PDFs, audio and video, plain text and code), iPadOS's Quick Look for what ours didn't show (Excel, Word, PowerPoint, iWork, USDZ...)
// and for the kinds of text it draws (RTF, HTML, CSV), the icon, kind and size for what neither can show (and for folders).
#include <stdio.h>
#include "../common/PreviewPick.h"
static int fails = 0;
static void check(const char *what, int ok) { printf("%s  %s\n", ok ? "PASS" : "FAIL", what); if (!ok) fails = 1; }
int main(void) {
    const unsigned QL = MSBD_PVF_QL;
    // ---- KT's report: "PDFs preview, Excel doesn't"
    check("an Excel file (xlsx: none of ours, Quick Look can): Quick Look", MSBDPreviewPick(QL) == MSBD_PV_QUICKLOOK);
    check("  ... without Quick Look (it can't, or isn't there): the icon, kind and size, as before", MSBDPreviewPick(0) == MSBD_PV_INFO);
    check("a PDF: ours (PDFKit, in-process, with our page geometry fix), even where Quick Look could", MSBDPreviewPick(MSBD_PVF_PDF | QL) == MSBD_PV_PDF && MSBDPreviewPick(MSBD_PVF_PDF) == MSBD_PV_PDF);
    // ---- ours where it is better
    check("a picture: ours (ImageIO, at most 2048 px)", MSBDPreviewPick(MSBD_PVF_IMAGE | QL) == MSBD_PV_IMAGE && MSBDPreviewPick(MSBD_PVF_IMAGE) == MSBD_PV_IMAGE);
    check("  ... one ImageIO can't read (SVG): Quick Look", MSBDPreviewPick(MSBD_PVF_IMAGE | MSBD_PVF_UNREADABLE | QL) == MSBD_PV_QUICKLOOK);
    check("  ... and without Quick Look: its text if it is text (SVG is XML), else the icon",
          MSBDPreviewPick(MSBD_PVF_IMAGE | MSBD_PVF_UNREADABLE | MSBD_PVF_TEXT) == MSBD_PV_TEXT && MSBDPreviewPick(MSBD_PVF_IMAGE | MSBD_PVF_UNREADABLE) == MSBD_PV_INFO);
    check("audio and video: ours (AVKit, its controls work by touch)", MSBDPreviewPick(MSBD_PVF_MEDIA | QL) == MSBD_PV_MEDIA);
    check("plain text, code, logs, plists: ours (binary plists as XML, 512 KB at most)", MSBDPreviewPick(MSBD_PVF_TEXT | QL) == MSBD_PV_TEXT && MSBDPreviewPick(MSBD_PVF_TEXT) == MSBD_PV_TEXT);
    // ---- Quick Look for the text it draws
    check("RTF, HTML, CSV (text to UTType): Quick Look draws them, not their source", MSBDPreviewPick(MSBD_PVF_TEXT | MSBD_PVF_RICH | QL) == MSBD_PV_QUICKLOOK);
    check("  ... without Quick Look: their text, as before", MSBDPreviewPick(MSBD_PVF_TEXT | MSBD_PVF_RICH) == MSBD_PV_TEXT);
    check("  ... RTFD (a package, not text to us): Quick Look, else the icon", MSBDPreviewPick(MSBD_PVF_RICH | QL) == MSBD_PV_QUICKLOOK && MSBDPreviewPick(MSBD_PVF_RICH) == MSBD_PV_INFO);
    check("the kinds Quick Look draws: rtf, rtfd, html, htm, xhtml, csv, tsv (any case)",
          MSBDPreviewRichExt("rtf") && MSBDPreviewRichExt("RTFD") && MSBDPreviewRichExt("html") && MSBDPreviewRichExt("htm") && MSBDPreviewRichExt("xhtml") && MSBDPreviewRichExt("Csv") && MSBDPreviewRichExt("tsv"));
    check("  ... not plain text, code or Markdown, not none", !MSBDPreviewRichExt("txt") && !MSBDPreviewRichExt("m") && !MSBDPreviewRichExt("md") && !MSBDPreviewRichExt("json") && !MSBDPreviewRichExt("") && !MSBDPreviewRichExt(0));
    // ---- the rest
    check("Word, PowerPoint, Pages, Numbers, Keynote, USDZ, a zip (Quick Look can): Quick Look", MSBDPreviewPick(QL) == MSBD_PV_QUICKLOOK);
    check("a folder: its icon, kind and size, never Quick Look", MSBDPreviewPick(MSBD_PVF_DIR | QL) == MSBD_PV_INFO && MSBDPreviewPick(MSBD_PVF_DIR) == MSBD_PV_INFO);
    // ---- debug switches
    check("(debug) /tmp/msb-qloff: our own viewers only, as before 1.8.4.2", MSBDPreviewPick(QL | MSBD_PVF_QL_OFF) == MSBD_PV_INFO && MSBDPreviewPick(MSBD_PVF_TEXT | MSBD_PVF_RICH | QL | MSBD_PVF_QL_OFF) == MSBD_PV_TEXT);
    check("(debug) /tmp/msb-qlall: Quick Look for all it can show (a PDF, a picture), not for what it can't",
          MSBDPreviewPick(MSBD_PVF_PDF | QL | MSBD_PVF_QL_ALL) == MSBD_PV_QUICKLOOK && MSBDPreviewPick(MSBD_PVF_IMAGE | QL | MSBD_PVF_QL_ALL) == MSBD_PV_QUICKLOOK
          && MSBDPreviewPick(MSBD_PVF_PDF | MSBD_PVF_QL_ALL) == MSBD_PV_PDF);
    if (fails) { printf("test-previewpick (compiled): FAILED\n"); return 1; }
    printf("test-previewpick (compiled): all checks pass\n"); return 0;
}
