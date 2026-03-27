# Sakusei

A PDF building system using Markdown, Ruby ERB, VueJS, and CSS templating.

## Overview

Sakusei is a build system for creating PDF documents from Markdown source files. It supports:

- **Markdown to PDF conversion** via `md-to-pdf`
- **ERB template evaluation** for dynamic content
- **Hierarchical style packs** for consistent document styling
- **File inclusion** for multi-file documents
- **PDF concatenation** for combining multiple documents

## Installation

```bash
# Install as a Ruby gem
gem install sakusei

# Or build from source
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
