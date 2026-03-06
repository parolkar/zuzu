# frozen_string_literal: true

# Warbler configuration for packaging Zuzu apps as standalone .jar / .war.
# Usage:  warble jar
#
# The resulting .jar can be run with:
#   java -XstartOnFirstThread -jar my_app.jar   (macOS)
#   java -jar my_app.jar                        (Linux / Windows)

Warbler::Config.new do |config|
  config.features  = %w[executable]
  config.dirs      = %w[lib templates models]
  config.includes  = FileList['app.rb', 'Gemfile']
  config.jar_name  = 'zuzu-app'

  # SWT native fragments are pulled in by glimmer-dsl-swt;
  # Warbler bundles them automatically.
  config.bundler   = true
end
