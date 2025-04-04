# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)

require "standard/rake"

Dir.glob("tasks/*.rake").each { |r| load r }

task default: %i[spec standard]
