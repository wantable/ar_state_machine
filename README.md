# ArStateMachine

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ar_state_machine'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install ar_state_machine

## Setup

config/initializers/ar_state_machine.rb

```ruby

  ARStateMachine.configure do |config|
    config.system_id = system_id
    config.should_log_state_change = true
  end

```

## Usage

Simply define the state machine at the top of your model in the format below:
```ruby
  self.state_machine({
    first_state: [:second_state, :third_state],
    :second_state: :third_state,
    third_state: []
  })
```
**Convention** - states should usually be past tense (completed, imported, etc) or present participle for ongoing actions (building, returning).

This example indicates that first_state can transition to second_state or third_state but second_state can only transition to third_state which is then a dead end.

Then add any before, after and after_commit callbacks to fire on state changes.

These use the [active record callback chain](http://guides.rubyonrails.org/v4.2/active_record_callbacks.html):

**Note:** if you have multiple of the same transition type they execute in the order they are put in your model file.

  - `before_transition_to`, `before_transition_from` run on `before_update`
    - returning false or raising an exception in here will halt the transaction stop running transitions
  - `after_transition_to`, `after_transition_from` run on `after_update`
  - `after_commit_transition_to`, `after_commit_transition_from` run on `after_commit, on: :update`



Here are some rules of thumb to follow:

  - `before_transition` - only if you need to be able to halt the transaction (validation generally) or you need to set a value on the model being transitioned. You can also use this to halt AR state machine callbacks but still allow the transaction to save (payment failure is a good example, we still want to save the failure).
  - `after_transition` - use if you need to update child records or do something that uses AR to update the database. If you need to halt the transaction you'll need to do it with an exception as returning false does nothing here.
  - `after_commit_transition` - most of the time, background job queue, cache clearing and similar tasks, do not use this if what you're doing will result in another transaction; `update_columns`, `update_all`, `delete`, `delete_all` are okay but nothing that results in an AR save/create/update/state transition.
```ruby
  before_transition_to :second_state do |from, to|
    puts "doing a before transition from #{self.from} to #{self.state}"
  end
  before_transition_to :second_state do |from, to|
    puts "doing another before transition #{self.state}"
  end
  after_transition_to :second_state do |from, to|
    puts "doing an after transition #{self.state}"
  end
  after_commit_transition_to :second_state do |from, to|
    puts "doing an after commit transition #{self.state}"
  end
  before_transition_from :second_state do |from, to|
    puts "doing before transition from #{self.state}"
  end
  after_transition_from :second_state do |from, to|
    puts "doing an after transition from #{self.state}"
  end
  after_commit_transition_from :second_state do |from, to|
    puts "doing an after commit transition from #{self.state}"
  end
```

this also supports arrays

```ruby
  after_transition_to [:second_state, :first_state] do |from, to|
    puts "doing an after transition #{self.state}"
  end
```

and reusable functions
```ruby
  after_transition_to :second_state, :function_name

  def function_name(from, to)
    puts "doing an after transition #{self.state}"
  end
```


It provides the instance methods for each state_name:
```ruby
  model_instance.is_state_name? => true/false
  model_instance.is_not_state_name? => true/false
  model_instance.can_make_state_name? => true/false
  model_instance.make_state_name =>  # transitions to new state if it can, otherwise adds rails validation error messages
  model_instance.make_state_name! => # transitions to new state if it can, otherwise throws exception and adds rails validation error messages
```

Class level constants for each state
```Model::STATE_NAME => 'state_name'```

And the class scopes for each state_name:
```ruby
  ModelName.state_name
  ModelName.not_state_name
```
Which is chainable with any other scopes you might have EX:
```ruby
  Order.completed.by_date(Date.today)
  Order.not_completed.by_date(Date.today)
```

You can add timestamps to your models that will automatically get filled in. In the format ```#{state_name}_at```. IE: a ```completed_at``` timestamp will get populated with the timestamp that the object moves to a ```completed``` state.
Once these timestamps are in place; helper methods are available to determine if an instance has ever been in a state given.  IE: if you have Order and field completed_at; then you also have ```order_model.has_been_made_completed?``` and the inverse ```order_model.has_not_been_made_completed?```

All transitions are logged in the state_changes table.



## Development

After checking out the repo, run `bin/setup` to install dependencies. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/ar_state_machine.

