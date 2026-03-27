# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestStylePreview < TestCase
    def test_preview_content_includes_all_elements
      preview = StylePreview.new
      content = StylePreview::PREVIEW_CONTENT

      # Check for all major elements
      assert_includes content, '# Style Pack Preview'
      assert_includes content, '# Heading 1'
      assert_includes content, '## Heading 2'
      assert_includes content, '**bold text**'
      assert_includes content, '*italic text*'
      assert_includes content, '`inline code`'
      assert_includes content, '- First item'  # unordered list
      assert_includes content, '1. First step'  # ordered list
      assert_includes content, '```ruby'  # code block
      assert_includes content, '> This is a blockquote'
      assert_includes content, '| Feature |'  # table
      assert_includes content, 'page-break'  # page break
    end

    def test_initializes_with_options
      preview = StylePreview.new('my_style', output: 'custom.pdf')

      assert_equal 'my_style', preview.instance_variable_get(:@style_pack_name)
      assert_equal 'custom.pdf', preview.instance_variable_get(:@output_path)
    end

    def test_default_output_path
      preview = StylePreview.new

      assert_equal 'style-preview.pdf', preview.instance_variable_get(:@output_path)
    end
  end
end
