class FakeActiveRecordModel
  # pretend to be an active record model
  # this isn't a perfect way to test because I can't seperate the callbacks and
  # test that if invalid the before's are called and the after's aren't

  include ActiveModel::Model
  extend ActiveModel::Callbacks
  extend ARStateMachine::ActiveRecordExtensions

  attr_accessor :id

  # override a few methods because this isn't valid to insert to the state change table - this isn't an AR model
  def self.has_many(what, options={}); end;

  define_model_callbacks :update, :initialize, :create, :commit


  def self.create(params={})
    model = self.new(params)
    model
  end

  # Just check validity, and if so, trigger callbacks.
  def save
    if valid?
      run_callbacks(:update) { self.id ||= rand(1000) }

      run_callbacks(:commit) { true}
      true
    else
      false
    end
  end

  def save!
    if valid?
      run_callbacks(:update) { self.id ||= rand(1000) }
      id ||= rand(1000)
      run_callbacks(:commit) { true }
      true
    else
      throw Exception self.errors
    end
  end

  def initialize(attributes={})
    run_callbacks(:initialize) { true }
  end


end