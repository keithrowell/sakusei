# frozen_string_literal: true

require 'thor'

module Sakusei
  class CLI < Thor
    desc 'preview [STYLE]', 'Generate a preview PDF showing all style elements'
    option :output, aliases: '-o', default: 'style-preview.pdf', desc: 'Output PDF file path'
    option :config, aliases: '-c', desc: 'Path to md-to-pdf config file'
    option :stylesheet, aliases: '-css', desc: 'Path to CSS stylesheet'
    def preview(style = nil)
      preview = StylePreview.new(style, options)
      output_path = preview.generate
      say "Style preview generated: #{output_path}", :green
    rescue Error => e
      say_error e.message
      exit 1
    end

    desc 'build FILES', 'Build PDF from markdown FILE(s). Accepts multiple files, globs, or directories.'
    option :output, aliases: '-o', desc: 'Output PDF file path'
    option :style, aliases: '-s', desc: 'Style pack name to use'
    option :config, aliases: '-c', desc: 'Path to md-to-pdf config file'
    option :stylesheet, aliases: '-css', desc: 'Path to CSS stylesheet'
    option :page_breaks, aliases: '-p', type: :boolean, default: false, desc: 'Add page breaks between files'
    def build(*files)
      raise Error, 'No input files provided' if files.empty?

      # Check if we have multiple files, globs, or directories
      if files.length > 1 || files.any? { |f| f.include?('*') || File.directory?(f) }
        # Multi-file build
        builder = MultiFileBuilder.new(files, options)
      else
        # Single file build
        raise Error, "File not found: #{files.first}" unless File.exist?(files.first)
        builder = Builder.new(files.first, options)
      end

      output_path = builder.build
      say "PDF created: #{output_path}", :green
    rescue Error => e
      say_error e.message
      exit 1
    end

    desc 'init [NAME]', 'Initialize a new style pack'
    option :directory, aliases: '-d', default: '.', desc: 'Directory to create style pack in'
    def init(name = 'default')
      StylePackInitializer.new(options[:directory], name).run
      say "Style pack '#{name}' created in #{options[:directory]}/.sakusei/style_packs/#{name}", :green
    rescue Error => e
      say_error e.message
      exit 1
    end

    desc 'concat FILES', 'Concatenate multiple PDF files'
    option :output, aliases: '-o', required: true, desc: 'Output PDF file path'
    def concat(*files)
      raise Error, 'No input files provided' if files.empty?

      PdfConcat.new(files, options[:output]).concat
      say "PDFs concatenated: #{options[:output]}", :green
    rescue Error => e
      say_error e.message
      exit 1
    end

    desc 'version', 'Show version'
    def version
      say "Sakusei #{Sakusei::VERSION}"
    end
    map %w[--version -v] => :version

    default_task :help
  end
end
