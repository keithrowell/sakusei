# frozen_string_literal: true

require_relative '../test_helper'
require 'json'

module Sakusei
  # Test subclass that bypasses Node.js for unit testing process() logic
  class FakeVueProcessor < VueProcessor
    def initialize(content, base_dir, batch_results, style_pack: nil)
      super(content, base_dir, style_pack: style_pack)
      @batch_results = batch_results
    end

    def vue_renderer_available?
      true
    end

    def render_batch(_jobs)
      @batch_results
    end
  end

  class TestVueProcessor < TestCase
    def setup
      @temp_dir = temp_dir
    end

    def test_no_components_returns_unchanged
      content = "# Markdown without Vue\n\nJust regular text."
      processor = VueProcessor.new(content, @temp_dir)
      assert_equal content, processor.process
    end

    def test_finds_component_file_in_components_dir
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'Test.vue'), '<template><div>Test</div></template>')

      processor = VueProcessor.new('', @temp_dir)
      assert_equal File.join(components_dir, 'Test.vue'),
                   processor.send(:find_component_file, 'Test')
    end

    def test_returns_nil_for_missing_component
      processor = VueProcessor.new('', @temp_dir)
      assert_nil processor.send(:find_component_file, 'Missing')
    end

    def test_first_pass_replaces_tag_with_placeholder
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'Alert.vue'), '<template><div></div></template>')

      processor = VueProcessor.new('', @temp_dir)
      jobs = []
      result = processor.send(:first_pass, '<vue-component name="Alert" />', jobs)

      assert_equal 1, jobs.length
      assert_equal '<!-- sakusei-vue-0 -->', result
    end

    def test_first_pass_collects_props
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'Card.vue'), '<template><div></div></template>')

      processor = VueProcessor.new('', @temp_dir)
      jobs = []
      processor.send(:first_pass, '<vue-component name="Card" title="My Title" />', jobs)

      assert_equal 0, jobs[0]['id']
      assert_equal 'My Title', jobs[0]['props']['title']
      assert_equal File.join(@temp_dir, 'components', 'Card.vue'), jobs[0]['componentFile']
    end

    def test_first_pass_missing_component_has_empty_file_path
      processor = VueProcessor.new('', @temp_dir)
      jobs = []
      processor.send(:first_pass, '<vue-component name="Missing" />', jobs)

      assert_equal '', jobs[0]['componentFile']
    end

    def test_first_pass_assigns_sequential_ids
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'A.vue'), '<template><div></div></template>')
      File.write(File.join(components_dir, 'B.vue'), '<template><div></div></template>')

      processor = VueProcessor.new('', @temp_dir)
      jobs = []
      processor.send(:first_pass, '<vue-component name="A" /><vue-component name="B" />', jobs)

      assert_equal 0, jobs[0]['id']
      assert_equal 1, jobs[1]['id']
    end

    def test_process_substitutes_rendered_html
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'Test.vue'), '<template><div>Test</div></template>')

      processor = FakeVueProcessor.new(
        '<vue-component name="Test" />',
        @temp_dir,
        [{ 'id' => 0, 'html' => '<div>rendered</div>', 'css' => '' }]
      )
      result = processor.process
      assert_includes result, '<div>rendered</div>'
      refute_includes result, '<vue-component'
    end

    def test_process_prepends_collected_css
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'Styled.vue'), '<template><div></div></template>')

      processor = FakeVueProcessor.new(
        '<vue-component name="Styled" />',
        @temp_dir,
        [{ 'id' => 0, 'html' => '<div></div>', 'css' => '.foo { color: red; }' }]
      )
      result = processor.process
      assert result.start_with?('<style>'), "Expected result to start with <style>"
      assert_includes result, '.foo { color: red; }'
    end

    def test_process_no_css_block_when_no_styles
      components_dir = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components_dir)
      File.write(File.join(components_dir, 'Plain.vue'), '<template><div></div></template>')

      processor = FakeVueProcessor.new(
        '<vue-component name="Plain" />',
        @temp_dir,
        [{ 'id' => 0, 'html' => '<div></div>', 'css' => '' }]
      )
      result = processor.process
      refute result.start_with?('<style>'), "Expected no <style> block when css is empty"
    end

    def test_finds_component_in_style_pack_when_not_local
      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)
      File.write(File.join(pack_components, 'PackComp.vue'), '<template><div>Pack</div></template>')

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      result = processor.send(:find_component_file, 'PackComp')
      assert_equal File.join(pack_components, 'PackComp.vue'), result
    end

    def test_local_component_overrides_style_pack_component
      local_components = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(local_components)
      local_file = File.join(local_components, 'SharedComp.vue')
      File.write(local_file, '<template><div>Local</div></template>')

      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)
      File.write(File.join(pack_components, 'SharedComp.vue'), '<template><div>Pack</div></template>')

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      result = processor.send(:find_component_file, 'SharedComp')
      assert_equal local_file, result
    end

    def test_find_component_returns_nil_when_not_found_in_pack_or_local
      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      assert_nil processor.send(:find_component_file, 'Nonexistent')
    end

    def test_job_nodeModulesDir_is_nil_for_local_component_without_node_modules
      components = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components)
      File.write(File.join(components, 'Comp.vue'), '<template><div></div></template>')

      processor = VueProcessor.new('', @temp_dir)
      jobs = []
      processor.send(:first_pass, '<vue-component name="Comp" />', jobs)
      assert_nil jobs[0]['nodeModulesDir']
    end

    def test_job_nodeModulesDir_is_set_for_local_component_with_node_modules
      components = File.join(@temp_dir, 'components')
      FileUtils.mkdir_p(components)
      File.write(File.join(components, 'Comp.vue'), '<template><div></div></template>')
      node_modules = File.join(@temp_dir, 'node_modules')
      FileUtils.mkdir_p(node_modules)

      processor = VueProcessor.new('', @temp_dir)
      jobs = []
      processor.send(:first_pass, '<vue-component name="Comp" />', jobs)
      assert_equal node_modules, jobs[0]['nodeModulesDir']
    end

    def test_job_nodeModulesDir_is_style_pack_node_modules_for_pack_component
      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)
      File.write(File.join(pack_components, 'PackComp.vue'), '<template><div></div></template>')

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      jobs = []
      processor.send(:first_pass, '<vue-component name="PackComp" />', jobs)
      assert_equal File.join(pack_dir, 'node_modules'), jobs[0]['nodeModulesDir']
    end

    def test_style_pack_needs_install_returns_true_when_package_json_but_no_node_modules
      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)
      File.write(File.join(pack_components, 'Comp.vue'), '<template><div></div></template>')
      File.write(File.join(pack_dir, 'package.json'), '{}')
      # No node_modules/ created

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      assert processor.send(:style_pack_needs_install?, fake_pack)
    end

    def test_style_pack_needs_install_returns_false_when_node_modules_exists
      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)
      File.write(File.join(pack_components, 'Comp.vue'), '<template><div></div></template>')
      File.write(File.join(pack_dir, 'package.json'), '{}')
      FileUtils.mkdir_p(File.join(pack_dir, 'node_modules'))

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      refute processor.send(:style_pack_needs_install?, fake_pack)
    end

    def test_style_pack_has_vue_renderer_returns_true_when_node_modules_present
      skip 'npm not available' unless system('which npm > /dev/null 2>&1')

      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)
      File.write(File.join(pack_components, 'Comp.vue'), '<template><div></div></template>')
      # Install real vue deps
      File.write(File.join(pack_dir, 'package.json'), JSON.generate({ dependencies: { '@vue/server-renderer' => '^3.5.0', '@vue/compiler-sfc' => '^3.5.0', 'vue' => '^3.5.0' } }))
      system('npm', 'install', '--prefix', pack_dir, %i[out err] => File::NULL)

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      assert processor.send(:style_pack_has_vue_renderer?)
    end

    def test_style_pack_has_vue_renderer_returns_false_when_no_node_modules
      pack_dir = File.join(@temp_dir, 'pack')
      pack_components = File.join(pack_dir, 'components')
      FileUtils.mkdir_p(pack_components)

      fake_pack = Struct.new(:path, :components_dir).new(pack_dir, pack_components)
      processor = VueProcessor.new('', @temp_dir, style_pack: fake_pack)
      refute processor.send(:style_pack_has_vue_renderer?)
    end
  end
end
