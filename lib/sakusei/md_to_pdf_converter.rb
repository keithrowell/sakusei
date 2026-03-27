# frozen_string_literal: true

require 'tempfile'

module Sakusei
  # Converts markdown content to PDF using md-to-pdf
  class MdToPdfConverter
    def initialize(content, output_path, style_pack, options = {})
      @content = content
      @output_path = output_path
      @style_pack = style_pack
      @options = options
    end

    def convert
      # Create temp directory for working files
      Dir.mktmpdir('sakusei') do |temp_dir|
        # Write content to temp markdown file
        temp_md = File.join(temp_dir, 'input.md')
        File.write(temp_md, @content)

        # Build md-to-pdf command
        cmd = build_command(temp_md, temp_dir)

        # Execute command
        result = system(cmd)
        raise Error, 'PDF conversion failed' unless result

        # md-to-pdf outputs to input.pdf in the same directory
        temp_pdf = File.join(temp_dir, 'input.pdf')

        # Move to final destination
        FileUtils.mv(temp_pdf, @output_path)
      end

      @output_path
    end

    private

    def build_command(temp_path, temp_dir)
      cmd = ['npx', 'md-to-pdf']

      # Config file
      config = @options[:config] || @style_pack.config
      cmd << '--config-file' << config if config

      # Stylesheet
      stylesheet = @options[:stylesheet] || @style_pack.stylesheet
      cmd << '--stylesheet' << stylesheet if stylesheet

      # Basedir for resolving relative paths
      cmd << '--basedir' << temp_dir

      # Input file
      cmd << temp_path

      cmd.join(' ')
    end
  end
end
