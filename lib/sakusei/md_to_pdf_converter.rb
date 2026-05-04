# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative 'converter_base'

module Sakusei
  # Converts markdown content to PDF using md-to-pdf
  class MdToPdfConverter < ConverterBase
    def initialize(content, output_path, style_pack, options = {})
      super(content, style_pack, options)
      @output_path = output_path
    end

    def convert
      Dir.mktmpdir('sakusei') do |temp_dir|
        # Write processed content to temp markdown file
        temp_md = File.join(temp_dir, 'input.md')
        File.write(temp_md, page_chrome_prefix + @content)

        # Copy any local images into the temp dir, mirroring the relative structure,
        # so md-to-pdf's HTTP server can serve them by their relative paths.
        copy_images(temp_dir)

        cmd = build_command(temp_md, temp_dir).join(' ')
        result = system(cmd)
        raise Error, 'PDF conversion failed' unless result

        FileUtils.mv(File.join(temp_dir, 'input.pdf'), @output_path)
      end

      @output_path
    end
  end
end
