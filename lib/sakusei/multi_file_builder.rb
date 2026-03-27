# frozen_string_literal: true

module Sakusei
  # Builds multiple markdown files into a single PDF with consistent page numbering
  class MultiFileBuilder
    def initialize(files, options = {})
      @files = expand_files(files)
      @options = options
      @base_dir = options[:base_dir] || Dir.pwd
    end

    def build
      raise Error, 'No files to build' if @files.empty?

      # Concatenate all markdown files
      combined_content = concatenate_files

      # Process the combined content through the normal pipeline
      temp_file = create_temp_file(combined_content)

      # Use standard Builder with the combined file
      Builder.new(temp_file, @options.merge(base_dir: @base_dir)).build
    ensure
      File.delete(temp_file) if temp_file && File.exist?(temp_file)
    end

    private

    def expand_files(files)
      expanded = []

      Array(files).each do |pattern|
        if pattern.include?('*')
          # Handle glob patterns
          matches = Dir.glob(File.expand_path(pattern, @base_dir))
          expanded.concat(matches)
        elsif File.directory?(pattern)
          # If directory, get all .md files
          expanded.concat(Dir.glob(File.join(pattern, '**', '*.md')))
        elsif File.exist?(pattern)
          expanded << File.expand_path(pattern, @base_dir)
        else
          raise Error, "File not found: #{pattern}"
        end
      end

      # Remove duplicates while preserving order
      expanded.uniq
    end

    def concatenate_files
      parts = []

      @files.each do |file|
        content = File.read(file)

        # Resolve includes within each file
        resolver = FileResolver.new(file)
        resolved = resolver.resolve

        parts << resolved

        # Add page break between files (optional)
        parts << "\n\n<div class=\"page-break\"></div>\n\n" if @options[:page_breaks]
      end

      parts.join("\n")
    end

    def create_temp_file(content)
      temp = Tempfile.new(['sakusei_multifile', '.md'])
      temp.write(content)
      temp.close
      temp.path
    end
  end
end
