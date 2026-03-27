# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestVueProcessor < TestCase
    def setup
      @temp_dir = temp_dir
    end

    def test_processes_simple_component_tag
      content = '<vue-component name="Test" />'
      processor = VueProcessor.new(content, @temp_dir)

      # Should return content (may be modified or kept as-is depending on availability)
      result = processor.process
      assert_kind_of String, result
    end

    def test_processes_component_with_slot
      content = '<vue-component name="Test">Slot content</vue-component>'
      processor = VueProcessor.new(content, @temp_dir)

      result = processor.process
      assert_kind_of String, result
    end

    def test_no_components_returns_unchanged
      content = "# Markdown without Vue\n\nJust regular text."
      processor = VueProcessor.new(content, @temp_dir)

      result = processor.process
      assert_equal content, result
    end

    def test_finds_component_file
      # Create a components directory with a .vue file
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'Test.vue'), '<template><div>Test</div></template>')

      content = '<vue-component name="Test" />'
      processor = VueProcessor.new(content, @temp_dir)

      # Should find the component file
      file_path = processor.send(:find_component_file, 'Test')
      assert_equal File.join(components_dir, 'Test.vue'), file_path
    end

    def test_returns_nil_for_missing_component
      content = '<vue-component name="Missing" />'
      processor = VueProcessor.new(content, @temp_dir)

      file_path = processor.send(:find_component_file, 'Missing')
      assert_nil file_path
    end

    def test_escape_slot_content
      content = '<vue-component name="Test">Hello "World"</vue-component>'
      processor = VueProcessor.new(content, @temp_dir)

      escaped = processor.send(:escape_slot_content, 'Hello "World"')
      require 'base64'
      decoded = Base64.strict_decode64(escaped)
      assert_equal 'Hello "World"', decoded
    end

    def test_escape_nil_content
      content = '<vue-component name="Test" />'
      processor = VueProcessor.new(content, @temp_dir)

      escaped = processor.send(:escape_slot_content, nil)
      assert_equal '', escaped
    end
  end
end
