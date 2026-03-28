# frozen_string_literal: true

require 'set'

module Sakusei
  class StylePack
    STYLE_PACKS_DIR = 'style_packs'
    SAKUSEI_DIR = '.sakusei'

    attr_reader :name, :path, :config, :stylesheet, :header, :footer

    # Path to the base CSS that is always applied before style pack CSS
    def self.base_stylesheet
      File.expand_path('../templates/base.css', __dir__)
    end

    def initialize(path, name = nil)
      @path = path
      @name = name || File.basename(path)
      load_files
    end

    # Discover style pack by walking up the directory tree
    def self.discover(start_dir, requested_name = nil)
      sakusei_path = find_sakusei_dir(start_dir)

      if sakusei_path
        packs_dir = File.join(sakusei_path, STYLE_PACKS_DIR)
        return load_from_path(packs_dir, requested_name) if Dir.exist?(packs_dir)
      end

      # Fall back to default style pack
      default_path = File.expand_path('../templates/default_style_pack', __dir__)
      new(default_path, 'default')
    end

    # Initialize a new style pack
    def self.init(directory, name)
      sakusei_path = File.join(directory, SAKUSEI_DIR)
      pack_path = File.join(sakusei_path, STYLE_PACKS_DIR, name)

      FileUtils.mkdir_p(pack_path)

      # Copy default templates
      default_path = File.expand_path('../templates/default_style_pack', __dir__)
      FileUtils.cp_r(Dir.glob("#{default_path}/*"), pack_path)

      pack_path
    end

    def components_dir
      dir = File.join(@path, 'components')
      Dir.exist?(dir) ? dir : nil
    end

    def list_components
      return [] unless components_dir
      Dir.glob(File.join(components_dir, '*.vue')).sort.map do |file|
        {
          name: File.basename(file, '.vue'),
          description: self.class.extract_docs_description(file),
          path: file
        }
      end
    end

    def self.extract_docs_description(file)
      content = File.read(file)
      match = content.match(/<docs>\s*\n\s*(.+)/)
      match ? match[1].strip : nil
    end

    # Find a component by name across style packs and local directories
    def self.find_component(start_dir, component_name)
      # Search in style packs
      sakusei_path = find_sakusei_dir(start_dir)
      if sakusei_path
        packs_dir = File.join(sakusei_path, STYLE_PACKS_DIR)
        if Dir.exist?(packs_dir)
          Dir.glob(File.join(packs_dir, '*')).select { |f| File.directory?(f) }.each do |pack_path|
            component_file = File.join(pack_path, 'components', "#{component_name}.vue")
            if File.exist?(component_file)
              pack = new(pack_path)
              return pack.extract_component_info(component_file)
            end
          end
        end
      end

      # Search in local ./components directory
      local_component = File.join(Dir.pwd, 'components', "#{component_name}.vue")
      if File.exist?(local_component)
        return extract_component_info(local_component, 'local')
      end

      # Search in default style pack
      default_path = File.expand_path('../templates/default_style_pack', __dir__)
      default_component = File.join(default_path, 'components', "#{component_name}.vue")
      if File.exist?(default_component)
        pack = new(default_path, 'default')
        return pack.extract_component_info(default_component)
      end

      nil
    end

    # Extract full component information from a Vue file
    def self.extract_component_info(file, pack_name = nil)
      pack_name ||= File.basename(File.dirname(File.dirname(file)))
      content = File.read(file)

      # Extract docs section
      docs_match = content.match(/<docs>(.+?)<\/docs>/m)
      docs = docs_match ? docs_match[1].strip : nil

      # Extract template section
      template_match = content.match(/<template>(.+?)<\/template>/m)
      template = template_match ? template_match[1].strip : nil

      # Extract script section
      script_match = content.match(/<script(?:\s+setup)?>(.+?)<\/script>/m)
      script = script_match ? script_match[1].strip : nil

      # Extract style section
      style_match = content.match(/<style(?:\s+scoped)?>(.+?)<\/style>/m)
      style = style_match ? style_match[1].strip : nil

      # Parse props from script
      props = parse_props(script) if script

      # Generate usage example
      usage = generate_usage(File.basename(file, '.vue'), props, template)

      {
        name: File.basename(file, '.vue'),
        description: docs ? docs.lines.first&.strip : nil,
        full_description: docs,
        path: file,
        pack_name: pack_name,
        template: template,
        script: script,
        style: style,
        props: props,
        usage: usage
      }
    end

    # Instance method wrapper for extract_component_info
    def extract_component_info(file)
      self.class.extract_component_info(file, @name)
    end

    private_class_method def self.parse_props(script)
      props = []

      # Match defineProps with object syntax
      props_match = script.match(/defineProps\(\{(.+?)\}\)/m)
      if props_match
        props_block = props_match[1]
        # Parse each property
        props_block.scan(/(\w+):\s*\{([^}]+)\}/).each do |name, config|
          prop = { name: name, required: false }
          if config.include?('required: true')
            prop[:required] = true
          elsif config.include?('default:')
            default_match = config.match(/default:\s*([^,\n]+)/)
            prop[:default] = default_match[1].strip if default_match
          end
          if config.include?('type:')
            type_match = config.match(/type:\s*(\w+)/)
            prop[:type] = type_match[1] if type_match
          end
          props << prop
        end
      end

      # Match defineProps with array syntax: defineProps(['name', 'other'])
      array_match = script.match(/defineProps\(\[\s*([^\]]+)\s*\]\)/)
      if array_match
        array_match[1].scan(/['"]([^'"]+)['"]/).each do |name|
          props << { name: name[0], required: true }
        end
      end

      props
    end

    private_class_method def self.generate_usage(name, props, template)
      return "<#{name} />" unless props&.any?

      attrs = props.map do |prop|
        if prop[:required]
          "#{prop[:name]}=\"...\""
        elsif prop[:default]
          "#{prop[:name]}=\"#{prop[:default].gsub(/['"]/, '')}\""
        else
          "#{prop[:name]}=\"...\""
        end
      end

      "<#{name} #{attrs.join(' ')} />"
    end

    # List all available style packs
    def self.list_available(start_dir = '.')
      packs = []

      # Find all .sakusei directories walking up from start_dir
      current = File.expand_path(start_dir)
      visited_dirs = Set.new

      loop do
        sakusei_path = File.join(current, SAKUSEI_DIR)
        if Dir.exist?(sakusei_path) && !visited_dirs.include?(sakusei_path)
          visited_dirs.add(sakusei_path)
          packs_dir = File.join(sakusei_path, STYLE_PACKS_DIR)
          if Dir.exist?(packs_dir)
            Dir.glob(File.join(packs_dir, '*')).select { |f| File.directory?(f) }.each do |pack_path|
              packs << { name: File.basename(pack_path), path: pack_path }
            end
          end
        end

        parent = File.dirname(current)
        break if parent == current

        current = parent
      end

      # Add default style pack
      default_path = File.expand_path('../templates/default_style_pack', __dir__)
      packs << { name: 'default', path: default_path }

      # Remove duplicates by name (closer packs take precedence)
      seen_names = Set.new
      packs.select { |p| seen_names.add?(p[:name]) }
    end

    private

    def self.find_sakusei_dir(start_dir)
      current = File.expand_path(start_dir)

      loop do
        sakusei_path = File.join(current, SAKUSEI_DIR)
        return sakusei_path if Dir.exist?(sakusei_path)

        parent = File.dirname(current)
        break if parent == current # Reached root

        current = parent
      end

      nil
    end

    def self.load_from_path(packs_dir, requested_name)
      available_packs = Dir.glob(File.join(packs_dir, '*')).select { |f| File.directory?(f) }

      raise Error, "No style packs found in #{packs_dir}" if available_packs.empty?

      if requested_name
        pack_path = available_packs.find { |p| File.basename(p) == requested_name }
        raise Error, "Style pack '#{requested_name}' not found" unless pack_path
      elsif available_packs.length == 1
        pack_path = available_packs.first
      else
        # Interactive selection would happen here
        # For now, use the first one
        pack_path = available_packs.first
      end

      new(pack_path)
    end

    def load_files
      @config = find_file('config.js')
      @stylesheet = find_file('style.css')
      @header = find_file('header.html')
      @footer = find_file('footer.html')
    end

    def find_file(name)
      file_path = File.join(@path, name)
      File.exist?(file_path) ? file_path : nil
    end
  end

  class StylePackInitializer
    def initialize(directory, name)
      @directory = directory
      @name = name
    end

    def run
      pack_path = StylePack.init(@directory, @name)
      $stderr.puts "Installing style pack dependencies for '#{@name}'..."
      result = system('npm', 'install', '--prefix', pack_path)
      raise Sakusei::Error, "npm install failed for style pack '#{@name}'. Check #{pack_path}." unless result
      pack_path
    end
  end
end
