module ArStateMachine
  class Configuration

    attr_accessor :system_id, :should_change_state

    def initialize
      self.should_change_state = true
      self.system_id = 1
    end
  end
end