# Sakusei

**Sakusei** (作成) — from the Japanese words meaning "creation," "making," or "craft."

Like a master artisan refining their craft, Sakusei transforms raw Markdown into beautifully crafted PDF documents. Every document is an act of creation — structured, styled, and brought to life with precision.

The name embodies the philosophy behind this tool: documents aren't just generated, they're _crafted_.


## Overview

Sakusei is a build system for creating PDF documents from Markdown source files. It supports:

- **Markdown to PDF conversion** via `md-to-pdf`
- **ERB template evaluation** for dynamic content
- **Hierarchical style packs** for consistent document styling
- **File inclusion** for multi-file documents
- **PDF concatenation** for combining multiple documents


## Installation

### macOS (Homebrew)

```bash
# Add the tap and install
brew tap keithrowell/sakusei https://github.com/keithrowell/sakusei/homebrew-tap
brew install sakusei
```

### Ruby Gem

```bash
gem install sakusei
```

### Build from Source

```bash
git clone https://github.com/keithrowell/sakusei
cd sakusei
bundle install
rake install
```

**Prerequisites:**
- Ruby 3.0+
- Node.js (for md-to-pdf)
- pdfunite or pdftk (for PDF concatenation)

## Quick Start

### Build a PDF from Markdown

```bash
sakusei build document.md
```

Or simply (build is the default command):

```bash
sakusei document.md
```

Extension is optional - `.md`, `.text`, or `.markdown` will be tried:

```bash
sakusei document    # Looks for document.md, document.text, or document.markdown
```

Auto-open after building:

```bash
sakusei document.md --open
```

### Initialize a Style Pack

```bash
sakusei init my_company
```

### Concatenate PDFs

```bash
sakusei concat part1.pdf part2.pdf -o combined.pdf
```

## Style Packs

Style packs are stored in `.sakusei/style_packs/` directories. Sakusei searches for style packs by walking up the directory tree from your source file.

```
.sakusei/
└── style_packs/
    └── my_company/
        ├── config.js      # md-to-pdf configuration
        ├── style.css      # Stylesheet
        ├── header.html    # Header template
        └── footer.html    # Footer template
```

## File Inclusion

Include other markdown files in your document:

```markdown
# My Document

<!-- @include ./introduction.md -->

<!-- @include ./chapter1.md -->
```

## ERB Templates

Use ERB for dynamic content:

```markdown
# Report Generated <%= today %>

Environment: <%= env('RAILS_ENV', 'development') %>
```

## Page Breaks

### Manual Page Breaks

Insert page breaks in your markdown using HTML:

```markdown
# Chapter 1

Content here...

<div class="page-break"></div>

# Chapter 2

More content...
```

Available classes:
- `.page-break` or `.page-break-after` - Break after this element
- `.page-break-before` - Break before this element

### Automatic Keep-Together

The base stylesheet automatically prevents page breaks inside these elements:
- Tables (including rows)
- Code blocks (`<pre>`)
- Blockquotes
- Images
- Figures and captions
- Definition lists (`<dl>`, `<dt>`, `<dd>`)
- Details/summary sections
- Math blocks (KaTeX)
- Custom elements: `.admonition`, `.callout`, `.card`, `.box`

To force keep-together on any element, add the `.keep-together` class:

```markdown
<div class="keep-together">

This content will not be split across pages.

| Table | Data |
|-------|------|
| A     | 1    |
| B     | 2    |

</div>
```

## Build Scripts

Create a `.sakusei_build` file for complex builds:

```yaml
steps:
  - command: build
    files:
      - cover.md
      - content/*.md
    output: document.pdf
    style: my_company
```

## License

MIT
