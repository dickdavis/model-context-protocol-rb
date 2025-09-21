require "mock_redis"

class MockRedis
  ConnectionError = Class.new(StandardError)

  def eval(script, keys: [], argv: [])
    if script.include?("SET") && script.include?("NX") && script.include?("EX")
      lock_key = keys.first
      lock_value = argv.first
      ttl = argv[1]

      if exists(lock_key) == 0
        set(lock_key, lock_value, nx: true, ex: ttl)
        1
      else
        0
      end
    elsif script.include?("redis.call(\"get\"") && script.include?("redis.call(\"del\"")
      lock_key = keys.first
      expected_value = argv.first

      current_value = get(lock_key)
      if current_value == expected_value
        del(lock_key)
        1
      else
        0
      end
    elsif script.include?("lrange") && script.include?("del")
      queue_key = keys.first
      messages = lrange(queue_key, 0, -1)
      del(queue_key) if messages.any?
      messages
    else
      []
    end
  end
end

Object.send(:remove_const, :Redis) if Object.const_defined?(:Redis)
Object.const_set(:Redis, MockRedis)

Dir[File.expand_path("../lib/**/*.rb", __dir__)].sort.each { |f| require f }
Dir[File.expand_path("spec/support/**/*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  config.example_status_persistence_file_path = ".rspec_status"

  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.before(:each) do
    if defined?(Redis.current)
      begin
        Redis.current.flushdb
      rescue
        nil
      end
    end
  end
end
