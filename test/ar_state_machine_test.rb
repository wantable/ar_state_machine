require 'ar_state_machine'
require 'ar_state_machine/fake_active_record_model'

class StateMachineTestClass < FakeActiveRecordModel
  extend ArStateMachine::ActiveRecordExtensions
  
  attr_accessor :state, :second_state_at, :overwrite_second_state_at

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

  def reset
    @initial_state = self.state
  end

  def initialize(attributes)
    super
    @initial_state = self.states.first.first.to_s
  end

  def state_changed?
    self.state != @initial_state
  end

  def changed_attributes
    if state_changed?
      {'state' => @initial_state}
    else 
      {}
    end
  end

  def save_state_change; end;

  ## HERE begins the actual state machine implementation
  self.state_machine({
    first_state: [:second_state, :third_state],  
    second_state: :third_state,
    third_state: :fourth_state,
    fourth_state: []
  })
  before_transition_to(:second_state) do |from, to|
    self.append_callback_happened(:second_state, from.to_sym, :before)
  end
  before_transition_to([:second_state]) do |from, to|
    self.append_callback_happened(:second_state, from.to_sym, :before)
  end
  after_transition_to :second_state, :another_second_state_callback 

  def another_second_state_callback(from)
    self.append_callback_happened(:second_state, from.to_sym, :after)
  end

  before_transition_to(:fourth_state) do |from, to|
    self.errors[:state] << "Cannot transition to fourth_state because I said so."
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

class StateMachineTest < ActiveSupport::TestCase
  
  test "test state machine transitions" do
    test = StateMachineTestClass.create

    
    assert test.is_first_state?
    assert test.is_not_second_state?
    assert_not test.is_second_state?
    assert_not test.is_third_state?

    assert_not test.can_make_first_state?
    assert test.can_make_second_state?  
    assert test.can_make_third_state?
    
    assert test.make_second_state

    assert_not test.is_first_state?
    assert test.is_second_state?
    assert_not test.is_third_state?

    assert_not test.can_make_first_state?
    assert_not test.can_make_second_state?
    assert test.can_make_third_state?

    assert test.make_third_state

    assert_not test.is_first_state?
    assert_not test.is_second_state?
    assert test.is_third_state?

    assert_not test.can_make_first_state?
    assert_not test.can_make_second_state?
    assert_not test.can_make_third_state?
  end

  test "second_state_at gets filled in" do 
    test = StateMachineTestClass.create

    assert_not test.has_been_made_second_state?
    assert_nil test.second_state_at
    assert test.make_second_state
    assert_not_nil test.second_state_at

    assert test.has_been_made_second_state?

    assert_raises(NotImplementedError) do 
      assert test.has_been_made_third_state?
    end
  end

  test "test state machine callbacks" do
    test = StateMachineTestClass.create

    test.make_second_state
    assert_equal 1, test.callbacks_happened.count
    assert_equal 2, test.callbacks_happened[:second_state].count
    assert_equal 2, test.callbacks_happened[:second_state][:before][:first_state]
    assert_equal 1, test.callbacks_happened[:second_state][:after][:first_state]
  end

  test "test state machine callbacks don't fire if state didn't change" do     
    test = StateMachineTestClass.create
    test.make_second_state
    first_time = test.callbacks_happened

    assert first_time.present?

    assert test.make_second_state # can call this as many times as you want. it just triggers a save then
    assert_equal first_time, test.callbacks_happened
    test.save # this is like a different field was edited on the model
    assert_equal first_time, test.callbacks_happened

  end

  test "test state machine validation errors" do 
    test = StateMachineTestClass.create
    test.state = "bad_state"
    assert_not test.save
    assert_equal "bad_state is not a valid state.", test.errors[:state].first


    test = StateMachineTestClass.create
    assert test.make_second_state
    assert_not test.make_first_state
    assert_equal "Cannot transition from second_state to first_state.", test.errors[:state].first


    test = StateMachineTestClass.create
    assert test.make_third_state
    assert_not test.make_fourth_state
  end

  test "test state machine validation errors as exceptions" do 
    
    test = StateMachineTestClass.create
    assert test.make_second_state!
    assert_raises(Exception) do 
      test.make_first_state!
    end

    test = StateMachineTestClass.create
    assert test.make_third_state

    assert_raises(Exception) do 
      test.make_fourth_state!
    end
  end

  test "test overwriting timestamps" do 
    
    test = StateMachineTestClass.create
    assert_nil test.second_state_at 
    assert test.make_second_state
    assert_not_nil test.second_state_at 

    was = test.second_state_at
    Timecop.travel(2.days.from_now)

    test.state = StateMachineTestClass::FIRST_STATE
    assert test.reset
    assert test.make_second_state
    assert_not_equal was, test.second_state_at

    was = test.second_state_at

    test.overwrite_second_state_at = false  

    Timecop.travel(2.days.from_now)

    test.state = StateMachineTestClass::FIRST_STATE
    assert test.reset

    assert test.make_second_state
    assert_equal was, test.second_state_at

  end

end
