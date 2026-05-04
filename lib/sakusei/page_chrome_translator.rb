# frozen_string_literal: true

require 'date'
require 'json'
require 'open3'

module Sakusei
  # Builds the live-preview's page chrome from the style pack's PDF
  # configuration, matching what Puppeteer renders for the PDF as closely as
  # possible.
  #
  # Source of truth is `pdf_options.headerTemplate` / `footerTemplate` /
  # `format` / `margin` inside `config.js`. We evaluate `config.js` with Node
  # to expand JS template literals (e.g. `${wordmarkDataUri}`), then translate
  # the resulting HTML strings into running elements + @page CSS.
  #
  # Strategy: Puppeteer's headerTemplate / footerTemplate are arbitrary HTML
  # (with images, flex layouts, multi-column structures). CSS @page margin
  # boxes only accept a content string, not arbitrary HTML — so we use
  # CSS Paged Media's running-element mechanism instead:
  #
  #   .sakusei-running-header { position: running(sk_header); }
  #   @page { @top-center { content: element(sk_header); } }
  #
  # Placeholder rewrites (matching Puppeteer's chrome semantics):
  # - <span class="pageNumber"></span> → <span class="sk-pn"></span>, with
  #   .sk-pn::after { content: counter(page); }
  # - <span class="totalPages"></span> → <span class="sk-tp"></span>, similar
  # - <span class="title"></span> → "" (Puppeteer leaves it blank by default)
  # - <span class="date"></span> → today's date (static at build time)
  # - <span class="url"></span> → ""
  # - <img src="rel/path"> → <img src="/__pack/rel/path"> so the browser can
  #   fetch images from the style-pack directory. Data URIs and absolute
  #   URLs pass through unchanged.
  #
  # Returns { css:, html: } — caller injects css into <head>, prepends html
  # into <body>.
  class PageChromeTranslator
    HEADER_RUNNING_NAME = 'sk_header'
    FOOTER_RUNNING_NAME = 'sk_footer'
    HEADER_CLASS        = 'sakusei-running-header'
    FOOTER_CLASS        = 'sakusei-running-footer'
    PAGE_NUMBER_CLASS   = 'sk-pn'
    TOTAL_PAGES_CLASS   = 'sk-tp'

    NODE_EXTRACT_SCRIPT = <<~JS.freeze
      try {
        const c = require(process.argv[1]);
        const o = (c && c.pdf_options) || {};
        const enabled = o.displayHeaderFooter !== false;
        process.stdout.write(JSON.stringify({
          format: o.format || null,
          margin: o.margin || null,
          headerTemplate: enabled ? (o.headerTemplate || null) : null,
          footerTemplate: enabled ? (o.footerTemplate || null) : null
        }));
      } catch (e) {
        process.stderr.write(String(e && e.stack || e));
        process.exit(2);
      }
    JS

    def initialize(style_pack)
      @style_pack = style_pack
    end

    def build
      return empty_result unless @style_pack
      opts = read_pdf_options

      # Extract chrome strip backgrounds from the templates BEFORE we strip them.
      # Puppeteer's PDF chrome uses a `position: fixed; top: -10cm; bottom: -10cm`
      # div that breaks out to fill the full chrome strip. paged.js's running
      # elements live inside the @top-center / @bottom-center margin boxes which
      # are constrained to the page's content width, so the same trick covers the
      # whole page (wrong) instead of just the strip. We replicate the strip via
      # .pagedjs_page::before / ::after pseudo-elements with the extracted color.
      header_bg = extract_chrome_bg(opts[:header_template])
      footer_bg = extract_chrome_bg(opts[:footer_template])

      header_html = transform_template(opts[:header_template])
      footer_html = transform_template(opts[:footer_template])

      html = +''
      html << wrap_running(:header, header_html) if header_html && !header_html.empty?
      html << wrap_running(:footer, footer_html) if footer_html && !footer_html.empty?

      { css: build_css(opts, header_html, footer_html, header_bg, footer_bg), html: html }
    end

    private

    def empty_result
      { css: '', html: '' }
    end

    def wrap_running(kind, inner)
      class_name = kind == :header ? HEADER_CLASS : FOOTER_CLASS
      tag = kind == :header ? 'header' : 'footer'
      %(<#{tag} class="#{class_name}">#{inner}</#{tag}>)
    end

    def build_css(opts, header_html, footer_html, header_bg, footer_bg)
      pieces = []

      page_decls = []
      page_decls << "size: #{opts[:size]};" if opts[:size]
      page_decls << "margin: #{opts[:margin]};" if opts[:margin]
      page_decls << "@top-center { content: element(#{HEADER_RUNNING_NAME}); }" if header_html && !header_html.empty?
      page_decls << "@bottom-center { content: element(#{FOOTER_RUNNING_NAME}); }" if footer_html && !footer_html.empty?
      pieces << "@page { #{page_decls.join(' ')} }" unless page_decls.empty?

      pieces << ".#{HEADER_CLASS} { position: running(#{HEADER_RUNNING_NAME}); }" if header_html && !header_html.empty?
      pieces << ".#{FOOTER_CLASS} { position: running(#{FOOTER_RUNNING_NAME}); }" if footer_html && !footer_html.empty?

      pieces << ".#{PAGE_NUMBER_CLASS}::after { content: counter(page); }"
      pieces << ".#{TOTAL_PAGES_CLASS}::after { content: counter(pages); }"

      sides = opts[:margin_sides] || {}

      # Full-page-width chrome strips, sized by the page's top/bottom margins.
      if header_bg && sides['top']
        pieces << <<~CSS
          .pagedjs_page { position: relative; }
          .pagedjs_page::before {
            content: "";
            position: absolute;
            top: 0; left: 0; right: 0;
            height: #{sides['top']};
            background: #{header_bg};
            z-index: 0;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
          }
        CSS
      end

      if footer_bg && sides['bottom']
        pieces << <<~CSS
          .pagedjs_page::after {
            content: "";
            position: absolute;
            bottom: 0; left: 0; right: 0;
            height: #{sides['bottom']};
            background: #{footer_bg};
            z-index: 0;
            -webkit-print-color-adjust: exact;
            print-color-adjust: exact;
          }
        CSS
      end

      # Make the running content extend to the full page width by overflowing
      # the @top-center / @bottom-center margin box on the left and right by
      # the page's side margins. Restores the Puppeteer chrome's edge-to-edge
      # padding semantics (e.g. `padding: 0.4cm 26px 0.6cm 26px` inside the
      # template now positions content from page edges, not from inner content
      # area). Also lifts the content above the chrome strip pseudo-elements.
      if sides['left'] || sides['right']
        left = sides['left'] || '0'
        right = sides['right'] || '0'
        pieces << <<~CSS
          .pagedjs_margin-top-center > .pagedjs_margin-content > *,
          .pagedjs_margin-bottom-center > .pagedjs_margin-content > * {
            margin-left: -#{left};
            margin-right: -#{right};
            position: relative;
            z-index: 1;
          }
        CSS
      end

      pieces.join("\n")
    end

    # Spawns Node to require() config.js and emit pdf_options as JSON.
    # Returns { size:, margin:, header_template:, footer_template: }, all
    # nil-safe. On any failure, returns {} and logs to stderr.
    def read_pdf_options
      return {} unless @style_pack.config && File.exist?(@style_pack.config)

      stdout, stderr, status = Open3.capture3(
        'node', '-e', NODE_EXTRACT_SCRIPT, @style_pack.config
      )
      unless status.success?
        $stderr.puts "[sakusei-preview] could not read pdf_options from config.js: #{stderr.strip}"
        return {}
      end

      raw = JSON.parse(stdout)
      sides = raw['margin'].is_a?(Hash) ? raw['margin'] : nil
      {
        size: raw['format'],
        margin: format_margin(sides),
        margin_sides: sides,
        header_template: raw['headerTemplate'],
        footer_template: raw['footerTemplate']
      }
    rescue StandardError => e
      $stderr.puts "[sakusei-preview] failed to extract chrome from config.js: #{e.message}"
      {}
    end

    def format_margin(margin)
      return nil unless margin.is_a?(Hash)
      sides = %w[top right bottom left].map { |s| margin[s] || '0' }
      sides.join(' ')
    end

    # Heuristic: Puppeteer chrome templates often use a position-fixed
    # background div to color the chrome strip. Find the first such background
    # color so we can replicate the strip via .pagedjs_page::before / ::after.
    # Looks for either `.X-bg { ... background: <color>; ... }` in a <style>
    # block, or `<div ... style="...background: <color>...">` with a *-bg class.
    def extract_chrome_bg(template)
      return nil unless template
      if template =~ /<style\b[^>]*>[\s\S]*?\.\w+-bg\s*\{[^}]*?background:\s*([^;}]+?)\s*[;}]/m
        return Regexp.last_match(1).strip
      end
      if template =~ /<div\b[^>]*class=["'][^"']*\b\w+-bg\b[^"']*["'][^>]*style=["'][^"']*background:\s*([^;"]+)/m
        return Regexp.last_match(1).strip
      end
      nil
    end

    # Transform a Puppeteer chrome template (HTML string) into preview HTML.
    def transform_template(raw)
      return nil if raw.nil?
      s = raw.to_s.dup
      return nil if s.strip.empty?

      strip_chrome_bg_markup!(s)
      s.gsub!(/<!--.*?-->/m, '')
      s.gsub!(/<span\s+class=["']pageNumber["']\s*>\s*<\/span>/i, %(<span class="#{PAGE_NUMBER_CLASS}"></span>))
      s.gsub!(/<span\s+class=["']totalPages["']\s*>\s*<\/span>/i, %(<span class="#{TOTAL_PAGES_CLASS}"></span>))
      s.gsub!(/<span\s+class=["']title["']\s*>\s*<\/span>/i, '')
      s.gsub!(/<span\s+class=["']date["']\s*>\s*<\/span>/i, Date.today.strftime('%Y-%m-%d'))
      s.gsub!(/<span\s+class=["']url["']\s*>\s*<\/span>/i, '')
      rewrite_image_paths!(s)
      s.strip!
      s
    end

    # Remove Puppeteer-specific markup that we replicate via paged.js CSS
    # (the <style> block defining .X-bg and the empty <div class="X-bg">).
    # Leaving them in would cover the whole page in paged.js because
    # `position: fixed` resolves against .pagedjs_page, not the chrome strip.
    def strip_chrome_bg_markup!(html)
      html.sub!(/<style\b[^>]*>[\s\S]*?\.\w+-bg\s*\{[\s\S]*?\}[\s\S]*?<\/style>/m, '')
      html.gsub!(/<div\b[^>]*class=["'][^"']*\b\w+-bg\b[^"']*["'][^>]*>\s*<\/div>/m, '')
    end

    # Rewrite <img src="rel/path"> to <img src="/__pack/rel/path"> for any
    # path that looks relative (no scheme, no leading slash). Data URIs and
    # absolute URLs pass through.
    def rewrite_image_paths!(html)
      html.gsub!(/(<img\b[^>]*\bsrc=["'])([^"']+)(["'])/i) do
        prefix = Regexp.last_match(1)
        src = Regexp.last_match(2)
        suffix = Regexp.last_match(3)
        new_src = if src.match?(%r{\A(https?:|data:|/)}) then src
                  else "/__pack/#{src}"
                  end
        "#{prefix}#{new_src}#{suffix}"
      end
    end
  end
end
