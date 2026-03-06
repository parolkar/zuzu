# frozen_string_literal: true

# A minimal smoke test to verify the gem loads and basic APIs work.
# Run:  jruby -S rake test
#
# Note: GUI tests require a display. These tests cover the non-GUI parts.

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))

require 'zuzu/version'
require 'zuzu/config'

require 'minitest/autorun'

class VersionTest < Minitest::Test
  def test_version_is_string
    assert_kind_of String, Zuzu::VERSION
    assert_match(/\A\d+\.\d+\.\d+\z/, Zuzu::VERSION)
  end
end

class ConfigTest < Minitest::Test
  def test_defaults
    config = Zuzu::Config.new
    assert_equal 8080, config.port
    assert_equal 'Zuzu', config.app_name
    assert_equal 860, config.window_width
    assert_equal 620, config.window_height
    assert_equal [], config.channels
  end

  def test_configure_block
    Zuzu.configure do |c|
      c.app_name = 'Test App'
      c.port     = 9090
    end
    assert_equal 'Test App', Zuzu.config.app_name
    assert_equal 9090, Zuzu.config.port
  ensure
    # Reset
    Zuzu.configure do |c|
      c.app_name = 'Zuzu'
      c.port     = 8080
    end
  end

  def test_path_expansion
    config = Zuzu::Config.new
    config.db_path = 'data/test.db'
    assert config.db_path.start_with?('/'), "db_path should be absolute: #{config.db_path}"
  end
end
