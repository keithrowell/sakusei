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
require_relative 'sakusei/vue_processor'

module Sakusei
  class Error < StandardError; end

  # Main entry point for building PDFs
  def self.build(source_file, options = {})
    Builder.new(source_file, options).build
  end
end
