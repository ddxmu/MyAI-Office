#!/usr/bin/env python3
"""Vendor the pinned Tabler outline selection and generate the two UI lookup tables.

Usage: prepare-ribbon-icons.py /path/to/unpacked/@tabler/icons-3.49.0/package
The SVG paths remain upstream artwork; only stroke colour and weight are normalized.
"""

import argparse
import json
import re
from pathlib import Path


VERSION = "3.49.0"
ROOT = Path(__file__).resolve().parents[2] / "ThirdParty"


def mapping(text):
    return dict(line.split() for line in text.strip().splitlines())


GRID = mapping("""
Paste clipboard-text
Cut scissors
Copy copy
Brush paint
Bold bold
Italic italic
Underline underline
Strike strikethrough
Borders border-bottom
BorderAll border-all
BorderNone border-none
BorderOutside border-outer
BorderThick border-style-2
Fill bucket-droplet
FontColor letter-a
AlignTop align-box-top-center
AlignMiddle align-box-center-middle
AlignBottom align-box-bottom-center
AlignLeft align-left
AlignCenter align-center
AlignRight align-right
Orientation text-orientation
IndentDec indent-decrease
IndentInc indent-increase
Wrap text-wrap
Merge arrows-minimize
Currency currency-dollar
Percent percentage
Comma quote
DecInc decimal
DecDec decimal
CondFormat color-swatch
FormatTable table-options
CellStyles palette
Insert table-plus
Delete table-minus
Format table-options
Sum sum
FillDown arrow-bar-to-down
Eraser eraser
SortFilter sort-ascending
Find search
Undo arrow-back-up
Redo arrow-forward-up
Save device-floppy
Home home
More dots
Chevron chevron-down
ChevronUp chevron-up
Close x
Check check
Fx math-function
Plus plus
Left chevron-left
Right chevron-right
Normal table
PageLayout layout
PageBreak page-break
Minus minus
Table table
PivotTable table-share
Chart chart-bar
ChartBar chart-bar
ChartLine chart-line
ChartPie chart-pie
ChartScatter chart-dots
Picture photo
Shapes shape
Link link
Comment message
Note note
TextBox text-size
Symbol omega
Sparkline chart-line
Checkbox checkbox
Function math-function
Name tags
Trace arrows-split
Calc calculator
Filter filter
SortAsc sort-ascending-letters
SortDesc sort-descending-letters
Duplicates copy-minus
TextColumns columns-3
Validation checklist
Group layers-linked
Ungroup layers-off
Subtotal sum
Lock lock
Spell abc
Freeze freeze-row-column
Zoom zoom-in
Gridlines grid-dots
Theme palette
Margins box-margin
Orient file-orientation
SheetRtl text-direction-rtl
Paper file
PrintArea crop
Script code
Pen ballpen
Share share-2
Search search
Settings settings
Appearance brightness-half
Sheet file-spreadsheet
SheetList list
Book book
Folder folder
Header layout-navbar
Footer layout-bottombar
PageNumber file-digit
PageCount files
Calendar calendar
Clock clock
FileName file-text
Back arrow-left
NewFile file-plus
OpenFolder folder-open
Info info-circle
Print printer
""")

WORD = mapping("""
paste clipboard-text
cut scissors
copy copy
painter paint
bold bold
italic italic
underline underline
strike strikethrough
charborder text-size
enclose circle-letter-a
subscript subscript
superscript superscript
grow text-increase
shrink text-decrease
case letter-case
clear clear-formatting
phonetic language-hiragana
highlight highlight
fontcolor letter-a
effects text-color
fontdialog arrow-down-right
bullets list
numbering list-numbers
multilevel list-tree
outdent indent-decrease
indent indent-increase
sort sort-ascending-letters
pilcrow pilcrow
paragraphLayout text-resize
alignLeft align-left
alignCenter align-center
alignRight align-right
justify align-justified
textLtr text-direction-ltr
textRtl text-direction-rtl
lineSpacing spacing-vertical
shading bucket-droplet
borders border-bottom
find search
replace replace
select pointer
dictate microphone
editor text-spellcheck
spelling abc
styles text-size
stylesPane layout-sidebar-right
coverPage file-description
blankPage file-plus
pageBreak page-break
drawTable table-shortcut
table table
picture photo
onlinePicture photo-search
shapes shape
shapeEffects shadow
icons category
models3d cube
smartArt sitemap
addShape square-rounded-plus
promote arrow-up
demote arrow-down
textPane layout-sidebar-left-expand
smartArtColors palette
resetGraphic restore
chart chart-bar
changeChartType chart-infographic
chartData table
chartTitle text-caption
legend list-details
dataLabels tags
screenshot screenshot
video movie
link link
bookmark bookmark
crossRef file-symlink
comment message
newComment message-plus
header layout-navbar
footer layout-bottombar
pageNumber file-digit
textBox text-size
quickParts components
wordArt typography
textFill text-color
textOutline text-outline
transform text-orientation
dropCap text-size
signature writing-sign
dateTime calendar-time
object box
equation math-pi
symbol omega
pen ballpen
pencil pencil
eraser eraser
thickness line-height
lasso lasso
inkToShape shape
inkToMath math-symbols
canvas artboard
replay player-play
addPen pencil-plus
replayRewind player-skip-back
replayPlay player-play
replayPause player-pause
replayForward player-skip-forward
themes palette
colors color-swatch
fonts letter-case
paraSpacing spacing-vertical
effectsDesign sparkles
setDefault circle-check
watermark rubber-stamp
pageColor bucket-droplet
pageBorders border-outer
margins box-margin
orientation file-orientation
size dimensions
columns columns-2
breaks page-break
lineNumbers list-numbers
hyphenation text-wrap
position float-center
wrapText text-wrap
bringForward layers-selected
sendBackward layers-selected-bottom
selectionPane layout-sidebar-right
align layout-align-center
group layers-linked
rotate rotate-clockwise
indentLeft indent-increase
indentRight indent-decrease
spaceBefore spacing-vertical
spaceAfter spacing-vertical
toc list-details
addText text-plus
updateTable table-import
update refresh
footnote subscript
endnote superscript
nextFootnote arrow-down
showNotes notes
researcher book-2
docPrefs settings
unlinkCitations unlink
addNote note
citation quote
sources books
bibliography books
caption text-caption
tableOfFigures list-details
markEntry bookmark-plus
index list-search
markCitation bookmark-plus
tableOfAuthorities list-details
envelope mail
labels tag
mailMerge mail-forward
recipients users
editRecipients user-edit
mergeField text-plus
addressBlock address-book
greetingLine text-caption
rules list-check
matchFields arrows-exchange
highlightFields highlight
preview eye
next chevron-right
previous chevron-left
first chevrons-left
last chevrons-right
finish mail-check
checkErrors file-alert
thesaurus vocabulary
wordCount numbers
readAloud volume
accessibility accessible
altText photo-edit
translate language
language language
deleteComment message-x
prevComment message-2
nextComment message-forward
showComments messages
resolve message-check
trackChanges file-pencil
markup pencil
reviewingPane layout-sidebar-right
accept file-check
reject file-x
prevChange chevron-left
nextChange chevron-right
compare files
combine layers-union
protect shield-lock
restrict lock
blockAuthors user-cancel
hideInk pencil-off
readMode book
printLayout file-text
webLayout browser
outline list-tree
draft align-left
focus focus-centered
immersive book-2
vertical layout-list
sideToSide layout-columns
ruler ruler-2
gridlines grid-dots
navPane layout-sidebar-left-expand
zoom zoom-in
zoomIn zoom-in
zoomOut zoom-out
zoom100 zoom-scan
onePage file
multiplePages files
pageWidth arrows-horizontal
darkMode moon
interfaceTheme brightness-half
newWindow app-window
arrangeAll layout-grid
split layout-rows
sideBySide layout-columns
syncScroll arrows-down-up
switchWindows apps
macros code
documentTemplate file-settings
properties file-settings
info info-circle
insertAbove row-insert-top
insertBelow row-insert-bottom
insertLeft column-insert-left
insertRight column-insert-right
deleteTable table-minus
merge arrows-minimize
splitCells columns-2
splitTable table-row
autofit arrows-horizontal
distributeRows layout-distribute-vertical
distributeCols layout-distribute-horizontal
rowHeight arrow-autofit-height
colWidth arrow-autofit-width
cellAlign align-box-center-middle
textDirection text-orientation
cellMargins box-padding
repeatHeader table-row
toText table-export
formula math-function
selectTable table-options
draw pencil
borderPainter border-style
save device-floppy
undo arrow-back-up
redo arrow-forward-up
search search
share share-2
user user-circle
close x
dropdown chevron-down
more dots
launcher arrow-down-right
pin pin
plus plus
minus minus
check check
chevronLeft chevron-left
chevronRight chevron-right
chevronUp chevron-up
chevronDown chevron-down
mediaPlay player-play
mediaPause player-pause
mediaStop player-stop
mediaPrev player-skip-back
mediaNext player-skip-forward
pastCitation history
chevronDoubleRight chevrons-right
addins apps
discord message-circle
open folder-open
print printer
alignText align-box-center-middle
textBoxLink link
textBoxUnlink unlink
folder folder
file file
homeFolder folder
outlinePromote indent-decrease
outlineDemote indent-increase
outlineTop chevrons-left
outlineBody align-left
outlineUp arrow-up
outlineDown arrow-down
outlineExpand plus
outlineCollapse minus
closeOutline layout-off
help help-circle
ccRichText text-size
ccPlainText letter-t
ccPicture photo
ccGallery library-photo
ccCheckBox checkbox
ccComboBox list-details
ccDropDown list
ccDate calendar
ccRepeat repeat
designMode geometry
""")


def render_helper():
    return '''
/// Rasterize the embedded SVG at the current display density; egui caches by URI and size.
/// A white source stroke lets one texture serve light, dark, disabled and selected states.
fn paint_svg(p: &Painter, rect: Rect, source: (&'static str, &'static [u8]), color: Color32) {
    let side = rect.width().min(rect.height());
    if side <= 0.0 || !p.is_visible() {
        return;
    }
    let rect = Rect::from_center_size(rect.center(), vec2(side, side));
    let color = if p.ctx().theme() != egui::Theme::Dark && color.r() == color.g() && color.g() == color.b() && color.r() < 100 {
        Color32::from_rgba_unmultiplied(101, 108, 118, color.a())
    } else {
        color
    };
    egui_extras::install_image_loaders(p.ctx());
    let image = egui::Image::from_bytes(source.0, source.1).fit_to_exact_size(rect.size());
    if let Ok(egui::load::TexturePoll::Ready { texture }) = image.load_for_size(p.ctx(), rect.size()) {
        p.image(texture.id, rect, Rect::from_min_max(Pos2::ZERO, pos2(1.0, 1.0)), color);
    }
}

#[cfg(all(test, not(target_arch = "wasm32")))]
mod tests {
    #[test]
    fn rounded_icons_rasterize_at_toolbar_and_retina_sizes() {
        let folder = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("assets/tabler");
        let mut count = 0;
        for entry in std::fs::read_dir(folder).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().is_none_or(|ext| ext != "svg") {
                continue;
            }
            count += 1;
            let svg = std::fs::read(&path).unwrap();
            for size in [16, 32, 64] {
                let hint = egui::SizeHint::Size { width: size, height: size, maintain_aspect_ratio: true };
                let image = egui_extras::image::load_svg_bytes_with_size(&svg, hint, &Default::default()).unwrap();
                assert_eq!(image.size, [size as usize, size as usize], "{}", path.display());
                assert!(image.pixels.iter().any(|pixel| pixel.a() > 0), "empty icon: {}", path.display());
                // Transparent surroundings allow every theme/state to tint the same source.
                assert!(image.pixels.iter().any(|pixel| pixel.a() == 0), "opaque icon background: {}", path.display());
            }
        }
        assert!(count >= 100);
    }
}
'''


def lookup(entries, word=False):
    lines = ["macro_rules! svg {", "    ($name:literal) => {", '        (concat!("bytes://myai/tabler/", $name, ".svg"), include_bytes!(concat!("../assets/tabler/", $name, ".svg")) as &[u8])', "    };", "}", ""]
    lines.append("fn source(name: &str) -> (&'static str, &'static [u8]) {" if word else "fn source(icon: Icon) -> (&'static str, &'static [u8]) {")
    lines.append("    match name {" if word else "    match icon {")
    for key, value in entries.items():
        key = f'"{key}"' if word else f"Icon::{key}"
        lines.append(f'        {key} => svg!("{value}"),')
    if word:
        lines.append('        _ => svg!("file"),')
    lines.extend(["    }", "}", ""])
    return "\n".join(lines)


def vendor(repo, package, names):
    dest = repo / "crates/ui-egui/assets/tabler"
    dest.mkdir(parents=True, exist_ok=True)
    names = sorted(set(names))
    for name in names:
        svg = (package / "icons/outline" / f"{name}.svg").read_text()
        svg = svg.replace('stroke="currentColor"', 'stroke="#ffffff"').replace('stroke-width="2"', 'stroke-width="1.75"')
        (dest / f"{name}.svg").write_text(svg)
    (dest / "LICENSE").write_bytes((package / "LICENSE").read_bytes())
    attribution = repo / "ATTRIBUTION.md"
    text = attribution.read_text()
    # This generated section is replaceable on repeated runs without touching other entries.
    text = text.split("\n## MyAI Office rounded toolbar icons\n")[0].rstrip()
    rows = ["", "## MyAI Office rounded toolbar icons", "", f"Tabler Icons {VERSION}: upstream SVG path geometry, white stroke for theme tinting, 1.75px stroke.", "", "| Asset | Author | Source | Licence | Notes |", "|---|---|---|---|---|"]
    for name in names:
        rows.append(f"| `crates/ui-egui/assets/tabler/{name}.svg` | Paweł Kuna / Tabler contributors | https://github.com/tabler/tabler-icons/tree/v{VERSION}/icons/outline/{name}.svg | MIT | Rounded toolbar icon; see bundled LICENSE |")
    rows.append(f"| `crates/ui-egui/assets/tabler/LICENSE` | Paweł Kuna / Tabler contributors | https://github.com/tabler/tabler-icons/blob/v{VERSION}/LICENSE | MIT | Upstream copyright and licence |")
    attribution.write_text(text + "\n" + "\n".join(rows) + "\n")


def prepare(package):
    if json.loads((package / "package.json").read_text())["version"] != VERSION:
        raise SystemExit(f"Expected @tabler/icons {VERSION}")
    missing = sorted({name for name in [*GRID.values(), *WORD.values()] if not (package / "icons/outline" / f"{name}.svg").exists()})
    if missing:
        raise SystemExit("Unavailable upstream icons: " + ", ".join(missing))
    grid = ROOT / "gridcraft"
    word = ROOT / "wordcraft"
    grid_path = grid / "crates/ui-egui/src/icons.rs"
    grid_text = grid_path.read_text()
    if "pub fn paint_document(" not in grid_text:
        variants = set(re.findall(r"^    (\w+),$", grid_text.split("struct G")[0], re.M))
        if variants != GRID.keys():
            raise SystemExit(f"Grid mapping mismatch: {variants ^ GRID.keys()}")
        grid_text = grid_text.replace("pub fn paint(p:", "pub fn paint_document(p:", 1)
        grid_text = grid_text.replace("//! GridCraft's icon set, drawn in code on a 16×16 design grid (original artwork; see\n//! ATTRIBUTION.md). Large ribbon icons use the same drawings at 32×32 with accent colours.", "//! Rounded Tabler toolbar icons (MIT, see ATTRIBUTION.md).\n//! Original document-icon artwork stays in `paint_document` so existing workbook art is unchanged.")
    marker = "/// Icons offered by Insert › Icons, by name."
    if "/// Theme-aware rounded toolbar icon." in grid_text:
        grid_text = grid_text[:grid_text.index("/// Theme-aware rounded toolbar icon.")] + grid_text[grid_text.index(marker):]
    new = '''/// Theme-aware rounded toolbar icon.
pub fn paint(p: &Painter, rect: Rect, icon: Icon, c: Color32) {
    if matches!(icon, Icon::DecInc | Icon::DecDec) {
        let side = rect.width().min(rect.height());
        let number = Rect::from_center_size(rect.center() - vec2(0.0, side * 0.15), vec2(side, side * 0.72));
        paint_svg(p, number, source(icon), c);
        let badge = Rect::from_center_size(rect.center() + vec2(side * 0.22, side * 0.3), vec2(side * 0.45, side * 0.45));
        paint_svg(p, badge, source(if icon == Icon::DecInc { Icon::Plus } else { Icon::Minus }), c);
    } else {
        paint_svg(p, rect, source(icon), c);
    }
}

''' + lookup(GRID) + render_helper() + "\n"
    grid_text = grid_text.replace(marker, new + marker)
    grid_path.write_text(grid_text)
    word_path = word / "crates/ui-egui/src/icons.rs"
    word_text = word_path.read_text()
    if "fn paint_svg(" not in word_text:
        keys = set(re.findall(r'"([\w]+)"', "\n".join(line.split("=>")[0] for line in word_text.splitlines() if re.match(r'        ".*=>', line))))
        if keys != WORD.keys():
            raise SystemExit(f"Word mapping mismatch: {keys ^ WORD.keys()}")
    library = word_text[word_text.index("/// Draw an Insert › Icons library icon"):]
    word_text = '''//! Rounded Tabler toolbar icons (MIT, see ATTRIBUTION.md).
//! Insert › Icons document artwork is kept in `library` and is not changed by toolbar styling.

use egui::{Color32, Painter, Pos2, Rect, Shape, Stroke, pos2, vec2};

/// Paint one semantic toolbar icon; callers retain the existing command and hit target.
pub fn paint(p: &Painter, r: Rect, name: &str, c: Color32, accent: Color32) {
    let color = if matches!(name, "pen" | "pencil" | "addPen") { accent } else { c };
    paint_svg(p, r, source(name), color);
}

''' + lookup(WORD, word=True) + render_helper() + "\n" + library
    word_path.write_text(word_text)
    vendor(grid, package, GRID.values())
    vendor(word, package, WORD.values())
    print(f"Grid: {len(GRID)} toolbar names / {len(set(GRID.values()))} assets")
    print(f"Word: {len(WORD)} toolbar names / {len(set(WORD.values()))} assets")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    prepare(parser.parse_args().package)
