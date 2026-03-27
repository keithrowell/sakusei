# frozen_string_literal: true

require_relative 'style_pack'
require_relative 'file_resolver'
require_relative 'erb_processor'
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
      style_pack = discover_style_pack

      # 2. Resolve and concatenate file references
      resolved_content = resolve_files

      # 3. Process ERB templates
      processed_content = process_erb(resolved_content)

      # 4. Convert to PDF
      output_path = generate_output_path
      convert_to_pdf(processed_content, output_path, style_pack)

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
      ErbProcessor.new(content, @source_dir).process
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
