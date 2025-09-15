require "mock_redis"

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
