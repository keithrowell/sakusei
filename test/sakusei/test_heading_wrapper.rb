# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestHeadingWrapper < TestCase
    def test_wraps_h2_with_following_paragraph
      content = "## My Heading\n\nSome paragraph content here.\n\nOther block."
      result = HeadingWrapper.new(content).wrap

      assert_includes result, "<div style=\"page-break-inside: avoid\">\n\n## My Heading\n\nSome paragraph content here.\n\n</div>"
      assert_includes result, "Other block."
    end

    def test_wraps_h3_with_following_paragraph
      content = "### Sub Heading\n\nParagraph text.\n\nNext block."
      result = HeadingWrapper.new(content).wrap

      assert_includes result, "<div style=\"page-break-inside: avoid\">\n\n### Sub Heading\n\nParagraph text.\n\n</div>"
    end

    def test_does_not_wrap_h1
      content = "# Document Title\n\nFirst paragraph."
      result = HeadingWrapper.new(content).wrap

      refute_includes result, "page-break-inside"
    end

    def test_does_not_wrap_heading_followed_by_heading
      content = "## Section One\n\n## Section Two\n\nParagraph."
      result = HeadingWrapper.new(content).wrap

      # Section One should not be wrapped (next block is a heading)
      refute_match(/<div.*>\n\n## Section One/, result)
      # Section Two should be wrapped (next block is a paragraph)
      assert_includes result, "<div style=\"page-break-inside: avoid\">\n\n## Section Two"
    end

    def test_does_not_wrap_heading_with_no_following_content
      content = "## Lone Heading"
      result = HeadingWrapper.new(content).wrap

      refute_includes result, "page-break-inside"
    end

    def test_preserves_content_outside_headings
      content = "Intro paragraph.\n\n## Section\n\nSection content.\n\nTrailing paragraph."
      result = HeadingWrapper.new(content).wrap

      assert_includes result, "Intro paragraph."
      assert_includes result, "Trailing paragraph."
    end

    def test_preserves_original_separator_length
      content = "## Heading\n\n\n\nParagraph.\n\nOther."
      result = HeadingWrapper.new(content).wrap

      # Should still produce valid output without crashing
      assert_includes result, "page-break-inside: avoid"
      assert_includes result, "Other."
    end

    def test_does_not_wrap_headings_inside_code_blocks
      content = <<~MD
        ## Real Heading

        Some intro.

        ```markdown

        # Title

        Some Markdown

        ```

        ## Another Real Heading

        Outro paragraph.
      MD

      result = HeadingWrapper.new(content).wrap

      # Real headings outside code blocks should still be wrapped
      assert_match(/<div style="page-break-inside: avoid">\n\n## Real Heading\n\nSome intro\.\n\n<\/div>/, result)
      assert_match(/<div style="page-break-inside: avoid">\n\n## Another Real Heading\n\nOutro paragraph\./m, result)

      # The heading inside the code block must NOT be wrapped
      assert_includes result, "```markdown\n\n# Title\n\nSome Markdown\n\n```"
      refute_includes result, "<div style=\"page-break-inside: avoid\">\n\n\n# Title"
    end

    def test_does_not_wrap_headings_inside_ruby_code_blocks
      content = <<~MD
        ```ruby
        ## This is a comment, not a heading

        foo = 1
        ```

        ## Actual Heading

        Paragraph.
      MD

      result = HeadingWrapper.new(content).wrap

      refute_match(/page-break-inside.*## This is a comment/m, result)
      assert_match(/<div style="page-break-inside: avoid">\n\n## Actual Heading\n\nParagraph\./m, result)
    end
  end
end
