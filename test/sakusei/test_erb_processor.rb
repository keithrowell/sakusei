# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestErbProcessor < TestCase
    def setup
      @temp_dir = temp_dir
    end

    def test_processes_simple_erb
      content = "Hello <%= 'World' %>!"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_equal "Hello World!", result
    end

    def test_today_helper
      content = "Date: <%= today %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, Date.today.strftime('%Y-%m-%d')
    end

    def test_today_with_custom_format
      content = "Date: <%= today('%Y') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, Date.today.year.to_s
    end

    def test_env_helper
      ENV['SAKUSEI_TEST'] = 'test_value'
      content = "Value: <%= env('SAKUSEI_TEST') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, 'test_value'
    ensure
      ENV.delete('SAKUSEI_TEST')
    end

    def test_env_helper_with_default
      content = "Value: <%= env('NONEXISTENT_VAR', 'default') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, 'default'
    end

    def test_include_file_helper
      test_file = File.join(@temp_dir, 'test.txt')
      File.write(test_file, 'Included content')

      content = "<%= include_file('test.txt') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, 'Included content'
    end

    def test_handles_erb_errors
      content = "<%= undefined_method %>"
      processor = ErbProcessor.new(content, @temp_dir)

      assert_raises(Error) do
        processor.process
      end
    end
  end
end
