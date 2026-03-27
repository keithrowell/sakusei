# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestStylePack < TestCase
    def setup
      @fixtures_dir = File.join(fixtures_dir, 'style_packs', 'default')
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
  end
end
