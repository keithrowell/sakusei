# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestMultiFileBuilder < TestCase
    def setup
      @temp_dir = temp_dir

      # Create test markdown files
      File.write(File.join(@temp_dir, 'file1.md'), "# File 1\n\nContent from file 1.")
      File.write(File.join(@temp_dir, 'file2.md'), "# File 2\n\nContent from file 2.")
      File.write(File.join(@temp_dir, 'file3.md'), "# File 3\n\nContent from file 3.")

      # Create subdirectory with files
      subdir = File.join(@temp_dir, 'subdir')
      FileUtils.mkdir_p(subdir)
      File.write(File.join(subdir, 'sub1.md'), "## Sub 1\n\nSub content.")
    end

    def test_builds_single_file
      files = [File.join(@temp_dir, 'file1.md')]
      builder = MultiFileBuilder.new(files, base_dir: @temp_dir, output: File.join(@temp_dir, 'out.pdf'))

      # Should not raise
      assert builder
    end

    def test_expands_multiple_files
      files = [
        File.join(@temp_dir, 'file1.md'),
        File.join(@temp_dir, 'file2.md')
      ]
      builder = MultiFileBuilder.new(files, base_dir: @temp_dir)

      # Access private method for testing
      expanded = builder.send(:expand_files, files)

      assert_equal 2, expanded.length
      assert_includes expanded, File.join(@temp_dir, 'file1.md')
      assert_includes expanded, File.join(@temp_dir, 'file2.md')
    end

    def test_expands_glob_patterns
      files = [File.join(@temp_dir, 'file*.md')]
      builder = MultiFileBuilder.new(files, base_dir: @temp_dir)

      expanded = builder.send(:expand_files, files)

      assert expanded.length >= 3
      assert_includes expanded, File.join(@temp_dir, 'file1.md')
    end

    def test_concatenates_files
      files = [
        File.join(@temp_dir, 'file1.md'),
        File.join(@temp_dir, 'file2.md')
      ]
      builder = MultiFileBuilder.new(files, base_dir: @temp_dir)

      content = builder.send(:concatenate_files)

      assert_includes content, '# File 1'
      assert_includes content, '# File 2'
      assert_includes content, 'Content from file 1'
      assert_includes content, 'Content from file 2'
    end

    def test_raises_on_empty_files
      builder = MultiFileBuilder.new([], base_dir: @temp_dir)

      assert_raises(Error) do
        builder.build
      end
    end

    def test_raises_on_missing_file
      files = [File.join(@temp_dir, 'nonexistent.md')]

      assert_raises(Error) do
        MultiFileBuilder.new(files, base_dir: @temp_dir)
      end
    end
  end
end
