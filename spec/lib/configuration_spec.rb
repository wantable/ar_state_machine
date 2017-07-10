require 'spec_helper'

describe 'Configuration' do

  it 'configuration is saved from helper' do
    expect(ARStateMachine.configuration.should_log_state_change).to eq(true)
  end

end