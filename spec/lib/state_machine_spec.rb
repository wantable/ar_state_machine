require "spec_helper"
require "state_machine_test_class"
require "timecop"

describe "StateMachine" do

  it 'transitions properly' do
    test = StateMachineTestClass.create
    expect(test.is_first_state?).to be true
    expect(test.is_not_second_state?).to be true
    expect(test.is_second_state?).to be false
    expect(test.is_third_state?).to be false

    expect(test.can_make_first_state?).to be false
    expect(test.can_make_second_state?).to be true
    expect(test.can_make_third_state?).to be true

    expect(test.make_second_state).to be true

    expect(test.is_first_state?).to be false
    expect(test.is_second_state?).to be true
    expect(test.is_third_state?).to be false

    expect(test.can_make_first_state?).to be false
    expect(test.can_make_second_state?).to be false
    expect(test.can_make_third_state?).to be true

    expect(test.make_third_state).to be true

    expect(test.is_first_state?).to be false
    expect(test.is_second_state?).to be false
    expect(test.is_third_state?).to be true

    expect(test.can_make_first_state?).to be false
    expect(test.can_make_second_state?).to be false
    expect(test.can_make_third_state?).to be false
  end

  it "test second_state_at gets filled in" do
    test = StateMachineTestClass.create
    expect(test.has_been_made_second_state?).to be false
    expect(test.second_state_at).to be_nil
    expect(test.make_second_state).to be true
    expect(test.second_state_at).not_to be_nil

    expect(test.has_been_made_second_state?).to be true
    expect{ test.has_been_made_fifth_state? }.to raise_error(NotImplementedError)
  end

  it "test does not change state_at on transition fail" do
    test = StateMachineTestClass.create
    expect(test.make_third_state).to be true
    expect(test.is_third_state?).to be true

    was = test.third_state_at
    Timecop.travel(Time.now + 1)

    expect(test.can_make_fourth_state?).to be true
    expect(test.make_fourth_state).to be false
    expect(test.callbacks_happened[:fourth_state][:before][:third_state]).to eq(1)
    expect(test.is_third_state?).to be true
    expect(test.fourth_state_at).to be_nil
    expect(test.third_state_at).to eq(was)
  end

  it "test state machine callbacks", :aggregate_failures do
    test = StateMachineTestClass.create

    expect(test.make_second_state).to be true
    expect(test.callbacks_happened.count).to eq(1)
    expect(test.callbacks_happened[:second_state].count).to eq(2)
    expect(test.callbacks_happened[:second_state][:before][:first_state]).to eq(2)
    expect(test.callbacks_happened[:second_state][:after][:first_state]).to eq(1)

    expect(test.make_third_state).to be true
    expect(test.callbacks_happened[:third_state].count).to eq(2)
    expect(test.callbacks_happened[:third_state][:after_commit][:second_state]).to eq(1)
    expect(test.callbacks_happened[:third_state][:before_from][:second_state]).to eq(1)
  end

  it "test state machine callbacks don't fire if state didn't change" do
    test = StateMachineTestClass.create
    expect(test.make_second_state).to be true
    first_time = test.callbacks_happened

    expect(first_time.present?).to be true

    expect(test.make_second_state).to be true
    test.save
    expect(test.callbacks_happened).to eq(first_time)
  end

  it "test state machine validation errors" do
    test = StateMachineTestClass.create

    test.state = "bad_state"
    expect(test.save).to be false
    expect(test.errors[:state].first).to eq("bad_state is not a valid state.")

    test = StateMachineTestClass.create
    expect(test.make_second_state).to be true
    expect(test.make_first_state).to be false
    expect(test.errors[:state].first).to eq("Cannot transition from second_state to first_state.")

    test = StateMachineTestClass.create
    expect(test.make_third_state).to be true
    expect(test.make_fourth_state).to be false
  end

  it "test state machine validation errors as exceptions" do
    test = StateMachineTestClass.create
    expect(test.make_second_state).to be true
    expect{test.make_first_state!}.to raise_error(Exception)

    test = StateMachineTestClass.create
    expect(test.make_third_state).to be true

    expect{test.make_fourth_state!}.to raise_error(Exception)
  end

  it "test overwriting timestamps" do
    test = StateMachineTestClass.create
    expect(test.second_state_at).to be_nil
    expect(test.make_second_state).to be true
    expect(test.second_state_at).not_to eq(nil)

    was = test.second_state_at
    Timecop.travel(Time.now + 2)

    test.state = StateMachineTestClass::FIRST_STATE
    expect(test.reset).to eq(StateMachineTestClass::FIRST_STATE)
    expect(test.make_second_state).to be true
    expect(test.second_state_at).not_to eq(was)

    was = test.second_state_at
    test.overwrite_second_state_at = false

    Timecop.travel(Time.now + 2)
    test.state = StateMachineTestClass::FIRST_STATE
    expect(test.reset).to eq(StateMachineTestClass::FIRST_STATE)

    expect(test.make_second_state).to be true
    expect(test.second_state_at).to eq(was)
  end

  it "test overwriting ids" do
    test = StateMachineTestClass.create
    expect(test.second_state_by_id).to be_nil

    expect(test.make_second_state(2)).to be true

    was = test.second_state_by_id
    test.overwrite_second_state_by_id = false

    test.state = StateMachineTestClass::FIRST_STATE
    expect(test.reset).to eq(StateMachineTestClass::FIRST_STATE)
    expect(test.make_second_state(5)).to be true
    expect(test.second_state_by_id).to eq(was)
  end

  it "test setting value before hand then changing states perserves id" do
    test = StateMachineTestClass.create
    expect(test.second_state_by_id).to be_nil

    test.second_state_by_id = 2
    expect(test.make_second_state).to be true

    expect(2).to eq(test.second_state_by_id)
  end

  it "test rollback_on_failure in before transition" do
    test = StateMachineTestClass.create

    thing = 'thing'

    test.arbitrary_field = thing
    expect(test.make_sixth_state).to be false
    expect(test.is_first_state?).to be true   # state was rollback
    expect(thing).to eq(test.arbitrary_field) # but other data was not
  end

  it "test rollback_on_failure in after transition" do
    test = StateMachineTestClass.create

    thing = 'thing'

    test.arbitrary_field = thing
    expect(test.make_seventh_state).to be false
    expect(test.is_first_state?).to be true   # state was rollback
    expect(thing).to eq(test.arbitrary_field) # but other data was not
  end
end




