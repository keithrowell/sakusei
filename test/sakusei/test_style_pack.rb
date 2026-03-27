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
end
