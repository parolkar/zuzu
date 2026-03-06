# frozen_string_literal: true

require 'rake'
require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'test'
  t.test_files = FileList['test/**/*_test.rb']
end

desc 'Open an IRB console with Zuzu loaded'
task :console do
  sh 'jruby -r ./lib/zuzu -r irb -e "IRB.start"'
end

desc 'Build the gem'
task :build do
  sh 'gem build zuzu.gemspec'
end

desc 'Install the gem locally'
task :install => :build do
  sh "gem install zuzu-#{File.read('lib/zuzu/version.rb')[/VERSION\s*=\s*"([^"]+)"/, 1]}-java.gem"
end

task default: :test
