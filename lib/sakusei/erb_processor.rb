# frozen_string_literal: true

require 'erb'

module Sakusei
  # Processes ERB templates in markdown content
  class ErbProcessor
    def initialize(content, base_dir)
      @content = content
      @base_dir = base_dir
    end

    def process
      # Create a context object with helper methods
      context = ErbContext.new(@base_dir)

      # Process the ERB
      erb = ERB.new(@content, trim_mode: '-')
      erb.result(context.binding)
    rescue StandardError => e
      raise Error, "ERB processing error: #{e.message}"
    end

    # Context object that provides helper methods for ERB templates
    class ErbContext
      def initialize(base_dir)
        @base_dir = base_dir
      end

      def binding
        ::Kernel.binding
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
    end
  end
end
