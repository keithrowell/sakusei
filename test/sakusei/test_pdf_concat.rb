# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestPdfConcatenator < TestCase
    def setup
      @temp_dir = temp_dir

      # Create dummy PDF files (just the header - not valid PDFs but good enough for validation tests)
      @pdf1 = File.join(@temp_dir, 'test1.pdf')
      @pdf2 = File.join(@temp_dir, 'test2.pdf')
      File.write(@pdf1, '%PDF-1.4 dummy')
      File.write(@pdf2, '%PDF-1.4 dummy')
    end

    def test_validates_files_exist
      concat = PdfConcatenator.new([@pdf1, @pdf2], File.join(@temp_dir, 'out.pdf'))

      # Should not raise since files exist
      assert concat.send(:validate_files)
    end

    def test_raises_on_missing_file
      concat = PdfConcatenator.new([@pdf1, 'nonexistent.pdf'], File.join(@temp_dir, 'out.pdf'))

      assert_raises(Error) do
        concat.send(:validate_files)
      end
    end

    def test_raises_on_non_pdf_file
      txt_file = File.join(@temp_dir, 'test.txt')
      File.write(txt_file, 'not a pdf')

      concat = PdfConcatenator.new([@pdf1, txt_file], File.join(@temp_dir, 'out.pdf'))

      assert_raises(Error) do
        concat.send(:validate_files)
      end
    end
  end
end
