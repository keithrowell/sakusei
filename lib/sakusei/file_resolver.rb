# frozen_string_literal: true

module Sakusei
  # Resolves file references in markdown and concatenates them
  class FileResolver
    INCLUDE_PATTERN = /<!--\s*@include\s+(\S+)\s*-->/

    def initialize(source_file)
      @source_file = source_file
      @source_dir = File.dirname(source_file)
      @resolved_files = Set.new
    end

    def resolve
      content = File.read(@source_file)
      resolve_includes(content, @source_file)
    end

    private

    def resolve_includes(content, parent_file)
      content.gsub(INCLUDE_PATTERN) do |match|
        file_ref = Regexp.last_match(1)
        resolved_path = resolve_path(file_ref, parent_file)

        next match unless resolved_path
        next '' if @resolved_files.include?(resolved_path)

        @resolved_files.add(resolved_path)

        file_content = File.read(resolved_path)
        # Recursively resolve includes in the included file
        resolve_includes(file_content, resolved_path)
      end
    end

    def resolve_path(file_ref, parent_file)
      # Handle absolute paths
      if file_ref.start_with?('/')
        return File.exist?(file_ref) ? file_ref : nil
      end

      # Handle relative paths from the parent file's directory
      parent_dir = File.dirname(parent_file)
      full_path = File.expand_path(file_ref, parent_dir)

      return full_path if File.exist?(full_path)

      # Try with .md extension
      full_path_with_ext = "#{full_path}.md"
      return full_path_with_ext if File.exist?(full_path_with_ext)

      nil
    end
  end
end
