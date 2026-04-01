# frozen_string_literal: true

require_relative '../test_helper'

module Sakusei
  class TestErbProcessor < TestCase
    def setup
      @temp_dir = temp_dir
    end

    def test_processes_simple_erb
      content = "Hello <%= 'World' %>!"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_equal "Hello World!", result
    end

    def test_today_helper
      content = "Date: <%= today %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, Date.today.strftime('%Y-%m-%d')
    end

    def test_today_with_custom_format
      content = "Date: <%= today('%Y') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, Date.today.year.to_s
    end

    def test_env_helper
      ENV['SAKUSEI_TEST'] = 'test_value'
      content = "Value: <%= env('SAKUSEI_TEST') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, 'test_value'
    ensure
      ENV.delete('SAKUSEI_TEST')
    end

    def test_env_helper_with_default
      content = "Value: <%= env('NONEXISTENT_VAR', 'default') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, 'default'
    end

    def test_include_file_helper
      test_file = File.join(@temp_dir, 'test.txt')
      File.write(test_file, 'Included content')

      content = "<%= include_file('test.txt') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_includes result, 'Included content'
    end

    def test_handles_erb_errors
      content = "<%= undefined_method %>"
      processor = ErbProcessor.new(content, @temp_dir)

      assert_raises(Error) do
        processor.process
      end
    end

    def test_document_headings_returns_empty_for_missing_file
      content = "<%= document_headings('./nonexistent.md') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process

      assert_equal '[]', result
    end

    def test_document_headings_extracts_headings_after_contents_tag
      md = <<~MD
        # Document Title
        ## Before Contents
        <vue-component name="Contents" depth="1"/>
        ## Session One
        ### Subsection A
        ### Subsection B
        ## Session Two
      MD
      source_file = File.join(@temp_dir, 'doc.md')
      File.write(source_file, md)

      content = "<%= document_headings('./doc.md') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      result = processor.process
      items = JSON.parse(result)

      assert_equal 4, items.length
      assert_equal({ 'title' => 'Session One',  'level' => 1, 'slug' => 'session-one' },   items[0])
      assert_equal({ 'title' => 'Subsection A', 'level' => 2, 'slug' => 'subsection-a' },  items[1])
      assert_equal({ 'title' => 'Subsection B', 'level' => 2, 'slug' => 'subsection-b' },  items[2])
      assert_equal({ 'title' => 'Session Two',  'level' => 1, 'slug' => 'session-two' },   items[3])
    end

    def test_document_headings_excludes_headings_before_contents_tag
      md = <<~MD
        # Title
        ## Preamble
        <vue-component name="Contents"/>
        ## Real Section
      MD
      source_file = File.join(@temp_dir, 'doc.md')
      File.write(source_file, md)

      content = "<%= document_headings('./doc.md') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      items = JSON.parse(processor.process)

      assert_equal 1, items.length
      assert_equal 'Real Section', items[0]['title']
    end

    def test_document_headings_defaults_to_source_file
      md = <<~MD
        # Title
        <vue-component name="Contents"/>
        ## Section One
        ## Section Two
      MD
      source_file = File.join(@temp_dir, 'source.md')
      File.write(source_file, md)

      content = "<%= document_headings %>"
      processor = ErbProcessor.new(content, @temp_dir, source_file: source_file)
      items = JSON.parse(processor.process)

      assert_equal 2, items.length
      assert_equal 'Section One', items[0]['title']
      assert_equal 'Section Two', items[1]['title']
    end

    def test_document_headings_normalises_levels
      md = <<~MD
        # Title
        <vue-component name="Contents"/>
        ## H2 Section
        ### H3 Subsection
        #### H4 Sub-subsection
      MD
      source_file = File.join(@temp_dir, 'doc.md')
      File.write(source_file, md)

      content = "<%= document_headings('./doc.md') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      items = JSON.parse(processor.process)

      assert_equal 1, items[0]['level'] # h2 → 1
      assert_equal 2, items[1]['level'] # h3 → 2
      assert_equal 3, items[2]['level'] # h4 → 3
    end

    def test_document_headings_generates_slugs
      md = <<~MD
        # Title
        <vue-component name="Contents"/>
        ## Session 1 — Technical Discovery
        ### Platform Walkthrough (30–45 min)
      MD
      source_file = File.join(@temp_dir, 'doc.md')
      File.write(source_file, md)

      content = "<%= document_headings('./doc.md') %>"
      processor = ErbProcessor.new(content, @temp_dir)
      items = JSON.parse(processor.process)

      assert_equal 'session-1--technical-discovery',  items[0]['slug']
      assert_equal 'platform-walkthrough-3045-min',   items[1]['slug']
    end
  end
end
