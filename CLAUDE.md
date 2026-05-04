# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

Run all tests:

```bash
bundle exec rake test
```

Run a single test file:

```bash
ruby -Ilib -Itest test/sakusei/test_builder_break_syntax.rb
```

Build and install the gem locally:

```bash
rake install
```

Build a PDF from one of the examples:

```bash
bundle exec sakusei build examples/getting-started.md
```

Live-preview a markdown file in the browser:

```bash
bundle exec sakusei-preview examples/getting-started.md
```

## Architecture

Sakusei ships two CLIs:

- `bin/sakusei` (Thor) — the build CLI that produces PDFs.
- `bin/sakusei-preview` — a separate live-render binary backed by `Sakusei::PreviewServer`. Watches the source file, its `@include` partials, the active style pack, and referenced images; re-renders to HTML on change via `npx md-to-pdf --as-html` and reloads the browser tab. Loads paged.js from a CDN so `@page`/`page-break-*` rules are visible as document pages. Use this for fast iteration; use `sakusei build` for the final PDF.

Both CLIs share the multi-stage build pipeline.

### Build pipeline

`Builder#build` in `lib/sakusei/builder.rb` runs these steps in order:

1. **StylePack.discover** — walks up the directory tree from the source file, looking for `.sakusei/style_packs/<name>/` at each level. Falls back to the built-in pack at `lib/templates/default_style_pack/`.
2. **FileResolver** — resolves `<!-- @include ./file.md -->` directives and concatenates the content.
3. **ErbProcessor** — evaluates ERB in the markdown. Available helpers: `today(format)`, `env(name, default)`, `sh(command)`, `include_file(path)`, `image_path(relative_path)`, `document_headings(path)`.
4. **expand_break_syntax** — expands `::break::` shorthand to `<div class="page-break"></div>`.
5. **VueProcessor** — finds `<vue-component name="Foo" prop="value" />` tags, renders them server-side via `lib/sakusei/vue_renderer.js` using Node.js + `@vue/server-renderer` in a single batched call.
6. **HeadingWrapper** — wraps h2/h3 headings with their immediately following content block in keep-together divs to prevent orphaned headings.
7. **MdToPdfConverter** / **HtmlConverter** — both extend `ConverterBase` (`lib/sakusei/converter_base.rb`) and assemble the `npx md-to-pdf` command with config, stylesheets, and header/footer from the style pack. `MdToPdfConverter` runs it in a temp dir and returns the PDF path; `HtmlConverter` adds `--as-html` and returns the HTML string (used by the live preview server).

`Builder#build_html` runs stages 1–6 and ends in `HtmlConverter`, sharing the pipeline with `Builder#build` so the preview matches the final PDF.

`MultiFileBuilder` handles glob patterns and multiple source files, delegating to `Builder` per file and concatenating results.

### Style packs

A style pack is a directory containing:

- `config.js` — md-to-pdf configuration (Puppeteer/Chrome options)
- `style.css` — stylesheet applied after `lib/templates/base.css`
- `header.html`, `footer.html` — Puppeteer page chrome injected before the markdown content
- `components/*.vue` — Vue 3 SFCs, rendered server-side at build time (optional)
- `package.json` — if present, npm dependencies are auto-installed on first use

`lib/templates/base.css` is always applied first and provides keep-together rules for tables, code blocks, blockquotes, images, and common custom classes.

Style pack discovery walks up the directory tree from the source file; a named pack can live in any ancestor's `.sakusei/` directory. The default pack in `lib/templates/default_style_pack/` is the final fallback.

### Vue component system

Components are referenced in markdown as `<vue-component name="MyComponent" prop="value" />`. `VueProcessor` finds all such tags in a first pass, replaces them with numbered placeholders, then sends a single JSON batch to `vue_renderer.js` via stdin. The JS renderer uses `@vue/server-renderer` to render each component and returns HTML + scoped CSS back as JSON. Scoped CSS is injected as a `<style>` block at the top of the document.

Component resolution order: local `./components/<Name>.vue` → style pack `components/<Name>.vue`.

Vue components support named slots via `<template #slotname>...</template>` inside the tag. Slot content is converted from Markdown to HTML before being passed to the renderer.

### Tests

Tests use Minitest. Fixtures live in `test/fixtures/` (markdown samples and stub style packs). `test/test_vue_renderer.js` is a standalone Node.js test for the JS renderer. The base test class `Sakusei::TestCase` provides `fixtures_dir` and a `temp_dir` that auto-cleans on teardown.
