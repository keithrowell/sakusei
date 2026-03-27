require_relative 'lib/sakusei/version'

Gem::Specification.new do |spec|
  spec.name          = 'sakusei'
  spec.version       = Sakusei::VERSION
  spec.authors       = ['Keith Rowell']
  spec.email         = ['keith@example.com']

  spec.summary       = 'A PDF building system using Markdown, ERB, and CSS templating'
  spec.description   = 'Sakusei is a build system for creating PDF documents from Markdown sources with support for ERB templates, VueJS components, and hierarchical styling.'
  spec.homepage      = 'https://github.com/keithrowell/sakusei'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.0.0'

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = 'bin'
  spec.executables   = ['sakusei']
  spec.require_paths = ['lib']

  # Dependencies
  spec.add_dependency 'thor', '~> 1.2'
  spec.add_dependency 'erb', '~> 4.0'

  spec.add_development_dependency 'minitest', '~> 5.0'
  spec.add_development_dependency 'rubocop', '~> 1.0'
end
