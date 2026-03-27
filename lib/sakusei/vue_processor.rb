# frozen_string_literal: true

require 'shellwords'
require 'json'
require 'base64'

module Sakusei
  # Processes Vue components at build time
  # Requires Node.js with @vue/server-renderer installed
  class VueProcessor
    # Pattern to match vue-component tags with optional props
    # Supports: <vue-component name="Comp" title="foo" />
    # Or: <vue-component name="Comp" title="foo">slot content</vue-component>
    VUE_COMPONENT_PATTERN = /<vue-component\s+([^>]+)(?:\s*\/>|>(.*?)<\/vue-component>)/m

    INSTALL_INSTRUCTIONS = <<~MSG
      Vue components detected but dependencies not found.

      To use Vue components, install the required npm packages:

        npm install @vue/server-renderer vue@3

      Or initialize a new package.json first:

        npm init -y
        npm install @vue/server-renderer vue@3
    MSG

    def initialize(content, base_dir)
      @content = content
      @base_dir = base_dir
      @collected_css = []
    end

    def process
      return @content unless vue_components_present?

      # Check if Vue renderer is available
      unless vue_renderer_available?
        raise Error, INSTALL_INSTRUCTIONS
      end

      # Process all vue-component tags and collect CSS
      result = @content.gsub(VUE_COMPONENT_PATTERN) do |match|
        attrs_string = Regexp.last_match(1)
        slot_content = Regexp.last_match(2)

        # Parse attributes
        attrs = parse_attributes(attrs_string)
        component_name = attrs.delete('name')

        render_component(component_name, slot_content, attrs)
      end

      # Inject collected CSS as a style block at the beginning
      if @collected_css.any?
        css_block = "<style>\n#{@collected_css.join("\n\n")}\n</style>\n\n"
        result = css_block + result
      end

      result
    end

    def self.available?
      system('which node > /dev/null 2>&1') &&
        vue_renderer_installed?
    end

    private

    def vue_components_present?
      @content.match?(VUE_COMPONENT_PATTERN)
    end

    def vue_renderer_available?
      self.class.available?
    end

    def self.vue_renderer_installed?
      # Check if @vue/server-renderer is available from the project directory
      check_cmd = "cd '#{Dir.pwd}' && node -e \"try { require('@vue/server-renderer'); process.exit(0); } catch(e) { process.exit(1); }\" 2>/dev/null"
      system(check_cmd)
    end

    def render_component(name, slot_content = nil, props = {})
      component_file = find_component_file(name)

      unless component_file
        return "<!-- Vue component '#{name}' not found -->"
      end

      # Process slot content through markdown first
      # (md-to-pdf doesn't process markdown inside HTML tags)
      html_content = slot_content ? markdown_to_html(slot_content.strip) : ''

      # Call Node.js script to render the component
      cmd = [
        'node',
        vue_renderer_script,
        component_file,
        escape_slot_content(html_content),
        escape_props(props)
      ].join(' ')

      # Capture stdout only (stderr goes to console for debugging)
      result = `#{cmd} 2>/dev/null`

      if $?.success?
        begin
          # Parse JSON response
          data = JSON.parse(result)

          # Collect CSS if present
          @collected_css << data['css'] if data['css'] && !data['css'].empty?

          # Return the HTML
          data['html']
        rescue JSON::ParserError
          # Fallback: return raw result if not valid JSON
          result
        end
      else
        "<!-- Vue component '#{name}' render error (check console) -->"
      end
    end

    def find_component_file(name)
      # Look for .vue files in components directory or relative paths
      possible_paths = [
        File.join(@base_dir, 'components', "#{name}.vue"),
        File.join(@base_dir, "#{name}.vue"),
        File.join(@base_dir, 'vue_components', "#{name}.vue")
      ]

      possible_paths.find { |p| File.exist?(p) }
    end

    def vue_renderer_script
      File.expand_path('../vue_renderer.js', __FILE__)
    end

    def escape_slot_content(content)
      return '' if content.nil?

      # Base64 encode to safely pass through shell
      Base64.strict_encode64(content.strip)
    end

    # Parse HTML-style attributes from a string
    # e.g., name="InfoCard" title="My Title" → { 'name' => 'InfoCard', 'title' => 'My Title' }
    def parse_attributes(attrs_string)
      attrs = {}
      return attrs if attrs_string.nil? || attrs_string.empty?

      # Match name="value" or name='value' patterns
      attrs_string.scan(/(\w+)=["']([^"']*)["']/) do |key, value|
        attrs[key] = value
      end

      attrs
    end

    # Escape props hash for passing to shell script
    def escape_props(props)
      return '' if props.nil? || props.empty?

      Base64.strict_encode64(props.to_json)
    end

    # Convert markdown to HTML so it renders properly inside Vue component slots
    # (md-to-pdf doesn't process markdown inside HTML tags)
    def markdown_to_html(markdown)
      return '' if markdown.nil? || markdown.empty?

      # Use marked (common markdown parser) via npx
      cmd = "echo #{Shellwords.escape(markdown)} | npx marked --stdin 2>/dev/null"
      html = `#{cmd}`

      if $?.success? && !html.empty?
        html.strip
      else
        # Fallback: return original markdown if conversion fails
        markdown
      end
    end
  end
end
