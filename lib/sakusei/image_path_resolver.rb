# frozen_string_literal: true

require 'base64'

module Sakusei
  # Embeds local images as base64 data URIs so that Puppeteer can render them
  # regardless of HTTP server basedir or working directory. Runs after ERB
  # processing so documents can use standard relative paths (e.g. images/foo.jpg)
  # and remain previewable in any standard markdown viewer.
  #
  # Handles:
  #   - Standard markdown images:  ![alt](images/foo.jpg)
  #   - Vue component image props:  "image":"images/foo.jpg"
  #
  # Leaves http://, https://, data:, and missing files untouched.
  class ImagePathResolver
    SKIP_PATTERN = /\A(https?:|data:|\/\/)/i

    MIME_TYPES = {
      '.jpg'  => 'image/jpeg',
      '.jpeg' => 'image/jpeg',
      '.png'  => 'image/png',
      '.gif'  => 'image/gif',
      '.svg'  => 'image/svg+xml',
      '.webp' => 'image/webp'
    }.freeze

    def initialize(content, base_dir)
      @content  = content
      @base_dir = base_dir
    end

    def resolve
      content = resolve_markdown_images(@content)
      content = resolve_component_image_props(content)
      content
    end

    private

    def to_data_uri(path)
      return path if path.match?(SKIP_PATTERN)

      full_path = path.start_with?('/') ? path : File.expand_path(path, @base_dir)
      return path unless File.exist?(full_path)

      ext  = File.extname(full_path).downcase
      mime = MIME_TYPES[ext] || 'application/octet-stream'
      data = Base64.strict_encode64(File.binread(full_path))
      "data:#{mime};base64,#{data}"
    end

    def resolve_markdown_images(content)
      content.gsub(/!\[([^\]]*)\]\(([^)]+)\)/) do
        alt  = Regexp.last_match(1)
        path = Regexp.last_match(2).strip
        "![#{alt}](#{to_data_uri(path)})"
      end
    end

    def resolve_component_image_props(content)
      content.gsub(/"image"\s*:\s*"([^"]+)"/) do
        path = Regexp.last_match(1)
        "\"image\":\"#{to_data_uri(path)}\""
      end
    end
  end
end
