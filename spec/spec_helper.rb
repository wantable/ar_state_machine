require 'bundler/setup'
Bundler.setup

require 'ar_state_machine'

RSpec.configure do |config|
  config.before(:each) {
    ARStateMachine.configure do |config|
      config.system_id = 1
      config.should_log_state_change = true
    end
  }
end