# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestVersion < TestCase
    def test_version_exists
      refute_nil VERSION
    end

    def test_version_format
      assert_match(/^\d+\.\d+\.\d+$/, VERSION)
    end
  end
end
