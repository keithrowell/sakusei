# frozen_string_literal: true

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'minitest/autorun'
require 'sakusei'

module Sakusei
  class TestCase < Minitest::Test
    def fixtures_dir
      File.expand_path('fixtures', __dir__)
    end

    def temp_dir
      @temp_dir ||= Dir.mktmpdir('sakusei_test')
    end

    def teardown
      FileUtils.rm_rf(@temp_dir) if @temp_dir
    end
  end
end
