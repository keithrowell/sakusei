# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestBuilderBreakSyntax < TestCase
    def expand(content)
      Builder.new('/dev/null').send(:expand_break_syntax, content)
    end

    def test_replaces_break_shorthand
      result = expand("Before\n\n::break::\n\nAfter")
      assert_includes result, '<div class="page-break"></div>'
      refute_includes result, '::break::'
    end

    def test_replaces_multiple_breaks
      result = expand("A\n\n::break::\n\nB\n\n::break::\n\nC")
      assert_equal 2, result.scan('<div class="page-break"></div>').length
    end

    def test_no_false_positives
      result = expand("No breaks here")
      refute_includes result, 'page-break'
    end

    def test_preserves_surrounding_content
      result = expand("Hello\n\n::break::\n\nWorld")
      assert_includes result, 'Hello'
      assert_includes result, 'World'
    end

    def test_raw_html_div_still_works
      content = 'Before<div class="page-break"></div>After'
      result = expand(content)
      assert_includes result, '<div class="page-break"></div>'
    end
  end
end
