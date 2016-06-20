describe "StateMachine" do

  it 'does what it' do
    test = StateMachineTestClass.create
    expect(test.is_first_state?).to eq(true)
  end

end