# 📊 MagikSheetz

A fast, self-contained spreadsheet application that runs entirely in your browser from a **single HTML file** — no build step, no server, no install. Open `index.html` and start working.

![MagikSheetz screenshot](screenshot.png)

## Features

### Files
- **Open** `.xlsx`, `.xls`, and `.csv` files (via [SheetJS](https://sheetjs.com))
- **Save** the workbook as `.xlsx` (all sheets) or the current sheet as `.csv`
- Multi-sheet workbooks with tabs (add, rename, delete, and cycle between sheets)

### Editing & formulas
- Click / double-click / `Enter` / `F2` or just start typing to edit a cell
- A **formula engine** supporting cell references (`A1`), ranges (`A1:B5`), arithmetic, comparisons, string concatenation, and functions:
  `SUM, AVERAGE, MIN, MAX, COUNT, COUNTA, PRODUCT, MEDIAN, STDEV, ROUND(UP/DOWN), ABS, SQRT, POWER, MOD, INT, IF, AND, OR, NOT, CONCAT, LEN, UPPER, LOWER, TRIM, LEFT, RIGHT, MID, COUNTIF, SUMIF, NOW, TODAY, PI`
- Circular-reference detection and error reporting (`#CIRC!`, `#ERROR!`, `#NUM!`)
- Copy / Cut / Paste — copying a formula and pasting **rewrites relative references** (A1 → B2…) like Excel, while `$`-locked parts stay fixed; tab-separated data still works to/from other apps
- Undo / Redo (up to 100 steps)

### Formatting
- Bold, italic, underline; font family & size
- **Font color** and **cell background color** pickers with a curated Dracula palette (dark tones tuned for readable row highlighting)
- Horizontal alignment
- **Number formats**: General, Number, Currency, Percent, Comma, Scientific, Date, Text — display-only, so the underlying values stay numeric for formulas
- Numeric-looking cells are auto-colored and right-aligned

### Data
- **Sort** any column ascending/descending (whole rows move together; the header row stays pinned)
- **AutoFilter** on the header row — per-column dropdowns with search, value checklists, and sort
- Insert / delete rows and columns
- Resize rows and columns by dragging header edges
- **Cross-sheet lookup / drill-down** — right-click a column to match its values against a column in another sheet; a **+** on each cell inline-expands the matching rows from that sheet
- **Export / import lookup mappings** — save the workbook's lookup configuration to a JSON file (by sheet + column header name) and re-apply it to a similar workbook

### UX
- **Frozen, auto-styled header row** and sticky column/row headers
- **Freeze columns** — right-click a column header → "Freeze columns (through X)" to pin the left columns while scrolling horizontally (independent of the frozen header row)
- **Virtualized grid** — only the visible rows are rendered, so sheets with tens of thousands of rows stay smooth
- Click-and-drag selection with edge auto-scroll; drag row/column headers to select whole rows/columns
- Right-click **context menus** for cells, headers, and sheet tabs
- Dracula dark theme throughout
- A built-in **shortcuts help panel** (hover the `?` at the end of the toolbar)

## Usage

Just open the file — that's it:

```
# clone, then open in your browser
git clone git@github.com:ultimal/magiksheetz.git
cd magiksheetz
# open index.html (double-click, or:)
start index.html      # Windows
open  index.html      # macOS
xdg-open index.html   # Linux
```

> Fully **offline** — the SheetJS library is bundled inside `index.html`, so no internet connection is required.

## Keyboard shortcuts

| Keys | Action |
|------|--------|
| Arrow keys | Move one cell |
| `Shift`+Arrows | Extend selection |
| `Tab` / `Shift`+`Tab` | Move right / left |
| `Ctrl`+`←` / `→` | Start / end of the current row |
| `Ctrl`+`↑` / `↓` | Top / bottom of the current column |
| `Ctrl`+`Home` / `End` | Go to A1 / last used cell |
| `Ctrl`+`Space` / `Shift`+`Space` | Select whole column / row |
| `Ctrl`+`A` | Select all cells |
| `Enter` / `F2` / double-click | Edit the active cell |
| `Delete` / `Backspace` | Clear contents |
| `Ctrl`+`C` / `X` / `V` | Copy / Cut / Paste |
| `Ctrl`+`B` / `I` / `U` | Bold / Italic / Underline |
| `Ctrl`+`Z` / `Ctrl`+`Y` | Undo / Redo |
| `Ctrl`+`.` / `Ctrl`+`,` | Next / previous sheet |

## Notes & limitations

- Visual styling (fonts, colors, number formats) is applied live in the app but is **not** written into exported `.xlsx`/`.csv` files with the free SheetJS build — exports contain the raw values. Persisting styles to files would require switching the save path to a library like ExcelJS.
- `.xlsx` files are fully loaded into memory (browsers can't stream a zip archive); the grid renders on demand via virtualization.

## Tech

- Plain HTML/CSS/JavaScript in one file — no framework, no bundler
- [SheetJS (xlsx)](https://sheetjs.com) bundled inline for spreadsheet file I/O (works offline)
- [Dracula](https://draculatheme.com) color palette

## License

[MIT](LICENSE) © ultimal
