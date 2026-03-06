# frozen_string_literal: true

require_relative 'lib/zuzu/version'

Gem::Specification.new do |s|
  s.name        = 'zuzu'
  s.version     = Zuzu::VERSION
  s.authors     = ['Abhishek Parolkar']
  s.email       = ['abhishek@parolkar.com']
  s.homepage    = 'https://github.com/parolkar/zuzu'
  s.summary     = 'JRuby framework for AI-native desktop apps — local LLM, single .jar distribution, Claude Code-ready scaffolding.'
  s.description = \
    'Every installed application is an orchestrator of OS capabilities. ' \
    'LLMs are simply a more expressive interface for that orchestration. ' \
    'Zuzu is a framework for building installable, AI-native desktop apps ' \
    'where the intelligence runs on the user\'s hardware — not in a data center. ' \
    'It uses JRuby and Glimmer DSL for SWT for the GUI, Mozilla\'s llamafile for ' \
    'local LLM inference, and SQLite (via AgentFS) as a sandboxed virtual filesystem ' \
    'the agent can read and write without touching the host OS. ' \
    'Apps package as a single cross-platform .jar — users download, double-click, run. ' \
    'No cloud. No subscriptions. No infrastructure to operate. ' \
    'Scaffolded projects include CLAUDE.md and Claude Code skills pre-tuned to ' \
    'Zuzu\'s patterns, so coding agents generate correct framework code from the start.'
  s.license     = 'MIT'

  s.platform              = 'java'
  s.required_ruby_version = '>= 3.1.0'

  s.metadata = {
    'homepage_uri'    => s.homepage,
    'source_code_uri' => 'https://github.com/parolkar/zuzu',
    'bug_tracker_uri' => 'https://github.com/parolkar/zuzu/issues'
  }

  s.files         = Dir['lib/**/*', 'bin/*', 'templates/**/*', 'LICENSE', 'README.md', 'warble.rb'] +
                    Dir['templates/.claude/**/*']
  s.executables   = ['zuzu']
  s.require_paths = ['lib']

  s.add_dependency 'glimmer-dsl-swt', '~> 4.30'
  s.add_dependency 'jdbc-sqlite3',    '~> 3.46'
  s.add_dependency 'webrick',         '>= 1.7'
  s.add_dependency 'bigdecimal'
  s.add_dependency 'logger'
end
