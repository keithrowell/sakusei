# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestHtmlConverter < TestCase
    FakePack = Struct.new(:config, :stylesheet, :header, :footer)

    def test_build_command_includes_as_html_flag
      pack = FakePack.new(nil, nil, nil, nil)
      converter = HtmlConverter.new('# hi', pack)
      cmd = converter.send(:build_command, '/tmp/in.md', '/tmp', ['--as-html'])

      assert_includes cmd, '--as-html'
      assert_equal 'npx', cmd.first
      assert_equal 'md-to-pdf', cmd[1]
      assert_equal '/tmp/in.md', cmd.last
    end

    def test_build_command_includes_base_stylesheet
      pack = FakePack.new(nil, nil, nil, nil)
      converter = HtmlConverter.new('# hi', pack)
      cmd = converter.send(:build_command, '/tmp/in.md', '/tmp', ['--as-html'])

      assert_includes cmd, '--stylesheet'
      assert(cmd.any? { |a| a.is_a?(String) && a.end_with?('base.css') })
    end

    def test_build_command_includes_pack_stylesheet_when_present
      pack = FakePack.new(nil, '/path/to/style.css', nil, nil)
      converter = HtmlConverter.new('# hi', pack)
      cmd = converter.send(:build_command, '/tmp/in.md', '/tmp', ['--as-html'])

      assert_includes cmd, '/path/to/style.css'
    end

    def test_image_paths_extracts_relative_only
      pack = FakePack.new(nil, nil, nil, nil)
      content = <<~MD
        ![local](images/a.png)
        ![remote](https://example.com/b.png)
        <img src="images/c.jpg">
        <img src="data:image/png;base64,xx">
        <img src="/abs/d.png">
      MD
      converter = HtmlConverter.new(content, pack)
      paths = converter.send(:image_paths)

      assert_equal %w[images/a.png images/c.jpg].sort, paths.sort
    end

    def test_page_chrome_prefix_concatenates_header_and_footer
      header_path = File.join(temp_dir, 'header.html')
      footer_path = File.join(temp_dir, 'footer.html')
      File.write(header_path, '<div class="h">H</div>')
      File.write(footer_path, '<div class="f">F</div>')

      pack = FakePack.new(nil, nil, header_path, footer_path)
      converter = HtmlConverter.new('# body', pack)
      prefix = converter.send(:page_chrome_prefix)

      assert_includes prefix, 'class="h"'
      assert_includes prefix, 'class="f"'
    end
  end
end
