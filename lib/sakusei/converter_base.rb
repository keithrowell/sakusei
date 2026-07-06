# frozen_string_literal: true

require 'fileutils'

module Sakusei
  class ConverterBase
    def initialize(content, style_pack, options = {})
      @content    = content
      @style_pack = style_pack
      @options    = options
      @source_dir = options[:source_dir]
    end

    protected

    def copy_images(temp_dir)
      return unless @source_dir

      image_paths.each do |rel_path|
        src = File.expand_path(rel_path, @source_dir)
        # Sandboxed builds must not read files outside the source directory
        # (image_paths already excludes absolute paths; this blocks ../ escapes).
        next if sandboxed? && !src.start_with?(File.expand_path(@source_dir) + File::SEPARATOR)
        next unless File.exist?(src)

        dest = File.join(temp_dir, rel_path)
        FileUtils.mkdir_p(File.dirname(dest))
        FileUtils.cp(src, dest)
      end
    end

    def sandboxed?
      !!@options[:sandboxed]
    end

    def image_paths
      paths = []
      @content.scan(/!\[[^\]]*\]\(([^)]+)\)/) { |m| paths << m[0].strip }
      @content.scan(/src="([^"]+)"/) { |m| paths << m[0].strip }
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

    def build_command(temp_md, temp_dir, extra_flags = [])
      cmd = ['npx', 'md-to-pdf']

      config = @options[:config] || @style_pack&.config
      cmd << '--config-file' << config if config

      stylesheets = [StylePack.base_stylesheet]
      pack_stylesheet = @options[:stylesheet] || @style_pack&.stylesheet
      stylesheets << pack_stylesheet if pack_stylesheet
      stylesheets.each { |s| cmd << '--stylesheet' << s }

      cmd << '--basedir' << temp_dir
      extra_flags.each { |f| cmd << f }
      cmd << temp_md
      cmd
    end
  end
end
