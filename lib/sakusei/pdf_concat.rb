# frozen_string_literal: true

module Sakusei
  # Concatenates multiple PDF files
  class PdfConcatenator
    # macOS built-in PDF join tool (last resort fallback)
    MACOS_JOIN_TOOL = '/System/Library/Automator/Combine PDF Pages.action/Contents/MacOS/join'

    def initialize(files, output_path)
      @files = files.map { |f| File.expand_path(f) }
      @output_path = File.expand_path(output_path)
    end

    def concat
      validate_files

      # Try tools in order of preference
      if pdfunite_available?
        concat_with_pdfunite
      elsif pdftk_available?
        concat_with_pdftk
      elsif macos_join_available?
        concat_with_macos_join
      else
        raise Error, 'No PDF concatenation tool found. Please install pdfunite (poppler-utils) or pdftk'
      end
    end

    private

    def validate_files
      @files.each do |file|
        raise Error, "File not found: #{file}" unless File.exist?(file)
        raise Error, "Not a PDF file: #{file}" unless File.extname(file).downcase == '.pdf'
      end
    end

    def pdfunite_available?
      system('which pdfunite > /dev/null 2>&1')
    end

    def pdftk_available?
      system('which pdftk > /dev/null 2>&1')
    end

    def macos_join_available?
      File.executable?(MACOS_JOIN_TOOL)
    end

    def concat_with_pdfunite
      cmd = ['pdfunite', *@files, @output_path].join(' ')
      result = system(cmd)
      raise Error, 'PDF concatenation failed with pdfunite' unless result
    end

    def concat_with_pdftk
      cmd = ['pdftk', *@files, 'cat', 'output', @output_path].join(' ')
      result = system(cmd)
      raise Error, 'PDF concatenation failed with pdftk' unless result
    end

    # Fallback to macOS built-in tool (last resort)
    def concat_with_macos_join
      cmd = [MACOS_JOIN_TOOL, '-o', @output_path, *@files].join(' ')
      result = system(cmd)
      raise Error, 'PDF concatenation failed with macOS join tool' unless result
    end
  end
end
