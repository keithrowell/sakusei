# frozen_string_literal: true

require 'date'
require 'set'
require 'fileutils'

require_relative 'sakusei/version'
require_relative 'sakusei/cli'
require_relative 'sakusei/builder'
require_relative 'sakusei/style_pack'
require_relative 'sakusei/file_resolver'
require_relative 'sakusei/erb_processor'
require_relative 'sakusei/md_to_pdf_converter'
require_relative 'sakusei/pdf_concat'
require_relative 'sakusei/multi_file_builder'
require_relative 'sakusei/style_preview'
require_relative 'sakusei/vue_processor'
require_relative 'sakusei/html_converter'
require_relative 'sakusei/page_chrome_translator'

module Sakusei
  class Error < StandardError; end

  # Markdown extensions to auto-discover when a CLI is given a file argument
  # without an extension (e.g. `sakusei-preview ai_workflow_assessment`).
  MARKDOWN_EXTENSIONS = %w[.md .text .markdown].freeze

  # Resolve a file argument by trying known markdown extensions if no extension
  # was given. Returns the input unchanged if the file already exists, is a
  # directory, looks like a glob, or already has an extension.
  def self.resolve_file_extension(file)
    return file if file.nil? || file.empty?
    return file if File.exist?(file)
    return file if File.directory?(file)
    return file if file.include?('*')
    return file if File.extname(file).length.positive?

    MARKDOWN_EXTENSIONS.each do |ext|
      candidate = file + ext
      return candidate if File.exist?(candidate)
    end

    file
  end

  # Main entry point for building PDFs
  def self.build(source_file, options = {})
    Builder.new(source_file, options).build
  end
end
