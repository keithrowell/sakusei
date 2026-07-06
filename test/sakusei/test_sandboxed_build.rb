# frozen_string_literal: true

require_relative '../test_helper'
require 'tmpdir'
require 'fileutils'

module Sakusei
  class TestSandboxedBuild < TestCase
    def with_source_file(content)
      Dir.mktmpdir('sakusei-sandbox-test') do |dir|
        source = File.join(dir, 'input.md')
        File.write(source, content)
        yield source, dir
      end
    end

    def processed_content(source, options)
      builder = Builder.new(source, options)
      _style_pack, processed = builder.send(:build_processed_content)
      processed
    end

    def test_erb_is_left_literal_when_sandboxed
      with_source_file(%(# Hi\n\n<% sh("touch /tmp/sakusei-pwned") %> and <%= env("HOME") %>)) do |source, _dir|
        processed = processed_content(source, sandboxed: true)
        assert_includes processed, '<% sh("touch /tmp/sakusei-pwned") %>'
        assert_includes processed, '<%= env("HOME") %>'
        refute File.exist?('/tmp/sakusei-pwned'), 'sandboxed build must not execute ERB sh()'
      end
    end

    def test_erb_still_runs_when_not_sandboxed
      with_source_file('Today: <%= today %>') do |source, _dir|
        processed = processed_content(source, {})
        refute_includes processed, '<%= today %>'
      end
    end

    def test_includes_are_left_literal_when_sandboxed
      with_source_file("# Doc\n\n<!-- @include /etc/hosts -->") do |source, _dir|
        processed = processed_content(source, sandboxed: true)
        assert_includes processed, '<!-- @include /etc/hosts -->'
        refute_includes processed, 'localhost'
      end
    end

    def test_includes_resolve_when_not_sandboxed
      with_source_file('') do |source, dir|
        File.write(File.join(dir, 'part.md'), 'INCLUDED CONTENT')
        File.write(source, '<!-- @include part.md -->')
        processed = processed_content(source, {})
        assert_includes processed, 'INCLUDED CONTENT'
      end
    end

    # Builds a layout where ../secret-*.png escapes the source dir:
    #   parent/secret-<pid>.png   <- outside the source dir
    #   parent/src/               <- the source dir
    # The copy destination (temp_dir/../secret-*.png) resolves somewhere else
    # entirely, so presence/absence of the copy is observable.
    def with_escaping_image
      Dir.mktmpdir('sakusei-sandbox-parent') do |parent|
        src_dir = File.join(parent, 'src')
        FileUtils.mkdir_p(src_dir)
        secret_name = "secret-#{Process.pid}-#{rand(10_000)}.png"
        File.write(File.join(parent, secret_name), 'outside')
        File.write(File.join(src_dir, 'ok.png'), 'inside')
        yield src_dir, secret_name
      end
    end

    def test_sandboxed_image_copy_rejects_traversal
      with_escaping_image do |src_dir, secret_name|
        content = "![escape](../#{secret_name})\n![ok](ok.png)"
        converter = ConverterBase.new(content, nil, source_dir: src_dir, sandboxed: true)

        Dir.mktmpdir('sakusei-sandbox-out') do |temp_dir|
          converter.send(:copy_images, temp_dir)
          escaped_copy = File.expand_path(File.join(temp_dir, '..', secret_name))
          refute File.exist?(escaped_copy), 'traversal image must not be copied'
          assert File.exist?(File.join(temp_dir, 'ok.png')), 'in-dir image should still be copied'
        ensure
          FileUtils.rm_f(File.expand_path(File.join(temp_dir, '..', secret_name)))
        end
      end
    end

    def test_unsandboxed_image_copy_allows_traversal
      with_escaping_image do |src_dir, secret_name|
        content = "![escape](../#{secret_name})"
        converter = ConverterBase.new(content, nil, source_dir: src_dir)

        Dir.mktmpdir('sakusei-sandbox-out') do |temp_dir|
          converter.send(:copy_images, temp_dir)
          escaped_copy = File.expand_path(File.join(temp_dir, '..', secret_name))
          assert File.exist?(escaped_copy), 'existing behaviour: relative traversal is allowed when not sandboxed'
        ensure
          FileUtils.rm_f(File.expand_path(File.join(temp_dir, '..', secret_name)))
        end
      end
    end
  end
end
