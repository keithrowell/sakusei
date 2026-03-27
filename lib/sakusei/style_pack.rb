# frozen_string_literal: true

module Sakusei
  class StylePack
    STYLE_PACKS_DIR = 'style_packs'
    SAKUSEI_DIR = '.sakusei'

    attr_reader :name, :path, :config, :stylesheet, :header, :footer

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
      StylePack.init(@directory, @name)
    end
  end
end
