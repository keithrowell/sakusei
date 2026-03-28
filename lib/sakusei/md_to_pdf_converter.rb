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
        # Write content to temp markdown file, prepending any page chrome from the style pack
        temp_md = File.join(temp_dir, 'input.md')
        File.write(temp_md, page_chrome_prefix + @content)

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

    def page_chrome_prefix
      return '' unless @style_pack
      %i[header footer].map do |part|
        path = @style_pack.public_send(part)
        path ? File.read(path) + "\n" : ''
      end.join
    end

    def build_command(temp_path, temp_dir)
      cmd = ['npx', 'md-to-pdf']

      # Config file
      config = @options[:config] || @style_pack.config
      cmd << '--config-file' << config if config

      # Stylesheets - base CSS first, then style pack CSS
      # This allows style packs to override base styles
      stylesheets = [StylePack.base_stylesheet]

      # Add style pack stylesheet if available
      pack_stylesheet = @options[:stylesheet] || @style_pack.stylesheet
      stylesheets << pack_stylesheet if pack_stylesheet

      stylesheets.each do |stylesheet|
        cmd << '--stylesheet' << stylesheet
      end

      # Basedir for resolving relative paths
      cmd << '--basedir' << temp_dir

      # Input file
      cmd << temp_path

      cmd.join(' ')
    end
  end
end
