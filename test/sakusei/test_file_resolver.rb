# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestFileResolver < TestCase
    def setup
      @temp_dir = temp_dir

      # Create test files
      File.write(File.join(@temp_dir, 'main.md'), "# Main\n\n<!-- @include ./sub.md -->")
      File.write(File.join(@temp_dir, 'sub.md'), "## Subsection\n\nContent here.")
    end

    def test_resolves_single_file
      main_file = File.join(@temp_dir, 'main.md')
      resolver = FileResolver.new(main_file)
      result = resolver.resolve

      assert_includes result, '# Main'
      assert_includes result, '## Subsection'
      assert_includes result, 'Content here.'
    end

    def test_resolves_nested_includes
      # Create nested include
      File.write(File.join(@temp_dir, 'nested.md'), "<!-- @include ./sub.md -->\n\nNested content.")

      nested_file = File.join(@temp_dir, 'nested.md')
      resolver = FileResolver.new(nested_file)
      result = resolver.resolve

      # Should only include sub.md once (prevents circular includes)
      assert_includes result, '## Subsection'
      assert_includes result, 'Nested content.'
    end

    def test_handles_missing_include_gracefully
      File.write(File.join(@temp_dir, 'broken.md'), "# Test\n\n<!-- @include ./nonexistent.md -->")

      broken_file = File.join(@temp_dir, 'broken.md')
      resolver = FileResolver.new(broken_file)
      result = resolver.resolve

      # Should keep the include comment if file not found
      assert_includes result, '# Test'
    end
  end
end
