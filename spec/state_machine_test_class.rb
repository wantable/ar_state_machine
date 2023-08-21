require "fake_active_record_model"

class StateMachineTestClass < FakeActiveRecordModel
  attr_accessor :state,
                :second_state_at,
                :third_state_at,
                :fourth_state_at,
                :second_state_by_id,
                :overwrite_second_state_at,
                :overwrite_second_state_by_id,
                :arbitrary_field


  def self.scope(_name, _block)
    nil
  end

  def initialize(attributes)
    super
    @initial_state = self.states.first.first.to_s
  end

  def save
    super
    if valid?
      @initial_state = self.state
      true
    else
      false
    end
  end

  def save!
    save
    if valid?
      true
    else
      raise Exception
    end
  end

  def will_save_change_to_state?
    self.state != @initial_state
  end

  alias_method :saved_change_to_state?, :will_save_change_to_state?

  def changes_to_save
    if will_save_change_to_state?
      { state: [@initial_state, state] }
    else
      {}
    end
  end

  alias_method :saved_changes, :changes_to_save

  def reset
    @initial_state = self.state
  end

  def save_state_change
    nil
  end

  ## HERE begins the actual state machine implementation
  include ARStateMachine

  state_machine(
    first_state: [:second_state, :third_state, :sixth_state, :seventh_state],
    second_state: :third_state,
    third_state: :fourth_state,
    fourth_state: [],
    fifth_state: [],
    sixth_state: [],
    seventh_state: []
  )

  before_transition_to(:second_state) do |from, to|
    self.append_callback_happened(to.to_sym, from.to_sym, :before)
  end

  before_transition_to([:second_state]) do |from, to|
    self.append_callback_happened(to.to_sym, from.to_sym, :before)
  end

  after_transition_to :second_state, :another_second_state_callback

  before_transition_from(:second_state) do |from, to|
    self.append_callback_happened(to.to_sym, from.to_sym, :before_from)
  end

  after_commit_transition_to :third_state do |from, to|
    self.append_callback_happened(to.to_sym, from.to_sym, :after_commit)
  end

  before_transition_to :sixth_state, rollback_on_failure: false do
    false
  end

  after_transition_to :seventh_state, rollback_on_failure: false do
    false
  end

  def another_second_state_callback(from, to)
    self.append_callback_happened(to.to_sym, from.to_sym, :after)
  end

  before_transition_to(:fourth_state) do |from, to|
    self.append_callback_happened(to.to_sym, from.to_sym, :before)
    self.errors.add(:state, "Cannot transition to fourth_state because I said so.")
    false
  end

  # helper methods for the tests to know what callbacks occured
  def callbacks_happened
    @callbacks_happened
  end

  def append_callback_happened(to, from, kind)
    @callbacks_happened ||= {}
    @callbacks_happened[to]||={}
    @callbacks_happened[to][kind]||={}
    @callbacks_happened[to][kind][from] ||= 0
    @callbacks_happened[to][kind][from] += 1
  end
end
