# frozen_string_literal: true

module Sakusei
  # Wraps each h2/h3 heading and its immediately following content block in a
  # <div style="page-break-inside: avoid"> so that Chromium/Puppeteer keeps
  # the heading glued to the content that follows it.
  #
  # Operates on the markdown string after ERB and Vue processing so that Vue
  # component output (already rendered to HTML) is treated as a normal block.
  # Raw HTML in the markdown (html: true) passes through md-to-pdf untouched.
  class HeadingWrapper
    HEADING_PATTERN = /\A[ \t]*(##|###) /
    FENCE_PATTERN = /\A`{3,}/

    def initialize(content)
      @content = content
    end

    def wrap
      code_blocks = []
      text_lines = []
      in_code = false
      code_buffer = []

      @content.each_line do |line|
        if line.match?(FENCE_PATTERN)
          if in_code
            # End of code block
            code_buffer << line
            code_blocks << code_buffer.join
            text_lines << "#{placeholder_for(code_blocks.length - 1)}\n\n"
            code_buffer = []
            in_code = false
          else
            # Start of code block
            in_code = true
            code_buffer << line
          end
        elsif in_code
          code_buffer << line
        else
          text_lines << line
        end
      end

      # Handle unclosed code block
      if in_code
        code_blocks << code_buffer.join
        text_lines << "#{placeholder_for(code_blocks.length - 1)}\n\n"
      end

      wrapped = wrap_text(text_lines.join)

      # Restore code blocks
      code_blocks.each_with_index do |block, i|
        wrapped = wrapped.sub(placeholder_for(i), block)
      end

      wrapped
    end

    private

    def placeholder_for(index)
      "__SAKUSEI_CODE_BLOCK_#{index}__"
    end

    def wrap_text(content)
      # Split on two-or-more blank lines to get top-level blocks.
      # Preserve the separator length so rejoining is faithful.
      blocks = content.split(/(\n{2,})/)
      # split with a capture group gives us [block, sep, block, sep, ...]
      result = []
      i = 0
      while i < blocks.length
        block = blocks[i]
        sep   = blocks[i + 1] || "\n\n"

        if heading_block?(block)
          # Look ahead past the separator to the next content block
          next_block = blocks[i + 2]
          next_sep   = blocks[i + 3] || "\n\n"

          if next_block && !heading_block?(next_block)
            result << "<div style=\"page-break-inside: avoid\">\n\n#{block}#{sep}#{next_block}\n\n</div>"
            result << next_sep
            i += 4
            next
          end
        end

        result << block
        result << sep
        i += 2
      end

      result.join
    end

    def heading_block?(block)
      return false unless block
      block.match?(HEADING_PATTERN)
    end
  end
end
