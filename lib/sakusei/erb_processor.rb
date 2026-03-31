# frozen_string_literal: true

require 'erb'
require 'json'

module Sakusei
  # Processes ERB templates in markdown content
  class ErbProcessor
    def initialize(content, base_dir, source_file: nil)
      @content = content
      @base_dir = base_dir
      @source_file = source_file
    end

    def process
      # Create a context object with helper methods
      context = ErbContext.new(@base_dir, source_file: @source_file)

      # Process the ERB — setting filename makes require_relative resolve
      # relative to the source document, not the working directory.
      erb = ERB.new(@content, trim_mode: '-')
      erb.filename = @source_file if @source_file
      erb.result(context.template_binding)
    rescue StandardError => e
      raise Error, "ERB processing error: #{e.message}"
    end

    # Context object that provides helper methods for ERB templates
    class ErbContext
      def initialize(base_dir, source_file: nil)
        @base_dir = base_dir
        @source_file = source_file
      end

      # Returns the binding of this ErbContext instance so that ERB local
      # variables (e.g. <% x = 1 %>) persist across the full template evaluation
      # and helper methods (today, include_file, etc.) are callable as self.
      def template_binding
        binding
      end

      # Helper method to include file content directly
      def include_file(path)
        full_path = File.expand_path(path, @base_dir)
        File.exist?(full_path) ? File.read(full_path) : "<!-- File not found: #{path} -->"
      end

      # Helper for current date
      def today(format = '%Y-%m-%d')
        Date.today.strftime(format)
      end

      # Helper for reading environment variables
      def env(name, default = nil)
        ENV.fetch(name, default)
      end

      # Helper for executing shell commands
      def sh(command)
        `#{command}`.chomp
      end

      # Extracts document headings as a JSON array for use with the Contents component.
      # Only includes headings that appear after the Contents component tag in the file.
      # Normalises heading depth relative to h2: h2 → level 1, h3 → level 2, etc.
      #
      # Usage:
      #   <%= document_headings %>              # reads current source file
      #   <%= document_headings('./other.md') %> # reads a specific file
      def document_headings(path = nil)
        target = path ? File.expand_path(path, @base_dir) : @source_file
        return '[]' unless target && File.exist?(target)

        items = []
        past_contents = false

        File.foreach(target) do |line|
          line = line.chomp
          past_contents = true if !past_contents && line.match?(/vue-component\s+name=["']Contents["']/)
          next unless past_contents

          m = line.match(/^(#+)\s+(.+)/)
          next unless m

          raw_level = m[1].length
          next if raw_level < 2 # skip h1 document title

          title = m[2].strip
          items << { title: title, level: raw_level - 1, slug: slugify(title) }
        end

        items.to_json
      end

      private

      # Slugify matching marked's Slugger.serialize (used by md-to-pdf v3).
      # Mirrors the JS logic exactly so that href="#slug" in Contents links
      # match the id="slug" attributes that marked puts on headings.
      #
      # marked source:
      #   .toLowerCase().trim()
      #   .replace(/<[!\/a-z].*?>/ig, '')          # strip html tags
      #   .replace(/[\u2000-\u206F\u2E00-\u2E7F\'...]/g, '')  # remove punctuation
      #   .replace(/\s/g, '-')                     # each space → hyphen (NOT \s+)
      def slugify(title)
        title
          .downcase
          .strip
          .gsub(/<[!\/a-z].*?>/i, '')
          .gsub(/[\u2000-\u206F\u2E00-\u2E7F\\'!"#$%&()*+,.\/:;<=>?@\[\]^`{|}~]/, '')
          .gsub(/\s/, '-')
      end
    end
  end
end
