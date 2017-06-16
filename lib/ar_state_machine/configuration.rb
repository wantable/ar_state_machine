module ARStateMachine
  class Configuration

    attr_accessor :system_id, :should_log_state_change

    def initialize
      self.should_log_state_change = true
      self.system_id = 1
    end
  end
end