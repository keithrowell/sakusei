# frozen_string_literal: true

require 'shellwords'
require 'json'
require 'open3'

module Sakusei
  # Processes Vue components at build time using a single Node.js process per build.
  # Requires Node.js with @vue/server-renderer, @vue/compiler-sfc, and vue@3 installed.
  class VueProcessor
    VUE_COMPONENT_PATTERN = /<vue-component\s+([^>]+)(?:\s*\/>|>(.*?)<\/vue-component>)/m

    INSTALL_INSTRUCTIONS = <<~MSG
      Vue components detected but dependencies not found.

      To use Vue components, install the required npm packages:

        npm install @vue/server-renderer @vue/compiler-sfc vue@3

      Or initialize a new package.json first:

        npm init -y
        npm install @vue/server-renderer @vue/compiler-sfc vue@3
    MSG

    def initialize(content, base_dir, style_pack: nil)
      @content = content
      @base_dir = base_dir
      @style_pack = style_pack
    end

    def process
      return @content unless vue_components_present?
      raise Error, INSTALL_INSTRUCTIONS unless vue_renderer_available?

      ensure_style_pack_deps_installed

      jobs = []
      content_with_placeholders = first_pass(@content, jobs)
      return content_with_placeholders if jobs.empty?

      results = render_batch(jobs)
      result_map = results.each_with_object({}) { |r, h| h[r['id']] = r }

      all_css = []
      output = content_with_placeholders.gsub(/<!-- sakusei-vue-(\d+) -->/) do
        id = Regexp.last_match(1).to_i
        result = result_map[id]
        all_css << result['css'] if result&.fetch('css', '')&.length&.positive?
        result ? result['html'] : '<!-- Vue component render error -->'
      end

      if all_css.any?
        "<style>\n#{all_css.join("\n\n")}\n</style>\n\n#{output}"
      else
        output
      end
    end

    def self.available?
      system('which node > /dev/null 2>&1') && vue_renderer_installed?
    end

    private

    def vue_components_present?
      @content.match?(VUE_COMPONENT_PATTERN)
    end

    def vue_renderer_available?
      self.class.available?
    end

    def self.vue_renderer_installed?
      check_cmd = "cd '#{Dir.pwd}' && node -e \"try { require('@vue/server-renderer'); require('@vue/compiler-sfc'); process.exit(0); } catch(e) { process.exit(1); }\" 2>/dev/null"
      system(check_cmd)
    end

    # First pass: replace each <vue-component> tag with a placeholder and populate jobs array.
    def first_pass(content, jobs)
      content.gsub(VUE_COMPONENT_PATTERN) do |_match|
        attrs = parse_attributes(Regexp.last_match(1))
        slot_content = Regexp.last_match(2)
        component_name = attrs.delete('name')
        component_file = find_component_file(component_name)

        id = jobs.length
        jobs << {
          'id' => id,
          'componentFile' => component_file || '',
          'props' => attrs,
          'slotHtml' => slot_content ? markdown_to_html(slot_content.strip) : '',
          'nodeModulesDir' => node_modules_dir_for(component_file)
        }

        "<!-- sakusei-vue-#{id} -->"
      end
    end

    # Send all jobs to Node.js in one call via stdin/stdout.
    def render_batch(jobs)
      stdout, stderr, status = Open3.capture3('node', vue_renderer_script, stdin_data: jobs.to_json)
      raise Error, "Vue renderer failed: #{stderr.strip}" unless status.success?

      JSON.parse(stdout)
    rescue JSON::ParserError => e
      raise Error, "Vue renderer returned invalid JSON: #{e.message}"
    end

    def node_modules_dir_for(component_file)
      return nil if component_file.nil? || component_file.empty?

      if @style_pack&.components_dir && component_file.start_with?(@style_pack.components_dir)
        File.join(@style_pack.path, 'node_modules')
      else
        local_nm = File.join(@base_dir, 'node_modules')
        Dir.exist?(local_nm) ? local_nm : nil
      end
    end

    def find_component_file(name)
      local_paths = [
        File.join(@base_dir, 'components', "#{name}.vue"),
        File.join(@base_dir, "#{name}.vue"),
        File.join(@base_dir, 'vue_components', "#{name}.vue")
      ]
      local = local_paths.find { |p| File.exist?(p) }
      return local if local

      if @style_pack&.components_dir
        pack_file = File.join(@style_pack.components_dir, "#{name}.vue")
        return pack_file if File.exist?(pack_file)
      end

      nil
    end

    def vue_renderer_script
      File.expand_path('../vue_renderer.js', __FILE__)
    end

    def parse_attributes(attrs_string)
      attrs = {}
      return attrs if attrs_string.nil? || attrs_string.empty?

      attrs_string.scan(/(\w+)=("(?:[^"\\]|\\.)*"|'(?:[^'\\]|\\.)*')/) do |key, quoted_value|
        value = quoted_value[1..-2]
        value = value.gsub('\\"', '"').gsub("\\'", "'")
        attrs[key] = value
      end

      attrs
    end

    def style_pack_needs_install?(style_pack)
      return false unless style_pack&.components_dir
      return false unless File.exist?(File.join(style_pack.path, 'package.json'))
      !Dir.exist?(File.join(style_pack.path, 'node_modules'))
    end

    def ensure_style_pack_deps_installed
      return unless style_pack_needs_install?(@style_pack)
      $stderr.puts "Installing style pack dependencies for '#{@style_pack.name}'..."
      result = system('npm', 'install', '--prefix', @style_pack.path)
      raise Error, "npm install failed for style pack '#{@style_pack.name}'. Check #{@style_pack.path}." unless result
    end

    def markdown_to_html(markdown)
      return '' if markdown.nil? || markdown.empty?

      cmd = "echo #{Shellwords.escape(markdown)} | npx marked --stdin 2>/dev/null"
      html = `#{cmd}`

      ($?.success? && !html.empty?) ? html.strip : markdown
    end
  end
end
