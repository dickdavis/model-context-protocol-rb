# frozen_string_literal: true

Dir[File.expand_path("../lib/**/*.rb", __dir__)].sort.each { |f| require f }
Dir[File.expand_path("spec/support/**/*.rb")].sort.each { |file| require file }

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
