# frozen_string_literal: true

module Sakusei
  # Processes Vue components at build time
  # Requires Node.js with @vue/server-renderer installed
  class VueProcessor
    VUE_COMPONENT_PATTERN = /<vue-component\s+name="([^"]+)"(?:\s*\/>|>(.*?)<\/vue-component>)/m

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
    end

    def process
      return @content unless vue_components_present?

      # Check if Vue renderer is available
      unless vue_renderer_available?
        raise Error, INSTALL_INSTRUCTIONS
      end

      @content.gsub(VUE_COMPONENT_PATTERN) do |match|
        component_name = Regexp.last_match(1)
        slot_content = Regexp.last_match(2)

        render_component(component_name, slot_content)
      end
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

    def render_component(name, slot_content = nil)
      component_file = find_component_file(name)

      unless component_file
        return "<!-- Vue component '#{name}' not found -->"
      end

      # Call Node.js script to render the component
      cmd = [
        'node',
        vue_renderer_script,
        component_file,
        escape_slot_content(slot_content)
      ].join(' ')

      # Capture stdout only (stderr goes to console for debugging)
      result = `#{cmd} 2>/dev/null`

      if $?.success?
        result
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
      require 'base64'
      Base64.strict_encode64(content.strip)
    end
  end
end
