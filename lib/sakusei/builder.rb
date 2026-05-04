# frozen_string_literal: true

require_relative 'style_pack'
require_relative 'file_resolver'
require_relative 'erb_processor'
require_relative 'image_path_resolver'
require_relative 'vue_processor'
require_relative 'heading_wrapper'
require_relative 'md_to_pdf_converter'
require_relative 'html_converter'

module Sakusei
  class Builder
    def initialize(source_file, options = {})
      @source_file = File.expand_path(source_file)
      @options = options
      @source_dir = File.dirname(@source_file)
      @file_resolver = nil
    end

    attr_reader :source_file, :source_dir

    # Files that contributed to the most recent build (source + @include partials).
    # Populated after #build, #build_html, or #build_processed_content runs.
    def resolved_input_files
      files = [@source_file]
      files.concat(@file_resolver.resolved_files.to_a) if @file_resolver
      files.uniq
    end

    def build
      style_pack, processed_content = build_processed_content
      $stderr.puts "[sakusei] converting to PDF..."
      output_path = generate_output_path
      convert_to_pdf(processed_content, output_path, style_pack)
      $stderr.puts "[sakusei] written: #{output_path}"
      output_path
    end

    # Run the full pipeline up to (but not including) PDF conversion, then
    # render the processed markdown to a styled HTML string via md-to-pdf --as-html.
    # Returns [html_string, style_pack].
    def build_html
      style_pack, processed_content = build_processed_content
      html = HtmlConverter.new(processed_content, style_pack, @options.merge(source_dir: @source_dir)).convert
      [html, style_pack]
    end

    private

    def build_processed_content
      $stderr.puts "[sakusei] discovering style pack..."
      style_pack = discover_style_pack
      $stderr.puts "[sakusei] style pack: #{style_pack.name} (#{style_pack.path})"

      $stderr.puts "[sakusei] resolving file includes..."
      resolved_content = resolve_files

      $stderr.puts "[sakusei] processing ERB..."
      processed_content = process_erb(resolved_content)

      processed_content = expand_break_syntax(processed_content)
      processed_content = process_vue(processed_content, style_pack)
      processed_content = wrap_headings(processed_content)

      [style_pack, processed_content]
    end

    def discover_style_pack
      StylePack.discover(@options[:source_dir] || @source_dir, @options[:style])
    end

    def resolve_files
      @file_resolver = FileResolver.new(@source_file)
      @file_resolver.resolve
    end

    def process_erb(content)
      ErbProcessor.new(content, @source_dir, source_file: @source_file).process
    end

    def resolve_image_paths(content)
      ImagePathResolver.new(content, @source_dir).resolve
    end

    def process_vue(content, style_pack)
      VueProcessor.new(content, @source_dir, style_pack: style_pack).process
    end

    def expand_break_syntax(content)
      content.gsub(/::break::/, '<div class="page-break"></div>')
    end

    def wrap_headings(content)
      HeadingWrapper.new(content).wrap
    end

    def convert_to_pdf(content, output_path, style_pack)
      MdToPdfConverter.new(content, output_path, style_pack, @options.merge(source_dir: @source_dir)).convert
    end

    def generate_output_path
      return File.expand_path(@options[:output]) if @options[:output]

      base_name = File.basename(@source_file, '.*')
      File.join(@source_dir, "#{base_name}.pdf")
    end
  end
end
