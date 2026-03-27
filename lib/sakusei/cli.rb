# frozen_string_literal: true

require 'thor'

module Sakusei
  class CLI < Thor
    desc 'build FILE', 'Build PDF from markdown FILE'
    option :output, aliases: '-o', desc: 'Output PDF file path'
    option :style, aliases: '-s', desc: 'Style pack name to use'
    option :config, aliases: '-c', desc: 'Path to md-to-pdf config file'
    option :stylesheet, aliases: '-css', desc: 'Path to CSS stylesheet'
    def build(file)
      raise Error, "File not found: #{file}" unless File.exist?(file)

      builder = Builder.new(file, options)
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
