# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestStylePack < TestCase
    def setup
      @fixtures_dir = File.join(fixtures_dir, 'style_packs', 'default')
      @temp_dir = temp_dir
    end

    def test_style_pack_initialization
      pack = StylePack.new(@fixtures_dir, 'default')

      assert_equal 'default', pack.name
      assert_equal @fixtures_dir, pack.path
    end

    def test_style_pack_loads_config
      pack = StylePack.new(@fixtures_dir, 'default')

      refute_nil pack.config
      assert File.exist?(pack.config)
    end

    def test_style_pack_loads_stylesheet
      pack = StylePack.new(@fixtures_dir, 'default')

      refute_nil pack.stylesheet
      assert File.exist?(pack.stylesheet)
    end

    def test_components_dir_returns_nil_when_no_dir
      pack = StylePack.new(@fixtures_dir, 'default')
      assert_nil pack.components_dir
    end

    def test_components_dir_returns_path_when_exists
      components = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components)
      pack = StylePack.new(@temp_dir, 'test')
      assert_equal components, pack.components_dir
    end

    def test_list_components_returns_empty_when_no_dir
      pack = StylePack.new(@fixtures_dir, 'default')
      assert_equal [], pack.list_components
    end

    def test_list_components_returns_component_names
      components = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components)
      File.write(File.join(components, 'BarChart.vue'), '<template><div></div></template>')
      File.write(File.join(components, 'AlertBox.vue'), '<template><div></div></template>')

      pack = StylePack.new(@temp_dir, 'test')
      names = pack.list_components.map { |c| c[:name] }
      assert_equal ['AlertBox', 'BarChart'], names
    end

    def test_list_components_extracts_docs_description
      components = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components)
      File.write(File.join(components, 'Chart.vue'), <<~VUE)
        <docs>
        A chart component for visualizing data.

        More details here.
        </docs>
        <template><div></div></template>
      VUE
      File.write(File.join(components, 'Plain.vue'), '<template><div></div></template>')

      pack = StylePack.new(@temp_dir, 'test')
      chart = pack.list_components.find { |c| c[:name] == 'Chart' }
      plain = pack.list_components.find { |c| c[:name] == 'Plain' }
      assert_equal 'A chart component for visualizing data.', chart[:description]
      assert_nil plain[:description]
    end

    def test_extract_docs_description_returns_first_line
      file = File.join(@temp_dir, 'Comp.vue')
      File.write(file, <<~VUE)
        <docs>
        First line of docs.

        Second paragraph.
        </docs>
        <template><div></div></template>
      VUE
      assert_equal 'First line of docs.', StylePack.extract_docs_description(file)
    end

    def test_extract_docs_description_returns_nil_when_no_docs_block
      file = File.join(@temp_dir, 'Comp.vue')
      File.write(file, '<template><div></div></template>')
      assert_nil StylePack.extract_docs_description(file)
    end

    def test_initializer_runs_npm_install
      skip 'npm not available' unless system('which npm > /dev/null 2>&1')

      initializer = StylePackInitializer.new(@temp_dir, 'testpack')
      initializer.run

      pack_path = File.join(@temp_dir, '.sakusei', 'style_packs', 'testpack')
      assert Dir.exist?(File.join(pack_path, 'node_modules')), 'Expected node_modules after init'
    end
  end

  class TestStylePackDefault < TestCase
    def setup
      @temp_dir = temp_dir
      @sakusei_dir = File.join(@temp_dir, '.sakusei')
      FileUtils.mkdir_p(@sakusei_dir)
    end

    # ── helpers ──────────────────────────────────────────────────────────────

    def make_pack(base_dir, *names)
      names.each do |name|
        pack_path = File.join(base_dir, '.sakusei', StylePack::STYLE_PACKS_DIR, name)
        FileUtils.mkdir_p(pack_path)
        File.write(File.join(pack_path, 'config.js'), 'module.exports = {}')
      end
    end

    # ── set_default / config.yml ─────────────────────────────────────────────

    def test_set_default_writes_config_yml
      make_pack(@temp_dir, 'mypack')
      StylePack.set_default(@temp_dir, 'mypack')

      config_path = File.join(@sakusei_dir, 'config.yml')
      assert File.exist?(config_path), 'config.yml should be created'
      data = YAML.safe_load(File.read(config_path))
      assert_equal 'mypack', data['default_style']
    end

    def test_set_default_merges_with_existing_config_keys
      make_pack(@temp_dir, 'mypack')
      config_path = File.join(@sakusei_dir, 'config.yml')
      File.write(config_path, YAML.dump('other_key' => 'preserved'))

      StylePack.set_default(@temp_dir, 'mypack')

      data = YAML.safe_load(File.read(config_path))
      assert_equal 'mypack', data['default_style']
      assert_equal 'preserved', data['other_key'], 'Existing keys must not be wiped'
    end

    def test_set_default_raises_when_no_sakusei_dir
      dir = File.join(@temp_dir, 'no_sakusei_here')
      FileUtils.mkdir_p(dir)
      assert_raises(Error) { StylePack.set_default(dir, 'anything') }
    end

    def test_set_default_raises_when_style_not_found
      make_pack(@temp_dir, 'existing')
      assert_raises(Error) { StylePack.set_default(@temp_dir, 'nonexistent') }
    end

    # ── discover uses configured default ────────────────────────────────────

    def test_discover_uses_configured_default_when_no_explicit_name
      make_pack(@temp_dir, 'alpha', 'beta')
      StylePack.set_default(@temp_dir, 'beta')

      pack = StylePack.discover(@temp_dir)
      assert_equal 'beta', pack.name
    end

    def test_discover_explicit_name_overrides_configured_default
      make_pack(@temp_dir, 'alpha', 'beta')
      StylePack.set_default(@temp_dir, 'beta')

      pack = StylePack.discover(@temp_dir, 'alpha')
      assert_equal 'alpha', pack.name
    end

    def test_discover_falls_back_to_first_pack_when_no_default_configured
      make_pack(@temp_dir, 'alpha', 'beta')
      # No set_default called — no config.yml

      pack = StylePack.discover(@temp_dir)
      # Should get some pack from the available list, not the built-in default
      assert_includes %w[alpha beta], pack.name
    end

    def test_discover_returns_builtin_default_when_configured_as_default
      # Even without a style_packs dir, user can explicitly pin to 'default'
      YAML.dump('default_style' => 'default').tap do |yml|
        File.write(File.join(@sakusei_dir, 'config.yml'), yml)
      end

      pack = StylePack.discover(@temp_dir)
      assert_equal 'default', pack.name
    end

    # ── list_available marks the configured default ──────────────────────────

    def test_list_available_marks_configured_default
      make_pack(@temp_dir, 'alpha', 'beta')
      StylePack.set_default(@temp_dir, 'alpha')

      packs = StylePack.list_available(@temp_dir)
      alpha = packs.find { |p| p[:name] == 'alpha' }
      beta  = packs.find { |p| p[:name] == 'beta' }

      assert alpha[:default],  'alpha should be marked as default'
      refute beta[:default],   'beta should not be marked as default'
    end

    def test_list_available_no_default_when_config_absent
      make_pack(@temp_dir, 'alpha', 'beta')

      packs = StylePack.list_available(@temp_dir)
      assert packs.none? { |p| p[:default] }, 'No pack should be default when config absent'
    end

    def test_list_available_can_mark_builtin_default_pack
      StylePack.set_default(@temp_dir, 'default')

      packs = StylePack.list_available(@temp_dir)
      builtin = packs.find { |p| p[:name] == 'default' }
      assert builtin[:default], 'Built-in default pack should be marked when configured'
    end

    # ── tree-walk: nearest .sakusei wins ────────────────────────────────────

    def test_discover_uses_nearest_sakusei_config
      # Parent has 'parent_pack' set as default
      parent_dir = @temp_dir
      make_pack(parent_dir, 'parent_pack')
      StylePack.set_default(parent_dir, 'parent_pack')

      # Child has its own .sakusei with 'child_pack' as default
      child_dir = File.join(parent_dir, 'subdir')
      FileUtils.mkdir_p(child_dir)
      make_pack(child_dir, 'child_pack')
      StylePack.set_default(child_dir, 'child_pack')

      pack = StylePack.discover(child_dir)
      assert_equal 'child_pack', pack.name, 'Nearest .sakusei config should win'
    end

    def test_discover_falls_back_to_parent_sakusei_when_no_child_config
      parent_dir = @temp_dir
      make_pack(parent_dir, 'parent_pack')
      StylePack.set_default(parent_dir, 'parent_pack')

      # Child dir exists but has NO .sakusei
      child_dir = File.join(parent_dir, 'subdir')
      FileUtils.mkdir_p(child_dir)

      pack = StylePack.discover(child_dir)
      assert_equal 'parent_pack', pack.name, 'Should inherit parent default when no child .sakusei'
    end

    def test_list_available_default_marker_reflects_nearest_config
      parent_dir = @temp_dir
      make_pack(parent_dir, 'shared_pack')
      StylePack.set_default(parent_dir, 'shared_pack')

      child_dir = File.join(parent_dir, 'subdir')
      FileUtils.mkdir_p(child_dir)
      make_pack(child_dir, 'local_pack')
      StylePack.set_default(child_dir, 'local_pack')

      packs = StylePack.list_available(child_dir)
      local  = packs.find { |p| p[:name] == 'local_pack' }
      shared = packs.find { |p| p[:name] == 'shared_pack' }

      assert local[:default],  'local_pack should be default per nearest config'
      refute shared[:default], 'shared_pack from parent should not be marked default'
    end

    # ── explicit --style finds pack across full tree ─────────────────────────

    def test_discover_explicit_name_finds_pack_in_parent_when_child_sakusei_has_no_packs
      # Regression: nearest .sakusei has only config.yml (no style_packs/),
      # but the requested pack lives in a parent .sakusei/style_packs/.
      # Previously discover() stopped at the nearest .sakusei, found no packs_dir,
      # and silently fell back to the built-in default.
      parent_dir = @temp_dir
      make_pack(parent_dir, 'legal')

      # Child has a .sakusei with only a config — no style_packs/
      child_dir = File.join(parent_dir, 'projects', 'my-client')
      FileUtils.mkdir_p(child_dir)
      FileUtils.mkdir_p(File.join(child_dir, '.sakusei'))

      pack = StylePack.discover(child_dir, 'legal')
      assert_equal 'legal', pack.name, '--style legal should find pack in parent .sakusei even when nearest .sakusei has no style_packs/'
    end

    def test_discover_explicit_name_finds_pack_in_same_sakusei
      make_pack(@temp_dir, 'legal', 'corporate')

      pack = StylePack.discover(@temp_dir, 'legal')
      assert_equal 'legal', pack.name
    end

    def test_discover_explicit_name_raises_when_pack_not_found_anywhere
      make_pack(@temp_dir, 'corporate')

      assert_raises(Error) { StylePack.discover(@temp_dir, 'nonexistent') }
    end

    def test_discover_explicit_name_does_not_silently_fall_back_to_builtin_default
      # No packs at all — explicit name should raise, not silently return built-in
      assert_raises(Error) { StylePack.discover(@temp_dir, 'legal') }
    end
  end
end
