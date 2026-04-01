# frozen_string_literal: true

require_relative 'style_pack'
require_relative 'file_resolver'
require_relative 'erb_processor'
require_relative 'vue_processor'
require_relative 'heading_wrapper'
require_relative 'md_to_pdf_converter'

module Sakusei
  class Builder
    def initialize(source_file, options = {})
      @source_file = File.expand_path(source_file)
      @options = options
      @source_dir = File.dirname(@source_file)
    end

    def build
      # 1. Discover and load style pack
      $stderr.puts "[sakusei] discovering style pack..."
      style_pack = discover_style_pack
      $stderr.puts "[sakusei] style pack: #{style_pack.name} (#{style_pack.path})"

      # 2. Resolve and concatenate file references
      $stderr.puts "[sakusei] resolving file includes..."
      resolved_content = resolve_files

      # 3. Process ERB templates
      $stderr.puts "[sakusei] processing ERB..."
      processed_content = process_erb(resolved_content)

      # 4. Process Vue components (if available)
      processed_content = process_vue(processed_content, style_pack)

      # 4.5 Wrap h2/h3 headings with their following block to prevent orphaned headings
      processed_content = wrap_headings(processed_content)

      # 5. Convert to PDF
      $stderr.puts "[sakusei] converting to PDF..."
      output_path = generate_output_path
      convert_to_pdf(processed_content, output_path, style_pack)

      $stderr.puts "[sakusei] written: #{output_path}"
      output_path
    end

    private

    def discover_style_pack
      StylePack.discover(@source_dir, @options[:style])
    end

    def resolve_files
      FileResolver.new(@source_file).resolve
    end

    def process_erb(content)
      ErbProcessor.new(content, @source_dir, source_file: @source_file).process
    end

    def process_vue(content, style_pack)
      VueProcessor.new(content, @source_dir, style_pack: style_pack).process
    end

    def wrap_headings(content)
      HeadingWrapper.new(content).wrap
    end

    def convert_to_pdf(content, output_path, style_pack)
      MdToPdfConverter.new(content, output_path, style_pack, @options).convert
    end

    def generate_output_path
      return File.expand_path(@options[:output]) if @options[:output]

      base_name = File.basename(@source_file, '.*')
      File.join(@source_dir, "#{base_name}.pdf")
    end
  end
end
