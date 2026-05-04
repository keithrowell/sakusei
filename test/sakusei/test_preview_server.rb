# frozen_string_literal: true

require_relative '../test_helper'
require 'sakusei/preview_server'

module Sakusei
  class TestPreviewServer < TestCase
    def setup
      @temp_dir = temp_dir
      @source = File.join(@temp_dir, 'doc.md')
      File.write(@source, "# Hi\n")
    end

    def server
      @server ||= begin
        s = PreviewServer.new(@source, open: false)
        s.instance_variable_set(:@version, 5)
        s
      end
    end

    def test_inject_preview_chrome_adds_preview_script
      html = '<html><head></head><body><p>x</p></body></html>'
      result = server.send(:inject_preview_chrome, html)

      assert_includes result, '/__assets/preview.js'
      assert_includes result, '__SAKUSEI_VERSION__'
      assert_includes result, '</body>'
    end

    def test_inject_preview_chrome_inserts_preview_css_in_head
      html = '<html><head><title>x</title></head><body></body></html>'
      result = server.send(:inject_preview_chrome, html)

      assert_includes result, 'pagedjs_page'
      assert_includes result, '__sakusei_render'
      assert result.index('pagedjs_page') < result.index('</head>'),
              'preview CSS should be inserted before </head>'
    end

    def test_extract_body_inner_returns_body_content
      html = '<html><head></head><body><p>hello</p></body></html>'
      assert_equal '<p>hello</p>', server.send(:extract_body_inner, html)
    end

    def test_extract_body_inner_falls_back_when_no_body
      html = '<p>no body tag</p>'
      assert_equal html, server.send(:extract_body_inner, html)
    end

    def test_inject_preview_chrome_appends_when_no_body
      html = '<p>no body tag</p>'
      result = server.send(:inject_preview_chrome, html)

      assert_includes result, '/__assets/preview.js'
      assert_includes result, '<p>no body tag</p>'
    end

    def test_inject_preview_chrome_includes_paged_js_script_by_default
      html = '<html><head></head><body></body></html>'
      result = server.send(:inject_preview_chrome, html)

      assert_includes result, PreviewServer::PAGED_JS_CDN
    end

    def test_inject_preview_chrome_omits_paged_js_script_when_disabled
      s = PreviewServer.new(@source, open: false, paged: false)
      result = s.send(:inject_preview_chrome, '<html><head></head><body></body></html>')

      refute_includes result, PreviewServer::PAGED_JS_CDN
      assert_includes result, '/__assets/preview.js'
    end

    def test_render_error_page_includes_message_and_reload
      err = StandardError.new('boom')
      err.set_backtrace(['line1', 'line2'])
      page = server.send(:render_error_page, err)

      assert_includes page, 'Build failed'
      assert_includes page, 'boom'
      assert_includes page, '/__assets/preview.js'
    end

    def test_path_within_detects_subpath
      assert server.send(:path_within?, '/a/b/c', '/a/b')
      refute server.send(:path_within?, '/a/x', '/a/b')
    end

    def test_initializer_rejects_missing_source
      assert_raises(Error) { PreviewServer.new('/nonexistent/file.md') }
    end
  end
end
