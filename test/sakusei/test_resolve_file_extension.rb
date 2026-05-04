# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestResolveFileExtension < TestCase
    def setup
      @temp_dir = temp_dir
    end

    def write(name)
      path = File.join(@temp_dir, name)
      File.write(path, '# hi')
      path
    end

    def test_returns_path_unchanged_when_file_exists
      path = write('doc.md')
      assert_equal path, Sakusei.resolve_file_extension(path)
    end

    def test_appends_md_extension
      write('doc.md')
      assert_equal File.join(@temp_dir, 'doc.md'),
                   Sakusei.resolve_file_extension(File.join(@temp_dir, 'doc'))
    end

    def test_appends_markdown_extension
      write('doc.markdown')
      assert_equal File.join(@temp_dir, 'doc.markdown'),
                   Sakusei.resolve_file_extension(File.join(@temp_dir, 'doc'))
    end

    def test_appends_text_extension
      write('doc.text')
      assert_equal File.join(@temp_dir, 'doc.text'),
                   Sakusei.resolve_file_extension(File.join(@temp_dir, 'doc'))
    end

    def test_md_takes_priority_when_multiple_exist
      write('doc.md')
      write('doc.markdown')
      assert_equal File.join(@temp_dir, 'doc.md'),
                   Sakusei.resolve_file_extension(File.join(@temp_dir, 'doc'))
    end

    def test_returns_input_unchanged_when_no_extension_found
      input = File.join(@temp_dir, 'nonexistent')
      assert_equal input, Sakusei.resolve_file_extension(input)
    end

    def test_leaves_existing_extension_alone
      input = '/some/path.txt'
      assert_equal input, Sakusei.resolve_file_extension(input)
    end

    def test_leaves_glob_alone
      input = '*.md'
      assert_equal input, Sakusei.resolve_file_extension(input)
    end

    def test_leaves_directory_alone
      assert_equal @temp_dir, Sakusei.resolve_file_extension(@temp_dir)
    end

    def test_handles_nil_and_empty
      assert_nil Sakusei.resolve_file_extension(nil)
      assert_equal '', Sakusei.resolve_file_extension('')
    end
  end
end
