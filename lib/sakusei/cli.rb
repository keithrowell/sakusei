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
    option :open, type: :boolean, default: false, desc: 'Open the PDF after building'
    def build(*files)
      raise Error, 'No input files provided' if files.empty?

      # Resolve file extensions (.md, .text, .markdown) if not provided
      resolved_files = files.map { |f| resolve_file_extension(f) }

      # Check if we have multiple files, globs, or directories
      if resolved_files.length > 1 || resolved_files.any? { |f| f.include?('*') || File.directory?(f) }
        # Multi-file build
        builder = MultiFileBuilder.new(resolved_files, options)
      else
        # Single file build
        raise Error, "File not found: #{resolved_files.first}" unless File.exist?(resolved_files.first)
        builder = Builder.new(resolved_files.first, options)
      end

      output_path = builder.build
      say "PDF created: #{output_path}", :green

      # Open the PDF if requested
      open_pdf(output_path) if options[:open]
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

    desc 'styles', 'List available style packs'
    option :directory, aliases: '-d', default: '.', desc: 'Directory to search for style packs'
    def styles
      style_packs = StylePack.list_available(options[:directory])

      if style_packs.empty?
        say 'No style packs found.', :yellow
        say "Run 'sakusei init <name>' to create a new style pack."
      else
        say 'Available style packs:', :green
        style_packs.each do |pack|
          say "  • #{pack[:name]}"
          say "    Path: #{pack[:path]}", :cyan
        end
      end
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

    # Override dispatch to treat file paths as build commands
    def self.dispatch(meth, given_args, given_opts, config)
      # If first arg is an existing file or glob pattern, treat it as a build command
      if given_args.any? && file_arg?(given_args.first)
        given_args.unshift('build')
      end
      super
    end

    def self.file_arg?(arg)
      return false if arg.nil?
      return false if arg.start_with?('-')  # Skip options

      # Check if it's a file (with or without extension), glob pattern, or directory
      File.exist?(arg) || file_with_extension?(arg) || arg.include?('*') || File.directory?(arg)
    end

    # Check if file exists with any of the supported markdown extensions
    def self.file_with_extension?(arg)
      return false if arg.nil? || arg.empty?
      return false if File.extname(arg).length > 0  # Already has an extension

      %w[.md .text .markdown].any? { |ext| File.exist?(arg + ext) }
    end

    private

    # Resolve file by trying markdown extensions if no extension provided
    def resolve_file_extension(file)
      return file if File.exist?(file)
      return file if File.directory?(file)
      return file if file.include?('*')  # Glob pattern
      return file if File.extname(file).length > 0  # Already has extension

      # Try markdown extensions
      %w[.md .text .markdown].each do |ext|
        path_with_ext = file + ext
        return path_with_ext if File.exist?(path_with_ext)
      end

      # Return original if no extension found
      file
    end

    def open_pdf(path)
      return unless File.exist?(path)

      cmd = case RbConfig::CONFIG['host_os']
            when /darwin/i  # macOS
              ['open', path]
            when /linux/i
              ['xdg-open', path]
            when /mswin|mingw|cygwin/i  # Windows
              ['start', path]
            else
              say "PDF created at: #{path}", :yellow
              return
            end

      system(*cmd)
    rescue => e
      say_error "Failed to open PDF: #{e.message}"
    end
  end
end
