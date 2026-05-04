# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestPageChromeTranslator < TestCase
    FakePack = Struct.new(:config, :header, :footer)

    def write_config(body)
      path = File.join(temp_dir, 'config.js')
      File.write(path, body)
      path
    end

    def make_pack(config_body)
      FakePack.new(write_config(config_body), nil, nil)
    end

    def build(pack)
      PageChromeTranslator.new(pack).build
    end

    def test_returns_empty_when_no_style_pack
      result = build(nil)
      assert_equal '', result[:css]
      assert_equal '', result[:html]
    end

    def test_returns_empty_when_no_config
      pack = FakePack.new(nil, nil, nil)
      result = build(pack)
      assert_equal '', result[:html]
    end

    def test_returns_empty_when_displayHeaderFooter_is_false
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            displayHeaderFooter: false,
            headerTemplate: '<div>H</div>',
            footerTemplate: '<div>F</div>'
          }
        };
      JS
      result = build(pack)
      assert_equal '', result[:html]
    end

    def test_emits_running_elements_for_header_and_footer_templates
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            displayHeaderFooter: true,
            headerTemplate: '<div>HEADER_BODY</div>',
            footerTemplate: '<div>FOOTER_BODY</div>'
          }
        };
      JS
      result = build(pack)

      assert_includes result[:html], '<header class="sakusei-running-header">'
      assert_includes result[:html], 'HEADER_BODY'
      assert_includes result[:html], '<footer class="sakusei-running-footer">'
      assert_includes result[:html], 'FOOTER_BODY'

      assert_includes result[:css], '.sakusei-running-header { position: running(sk_header); }'
      assert_includes result[:css], '.sakusei-running-footer { position: running(sk_footer); }'
      assert_includes result[:css], '@top-center { content: element(sk_header); }'
      assert_includes result[:css], '@bottom-center { content: element(sk_footer); }'
    end

    def test_pagenumber_and_totalpages_become_counters
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            displayHeaderFooter: true,
            footerTemplate: '<div>p<span class="pageNumber"></span>/<span class="totalPages"></span></div>'
          }
        };
      JS
      result = build(pack)

      assert_includes result[:html], 'class="sk-pn"'
      assert_includes result[:html], 'class="sk-tp"'
      assert_includes result[:css], '.sk-pn::after { content: counter(page); }'
      assert_includes result[:css], '.sk-tp::after { content: counter(pages); }'
    end

    def test_title_placeholder_is_empty_to_match_pdf
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            displayHeaderFooter: true,
            headerTemplate: '<div>before<span class="title"></span>after</div>'
          }
        };
      JS
      result = build(pack)

      assert_includes result[:html], 'before'
      assert_includes result[:html], 'after'
      refute_includes result[:html], 'class="title"'
    end

    def test_template_literal_with_interpolated_data_uri
      pack = make_pack(<<~JS)
        const dataUri = 'data:image/svg+xml;base64,AAAA';
        module.exports = {
          pdf_options: {
            displayHeaderFooter: true,
            headerTemplate: `<div><img src="${dataUri}" /></div>`
          }
        };
      JS
      result = build(pack)

      assert_includes result[:html], 'src="data:image/svg+xml;base64,AAAA"'
      refute_includes result[:html], '/__pack/data'
    end

    def test_relative_image_src_rewritten_to_pack_route
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            displayHeaderFooter: true,
            headerTemplate: '<div><img src="logo.png"></div>'
          }
        };
      JS
      result = build(pack)
      assert_includes result[:html], 'src="/__pack/logo.png"'
    end

    def test_extracts_page_size_and_margin
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            format: 'A4',
            margin: { top: '3.4cm', right: '2cm', bottom: '2cm', left: '2cm' },
            displayHeaderFooter: true,
            footerTemplate: '<div>p<span class="pageNumber"></span></div>'
          }
        };
      JS
      result = build(pack)

      assert_includes result[:css], 'size: A4;'
      assert_includes result[:css], 'margin: 3.4cm 2cm 2cm 2cm;'
    end

    def test_handles_config_js_evaluation_failure_gracefully
      pack = make_pack('this is not valid javascript {{{')
      result = build(pack)

      assert_equal '', result[:html]
    end

    def test_extracts_chrome_bg_color_into_page_pseudo_elements
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            format: 'A4',
            margin: { top: '3.4cm', right: '2cm', bottom: '2cm', left: '2cm' },
            displayHeaderFooter: true,
            headerTemplate: `
              <style>
                .header-bg {
                  position: fixed; left: 0; right: 0; top: -10cm; bottom: -10cm;
                  background: #F7F1E4;
                  z-index: -1;
                }
              </style>
              <div class="header-bg"></div>
              <div style="position:relative; z-index:1;">
                <img src="data:image/svg+xml;base64,XYZ" />
              </div>
            `,
            footerTemplate: `
              <style>
                .footer-bg {
                  position: fixed; left: 0; right: 0; top: -10cm; bottom: -10cm;
                  background: #F7F1E4;
                }
              </style>
              <div class="footer-bg"></div>
              <div>FOOTER</div>
            `
          }
        };
      JS
      result = build(pack)

      # Pseudo-element strips emitted with extracted bg color and page margins
      assert_includes result[:css], '.pagedjs_page::before'
      assert_includes result[:css], 'height: 3.4cm;'
      assert_includes result[:css], 'background: #F7F1E4;'
      assert_includes result[:css], '.pagedjs_page::after'
      assert_includes result[:css], 'height: 2cm;'

      # Negative-margin rule extends running content to full page width
      assert_includes result[:css], 'margin-left: -2cm'
      assert_includes result[:css], 'margin-right: -2cm'

      # The puppeteer-only <style> and bg div are stripped from the running HTML
      refute_includes result[:html], 'header-bg'
      refute_includes result[:html], 'footer-bg'
      refute_includes result[:html], 'position: fixed'
      # But the actual chrome content remains
      assert_includes result[:html], 'data:image/svg+xml;base64,XYZ'
      assert_includes result[:html], 'FOOTER'
    end

    def test_chrome_without_bg_emits_no_pseudo_strip
      pack = make_pack(<<~JS)
        module.exports = {
          pdf_options: {
            format: 'A4',
            margin: { top: '2cm', right: '2cm', bottom: '2cm', left: '2cm' },
            displayHeaderFooter: true,
            headerTemplate: '<div>just content</div>',
            footerTemplate: '<div>just content</div>'
          }
        };
      JS
      result = build(pack)

      refute_includes result[:css], '.pagedjs_page::before'
      refute_includes result[:css], '.pagedjs_page::after'
    end
  end
end
