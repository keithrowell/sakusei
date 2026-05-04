# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require_relative 'converter_base'

module Sakusei
  # Converts markdown content to a styled HTML string by invoking
  # `npx md-to-pdf --as-html`. Used by the live preview server.
  class HtmlConverter < ConverterBase
    def convert
      Dir.mktmpdir('sakusei-html') do |temp_dir|
        temp_md = File.join(temp_dir, 'input.md')
        # Header/footer files are injected as @page margin chrome by PreviewServer.
        # Don't prepend them to the body the way MdToPdfConverter does for PDF output.
        File.write(temp_md, @content)

        copy_images(temp_dir)

        cmd = build_command(temp_md, temp_dir, ['--as-html'])
        stdout, stderr, status = Open3.capture3(*cmd)

        unless status.success?
          raise Error, "HTML conversion failed: #{stderr.strip}\n#{stdout.strip}"
        end

        html_path = File.join(temp_dir, 'input.html')
        raise Error, "md-to-pdf did not produce HTML at #{html_path}" unless File.exist?(html_path)

        File.read(html_path)
      end
    end
  end
end
