# Word / Excel rounded toolbar icons — 2026-10-17

final result: passed

Scope: replace the existing native Word/Excel toolbar icon style with the rounded,
minimal outline direction selected by the user. Button locations, command IDs,
document typography/layout and already-inserted document icon artwork are preserved.
This is a native application update, not a browser prototype.

## Source visual truth

All source images are user-provided references, not instructions or distributable assets.
Primary style reference (figure 5):
`/var/folders/sc/dqy2y37932b4ssrbbsyfd3vr0000gn/T/codex-clipboard-feba0015-e7fe-4f3e-aec4-22b61b47fe9b.png`
(84 × 238 px). The intended traits are rounded caps/joins, quiet grey strokes and open space.

Functional/recognition references:

- Word Draw: `codex-clipboard-6b5611e2-124e-4ed0-8fd9-eb362c1870dd.png`, 1450 × 272 px.
- Word Layout: `codex-clipboard-48f1d6fd-3c06-4975-bc8b-ab8c10386649.png`, 1702 × 246 px.
- Excel Insert: `codex-clipboard-78d5483b-2b23-47e9-aac0-3bd3b2c58133.png`, 1656 × 248 px.
- Excel Draw: `codex-clipboard-6cccc0c2-82ac-4865-872b-cde6ed2e44ef.png`, 972 × 268 px.

The four files above are in the same absolute temporary directory as the primary reference.
Artwork used by the implementation: Tabler Icons 3.49.0 outline SVGs, MIT,
https://github.com/tabler/tabler-icons. Paths are retained; stroke colour is white for
theme tinting and stroke width is 1.75 on the original 24 × 24 design grid.

## Implementation and normalization

Evidence directory:
`/Users/dingjunjie/Desktop/XYZ Office/MyAI Office/Build/QA/rounded-icons/`

The offscreen captures render the actual native frontends at a 1440 × 900 point
viewport and 2× density, producing 2880 × 1800 px PNGs. The additional
`excel-insert-1x.png` is 1440 × 900 px at 1×. Before/after captures use the same
viewport, language, content and active ribbon tab. Source figure 5 is a style crop
and is not treated as a full-window layout or a pixel-for-pixel icon specification.

Combined comparison inputs opened and inspected:

- `word-draw-comparison.png`
- `word-layout-comparison.png`
- `word-home-comparison.png`
- `excel-insert-comparison.png`

Each board contains both actual before/after toolbar crops, normalized from 2× to
1×, and figure 5 at its source pixel size. This is a combined comparison input,
not an inference from separate image paths. Full screenshots were also inspected
to check that document/workbook content and overall layout remained intact.
`ribbon-preview.png` combines the final Word Draw and Excel Insert ribbon captures.

Native app evidence from the final signed 0.10.1 bundle:

- `native-word-draw.png` — 2972 × 1904 px, synthetic handbook, Draw tab selected
  through the native accessibility action.
- `native-excel-home.png` — 3104 × 2024 px, synthetic sales workbook with chart UI;
  the full ribbon, workbook, sidebar and context menu were visible.

Native window captures include the macOS frame/shadow, so they are acceptance
evidence and are not used for exact viewport geometry comparisons.

## Comparison history and findings

1. Initial outline pass: [P2] light-mode large icons were too dark against the
   light toolbar compared with the quiet grey of figure 5.
   Evidence: `iteration-1-excel-insert-comparison.png` and
   `iteration-1-excel-insert.png`.
   Fix: neutral dark toolbar ink now uses RGB (101, 108, 118) in light mode.
   Accent, disabled, selected and dark-mode colours remain distinct.
2. Post-fix pass: final combined comparison boards and the 1×/2× captures show
   consistent rounded outlines, clear recognition, adequate spacing and no icon
   crop, missing glyph or new control overflow. No actionable P0/P1/P2 visual
   findings remain within this icon-refresh scope.

## Required fidelity surfaces

- Fonts/typography: UI font families, sizes, weights, labels and document fonts
  remain unchanged. Letter-like function symbols in toolbars now use library SVG
  artwork rather than depending on the selected document/system font.
- Spacing/layout rhythm: button hit targets and label placement are unchanged.
  Hover/selected backgrounds use modest rounded corners; colour indicator bars
  have rounded ends. Large and small icons share the 24-unit source grid.
- Colours/tokens: neutral grey light-mode strokes, light strokes on dark chrome,
  and the existing blue/green selection colours are consistent. Excel pens show
  their blue/black/red/yellow swatches; Word highlight shows its current colour.
- Asset quality: embedded SVGs render at current display density, load offline,
  and were checked in light/dark and 1×/2× UI captures. All 341 bundled SVG
  selections rasterize to nonempty transparent images at 16/32/64 px. SVG
  geometry is from the attributed library; there are no screenshot-cropped icons.
- Copy/content: functional names, language selection, menus and commands are
  unchanged. The task changes icon appearance, not all existing translation gaps.

## Functional verification

- GridCraft UI library: 96 tests passed.
- Word icon rasterization: passed; Word widget suite: 5 tests passed.
- Word paragraph alignment/Bold buttons retain focus and allow continued typing:
  the existing interaction test passed.
- Asset attribution checks: passed for both modules (146 / 283 total assets).
- Dependency-layer checks: passed for both modules.
- Native Word/Excel launches and rendering from final signed bundle: passed.
- `codesign --verify --deep --strict` for the final app: passed.
- Source diffs and vendor-patch reverse-apply checks: passed.

One existing broader Word interaction check still fails after clicking the
Heading 1 style tile and typing. The identical assertion also fails in an
independent baseline checkout reconstructed from the pre-refresh vendor patch:
`/tmp/myai-word-icons-baseline.fwONfu`. It is not introduced by this refresh and is
not counted as a passing test. No change to that separate behavior is claimed.

## Delivery

Local version: 0.10.1. Built and installed at `/Applications/MyAI Office.app`.
The earlier installed build is recoverable at
`/tmp/myai-office-before-rounded-icons.q6OgnO/MyAI Office.app`.
Package and update reconstruction checks for the 0.10.1 release are recorded in
`QA/verification-0.10.1.md`. They use the exact previously published 0.10.0 base.

Implementation checklist: rounded library assets, neutral colour refinement,
semantic colour swatches, theme/DPI verification, button interaction checks,
licence packaging, signed local build and installation are complete.
