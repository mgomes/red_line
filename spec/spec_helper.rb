# frozen_string_literal: true

require "bundler/setup"
require "red_line"
require "timecop"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!
  config.warnings = true

  config.default_formatter = "doc" if config.files_to_run.one?

  config.order = :random
  Kernel.srand config.seed

  config.before(:suite) do
    RedLine.configure do |c|
      if ENV["REDIS_URL"]
        c.redis_url = ENV["REDIS_URL"]
      else
        c.redis_db = 15
      end
    end
  end

  config.before(:each, :redis) do
    flush_redis!
  end

  config.after(:suite) do
    flush_redis!
  end
end

def flush_redis!
  RedLine.connection.call("FLUSHDB")
rescue
  nil
end

def redis_available?
  RedLine.connection.call("PING") == "PONG"
rescue
  false
end

RSpec.configure do |config|
  config.before(:each, :redis) do
    skip "Redis not available" unless redis_available?
  end
end
