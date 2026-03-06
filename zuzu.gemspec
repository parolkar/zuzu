# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'zuzu'
  s.version     = '0.0.1'
  s.authors     = ['Abhishek Parolkar']
  s.email       = ['abhishek@parolkar.com']
  s.homepage    = 'https://github.com/parolkar/zuzu'
  s.summary     = 'Local-first agentic desktop apps with JRuby.'
  s.description = 'Zuzu is a framework for building local-first, ' \
                  'privacy-respecting desktop AI assistants using JRuby, ' \
                  'Glimmer DSL for SWT, SQLite, and llamafile.'
  s.license     = 'MIT'

  s.platform              = 'java'
  s.required_ruby_version = '>= 3.1.0'

  s.metadata = {
    'homepage_uri'    => s.homepage,
    'source_code_uri' => 'https://github.com/parolkar/zuzu',
    'bug_tracker_uri' => 'https://github.com/parolkar/zuzu/issues'
  }

  s.files         = Dir['lib/**/*', 'bin/*', 'templates/**/*', 'LICENSE', 'README.md']
  s.executables   = ['zuzu']
  s.require_paths = ['lib']

  s.add_dependency 'glimmer-dsl-swt', '~> 4.30'
  s.add_dependency 'jdbc-sqlite3',    '~> 3.46'
  s.add_dependency 'webrick',         '>= 1.7'
  s.add_dependency 'bigdecimal'
  s.add_dependency 'logger'
end
