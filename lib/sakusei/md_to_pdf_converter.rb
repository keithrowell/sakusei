# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

module Sakusei
  # Converts markdown content to PDF using md-to-pdf
  class MdToPdfConverter
    def initialize(content, output_path, style_pack, options = {})
      @content    = content
      @output_path = output_path
      @style_pack = style_pack
      @options    = options
      @source_dir = options[:source_dir]
    end

    def convert
      Dir.mktmpdir('sakusei') do |temp_dir|
        # Write processed content to temp markdown file
        temp_md = File.join(temp_dir, 'input.md')
        File.write(temp_md, page_chrome_prefix + @content)

        # Copy any local images into the temp dir, mirroring the relative structure,
        # so md-to-pdf's HTTP server can serve them by their relative paths.
        copy_images(temp_dir)

        cmd = build_command(temp_md, temp_dir)
        result = system(cmd)
        raise Error, 'PDF conversion failed' unless result

        FileUtils.mv(File.join(temp_dir, 'input.pdf'), @output_path)
      end

      @output_path
    end

    private

    # Scans content for relative image paths (markdown and HTML img src),
    # and copies each referenced file into temp_dir at the same relative path.
    def copy_images(temp_dir)
      return unless @source_dir

      image_paths.each do |rel_path|
        src = File.expand_path(rel_path, @source_dir)
        next unless File.exist?(src)

        dest = File.join(temp_dir, rel_path)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      end
    end

    # Extracts relative image paths from both markdown syntax and HTML img tags.
    def image_paths
      paths = []

      # Markdown: ![alt](path)
      @content.scan(/!\[[^\]]*\]\(([^)]+)\)/) { |m| paths << m[0].strip }

      # HTML: src="path" (covers Vue-rendered img tags)
      @content.scan(/src="([^"]+)"/) { |m| paths << m[0].strip }

      # Filter to relative paths only (skip http, https, data URIs, absolute paths)
      paths.reject { |p| p.match?(/\A(https?:|data:|\/\/)/) || p.start_with?('/') }
           .uniq
    end

    def page_chrome_prefix
      return '' unless @style_pack
      %i[header footer].map do |part|
        path = @style_pack.public_send(part)
        path ? File.read(path) + "\n" : ''
      end.join
    end

    def build_command(temp_path, temp_dir)
      cmd = ['npx', 'md-to-pdf']

      config = @options[:config] || @style_pack.config
      cmd << '--config-file' << config if config

      stylesheets = [StylePack.base_stylesheet]
      pack_stylesheet = @options[:stylesheet] || @style_pack.stylesheet
      stylesheets << pack_stylesheet if pack_stylesheet
      stylesheets.each { |s| cmd << '--stylesheet' << s }

      # Set basedir to temp_dir so relativePath resolves to /input.md,
      # making image src="images/foo.jpg" resolve to http://localhost:PORT/images/foo.jpg
      # which is served from temp_dir where we've copied the assets.
      cmd << '--basedir' << temp_dir

      cmd << temp_path
      cmd.join(' ')
    end
  end
end
