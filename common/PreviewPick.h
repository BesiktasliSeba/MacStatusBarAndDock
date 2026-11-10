// PreviewPick.h -- which viewer our Quick Look window shows a file in (1.8.4.2 item 2, KT 8 Nov 2026: "PDFs preview, Excel doesn't"). Plain C, so
// the Mac test (tools/test-previewpick.c) runs this very code; Finder.h (DMQuickLookWindow) gives it what it knows of the file.
// Our own viewers stay where they do better than iPadOS's Quick Look inside SpringBoard: they draw in-process, so touches, scrolling and the
// keys work in them as in any of our windows (Apple's QLPreviewController draws most files from another process, QuickLookUIService, and in
// SpringBoard's windows the touches for that part went nowhere -- see Finder.h). Ours: pictures (ImageIO, at most 2048 px), PDFs (PDFKit, with
// our page geometry fix), audio and video (AVKit), and plain text and code (logs, plists -- binary ones shown as XML --, JSON, scripts).
// Quick Look for the rest it can show: Office (xlsx, docx, pptx), iWork, RTF, HTML, CSV, USDZ, and pictures ImageIO can't read (SVG...). RTF,
// HTML and CSV are text to UTType, but our text viewer showed their source: Quick Look draws them. Nothing Quick Look can show: the file's icon,
// kind and size, as a Mac's Quick Look does (a folder too, with its size).
#ifndef MSBD_PREVIEW_PICK_H
#define MSBD_PREVIEW_PICK_H
#include <strings.h>

enum {   // what the file is (Finder.h works it out from its UTType and the file system)
    MSBD_PVF_DIR = 1 << 0,         // a folder (not a package: those are shown as files)
    MSBD_PVF_IMAGE = 1 << 1,       // UTTypeImage
    MSBD_PVF_PDF = 1 << 2,         // UTTypePDF
    MSBD_PVF_MEDIA = 1 << 3,       // UTTypeAudiovisualContent
    MSBD_PVF_TEXT = 1 << 4,        // text or code our text viewer reads (DMQLIsText)
    MSBD_PVF_RICH = 1 << 5,        // a kind of text Quick Look draws better than its source (MSBDPreviewRichExt)
    MSBD_PVF_UNREADABLE = 1 << 6,  // a picture ImageIO could not read
    MSBD_PVF_QL = 1 << 7,          // Quick Look is there (QuickLook.framework opened) and says it can show the file (+canPreviewItem:)
    MSBD_PVF_QL_OFF = 1 << 8,      // (debug, /tmp/msb-qloff: never Quick Look, to compare)
    MSBD_PVF_QL_ALL = 1 << 9,      // (debug, /tmp/msb-qlall: Quick Look for everything it can show, to compare)
};
enum { MSBD_PV_INFO = 0, MSBD_PV_IMAGE = 1, MSBD_PV_PDF = 2, MSBD_PV_MEDIA = 3, MSBD_PV_TEXT = 4, MSBD_PV_QUICKLOOK = 5 };

// RTF, HTML, CSV, TSV (and RTFD, a package): text to UTType, drawn by Quick Look.
static inline int MSBDPreviewRichExt(const char *ext) {
    static const char *const rich[] = { "rtf", "rtfd", "html", "htm", "xhtml", "csv", "tsv", 0 };
    if (!ext || !*ext) return 0;
    for (int i = 0; rich[i]; i++) if (!strcasecmp(ext, rich[i])) return 1;
    return 0;
}
static inline int MSBDPreviewPick(unsigned f) {
    if (f & MSBD_PVF_DIR) return MSBD_PV_INFO;
    int ql = (f & MSBD_PVF_QL) && !(f & MSBD_PVF_QL_OFF);
    if (ql && (f & MSBD_PVF_QL_ALL)) return MSBD_PV_QUICKLOOK;
    if ((f & MSBD_PVF_IMAGE) && !(f & MSBD_PVF_UNREADABLE)) return MSBD_PV_IMAGE;
    if (f & MSBD_PVF_PDF) return MSBD_PV_PDF;
    if (f & MSBD_PVF_MEDIA) return MSBD_PV_MEDIA;
    if (ql && (f & MSBD_PVF_RICH)) return MSBD_PV_QUICKLOOK;
    if ((f & MSBD_PVF_TEXT) && !(f & MSBD_PVF_RICH)) return MSBD_PV_TEXT;
    if (ql) return MSBD_PV_QUICKLOOK;
    if (f & MSBD_PVF_TEXT) return MSBD_PV_TEXT;   // (RTF or CSV without Quick Look: its text, as before)
    return MSBD_PV_INFO;
}
#endif
