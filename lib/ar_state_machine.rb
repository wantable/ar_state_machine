require "ar_state_machine/version"
require "ar_state_machine/configuration"
require "active_record"

module ARStateMachine
  extend ActiveSupport::Concern

  included do
    cattr_accessor    :states, :after_callbacks

    attr_accessor     :last_edited_by_id, :skipped_transition

    after_initialize  :state_machine_set_initial_state

    before_update     :set_state_by_id,
                      if: -> { will_save_change_to_state? || skipped_transition_equals_state? }

    before_update     :do_state_change_do_before_callbacks,
                      if: -> { will_save_change_to_state? || skipped_transition_equals_state? }

    after_update      :do_state_change_do_after_callbacks,
                      if: -> { saved_change_to_state? || skipped_transition_equals_state? }

    after_commit      :do_state_change_do_after_commit_callbacks

    before_update     :save_state_change,
                      if: -> { ARStateMachine.configuration.should_log_state_change && (will_save_change_to_state? || skipped_transition_equals_state?) }

    validate          :state_machine_validation

    validates         :state,
                      presence: true

    has_many          :state_changes, as: :source,
                      dependent: :delete_all
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.configure
    yield(configuration) if block_given?
  end

  private

  def rails51?
    Gem::Version.new(ActiveRecord::VERSION::STRING) >= Gem::Version.new('5.1')
  end

  def skipped_transition_equals_state?
    skipped_transition && skipped_transition.to_s == state.to_s
  end

  def will_save_change_to_state?
    rails51? ? will_save_change_to_attribute?(:state) : state_changed?
  end

  def saved_change_to_state?
    if rails51?
      saved_change_to_attribute?(:state) || will_save_change_to_attribute?(:state)
    else
      state_changed?
    end
  end

  def resolve_old_state(is_saved:)
    old_state = if rails51?
      (is_saved ? saved_changes : changes_to_save)[:state]&.first
    else
      changed_attributes[:state]
    end

    # we usually only want to create the state change if the state actually changes but
    #   we also want to create it if it fails to transition from a state and stays there
    #   example: a SubscriptionSeason in errored attempts to move to purchased, the order
    #   fails to build and it goes back to errored. We want to log the attempt.
    #   we also want to do any callbacks
    old_state ||= skipped_transition if skipped_transition.to_s == state.to_s

    old_state
  end

  def state_machine_set_initial_state
    self.state ||= self.class.states.first.first
  end

  def do_state_change_do_before_callbacks
    self.class.run_before_transition_callbacks(self.state, self, resolve_old_state(is_saved: false))

    if self.skipped_transition &&
       self.respond_to?("#{self.skipped_transition}_at=") &&
       (
         self.respond_to?("#{self.skipped_transition}_at").blank? ||
         should_overwrite_timestamp?(self.skipped_transition)
       )
      self.send("#{self.skipped_transition}_at=", Time.now)
    end

    if self.respond_to?("#{self.state}_at=")
      if (self.send("#{self.state}_at").blank? || should_overwrite_timestamp?(self.state))
        self.send("#{self.state}_at=", Time.now)
      end
    end
  end

  def do_state_change_do_after_callbacks
    # here we store a class variable for what happened so that we can use it in after commit
    # we can't simply use an instance variable because its possible the model in question
    # has more than one instance in memory and then the first instance is the only one that
    # would have the after_commit fire, we want to fire the after commit for the most recent
    # state change in the transaction not necessarily the one related to the first created
    # instance of a particular model
    # https://github.com/rails/rails/issues/19797
    old_state = resolve_old_state(is_saved: true)

    self.class.after_callbacks[id] = [old_state, state]
    self.class.run_after_transition_callbacks(state, self, old_state)
  end

  def do_state_change_do_after_commit_callbacks
    # we have to use an instance variable because the change was already committed and changed_attributes is empty
    previous_state, new_state = self.class.after_callbacks[id]

    if previous_state && new_state
      self.class.after_callbacks.delete(id)
      self.class.run_after_commit_transition_callbacks(new_state, self, previous_state)
    end
  end

  def save_state_change
    self.state_changes.create(
      previous_state: resolve_old_state(is_saved: false),
      next_state:     self.state,
      created_by_id:  self.last_edited_by_id || ARStateMachine.configuration.system_id
    )
  end

  def state_machine_validation
    old_state = resolve_old_state(is_saved: false)

    return if !self.state.present?
    return if old_state == self.state

    if !self.class.states.keys.include?(self.state.to_sym)
      errors.add(:state, "#{self.state} is not a valid state.")
    elsif will_save_change_to_state? && !allow_transition?(self.class.states, old_state, self.state)
      errors.add(:state, "Cannot transition from #{old_state} to #{self.state}.")
    end
  end

  def allow_transition?(states, from, to)
    first_state = self.class.states.first.first
    return (to.to_sym == first_state || self.skipped_transition.try(:to_sym) == first_state) if from.blank? # happens on new
    states[from.to_sym].include?(to.to_sym)
  end

  protected

  def should_overwrite_timestamp?(to_state)
    if self.respond_to?("overwrite_#{to_state}_at")
       # could be nil, want to assume we overwrite if it isn't exactly false
      !(self.send("overwrite_#{to_state}_at") == false)
    elsif self.class.respond_to?("overwrite_#{to_state}_at")
      !(self.class.send("overwrite_#{to_state}_at") == false)
    else
      true
    end
  end

  def set_state_by_id
    if self.respond_to?("#{self.state}_by_id")
      overwrite = if self.respond_to?("overwrite_#{self.state}_by_id")
        !(self.send("overwrite_#{self.state}_by_id") == false)
      elsif self.class.respond_to?("overwrite_#{self.state}_by_id")
        !(self.class.send("overwrite_#{self.state}_by_id") == false)
      else
        true
      end

      if self.send("#{self.state}_by_id").blank? || overwrite
        self.send("#{self.state}_by_id=", self.last_edited_by_id) if self.last_edited_by_id.present?
      end
    end
  end

  module ClassMethods
    def state_machine(states)
      @before_transitions_to ||= {}
      @after_transitions_to ||= {}
      @after_commit_transitions_to ||= {}
      @before_transitions_from ||= {}
      @after_transitions_from ||= {}
      @after_commit_transitions_from ||= {}
      @all_callbacks ||= []

      states_sym = states.keys.map(&:to_sym)

      self.after_callbacks ||= {}

      # normalize the format of states
      self.states = states.inject({}) do |h, (state, can)|
        can = [can] if can.class != Array
        state_s = state.to_s
        state_sym = state.to_sym
        can_sym = can.map(&:to_sym)

        # catch any coding errors with symbols that MUST match each other
        invalid_cans = (can_sym - states_sym)
        if invalid_cans.present?
          raise "Invalid transition defined from #{state_s} to [#{invalid_cans.join(", ")}] in #{self.name}."
        end
        h[state_sym] = can_sym
        h
      end

      self.states.keys.each do |state|
        ss = state.to_s
        sy = state.to_sym

        define_method "has_been_made_#{ss}?" do
          if self.respond_to?("#{ss}_at")
            self.send("#{ss}_at").present?
          else
            raise NotImplementedError, "Must add column #{ss}_at to the #{self.class.name.tableize} to use has_been_made_#{ss}?"
          end
        end

        define_method "has_not_been_made_#{ss}?" do
          !self.send("has_been_made_#{ss}?")
        end

        define_method "is_#{ss}?" do
          self.state.to_s == ss
        end

        define_method "make_#{ss}" do |last_edited_by_override = nil|
          self.last_edited_by_id = last_edited_by_override if last_edited_by_override
          self.state = ss

          # check that the state actually changed in case AR callback chain/transactions are ignored and it gets reverted
          self.save && (self.send("is_#{ss}?") || self.skipped_transition.to_s == ss)
        end

        define_method "is_not_#{ss}?" do
          !self.send("is_#{ss}?")
        end

        define_method "make_#{ss}!" do |last_edited_by_override = nil|
          self.last_edited_by_id = last_edited_by_override if last_edited_by_override
          self.state = ss
          self.save!

          if self.send("is_#{ss}?") || self.skipped_transition.to_s == ss
            true
          else
            messages = self.errors.map { |error| "#{error.attribute}=#{error.message}"}.join(" | ")

            raise StandardError.new("Cannot transition to #{ss}. #{messages}")
          end
        end

        can_make_function = "can_make_#{ss}?"
        if !respond_to?(can_make_function)
          define_method can_make_function do |user=nil, ability=nil|
            if user && ability.blank?
              ability = Ability.new(user)
            end
            allow_transition?(self.class.states, self.state, ss) && (ability.blank? || ability.can?(:change_state, self))
          end
        end

        scope ss,          -> { where(state: ss) }
        scope "not_#{ss}", -> { where.not(state: ss) }
      end
    end

    # this sets all the state names as a constant on the class so we can do things like Product::ACTIVE
    # instead of having string everywhere
    def const_missing(name)
      state_name = name.downcase
      return const_set(name, state_name.to_sym) if states && states.keys.include?(state_name)
      super(name)
    end

    def append_transitions_callback(states, method_or_block, rollback_on_failure, method_prefix)
      Array(states).map(&:to_sym).each do |state|
        transitions = yield(state)

        if method_or_block.respond_to?(:call)
          method = "_#{method_prefix}_#{state}_#{transitions.length}"
          @all_callbacks.push method
          define_method method, method_or_block
        else
          method = method_or_block
        end

        transitions.push(method: method, rollback_on_failure: rollback_on_failure)
      end
    end

    def before_transition_to(to, method = nil, rollback_on_failure: true, &block)
      append_transitions_callback(to, method || block, rollback_on_failure, 'before_transition_to') do |state|
        @before_transitions_to[state] ||= []
      end
    end

    def after_transition_to(to, method = nil, rollback_on_failure: true, &block)
      append_transitions_callback(to, method || block, rollback_on_failure, 'after_transition_to') do |state|
        @after_transitions_to[state] ||= []
      end
    end

    def after_commit_transition_to(to, method = nil, &block)
      append_transitions_callback(to, method || block, true, 'after_commit_to') do |state|
        @after_commit_transitions_to[state] ||= []
      end
    end

    def before_transition_from(from, method = nil, rollback_on_failure: true, &block)
      append_transitions_callback(from, method || block, rollback_on_failure, 'before_transition_from') do |state|
        @before_transitions_from[state] ||= []
      end
    end

    def after_transition_from(from, method = nil, rollback_on_failure: true, &block)
      append_transitions_callback(from, method || block, rollback_on_failure, 'after_transition_from') do |state|
        @after_transitions_from[state] ||= []
      end
    end

    def after_commit_transition_from(from, method = nil, &block)
      append_transitions_callback(from, method || block, true, 'after_commit_from') do |state|
        @after_commit_transitions_from[state] ||= []
      end
    end

    def process_callbacks(to, model, from, callbacks, ignore_result: false, raise_not_throw: false)
      # make sure these are all in the right order if there are to and from callbacks
      callbacks.sort_by! do |callback|
        @all_callbacks.index(callback)
      end

      callbacks.each do |callback|
        method_arity = model.method(callback[:method]).parameters.count
        arguments    = [from.to_sym, to.to_sym].take(method_arity)
        result       = model.send(callback[:method], *arguments)

        if !ignore_result && result == false
          # cancel others if any returned false

          if model.state == to # revert the state if AR won't and it hasn't been changed already
            model.state = from
            model.send("#{to}_at=", nil) if model.respond_to?("#{to}_at=")
          end

          if callback[:rollback_on_failure] == false
            break # just exit THIS chain; not the whole rails callback chain
          else
            # rollback changes / cancel subsequent other callbacks
            if raise_not_throw
              # after save callback chain is halted like this
              # https://github.com/rails/rails/issues/33192
              raise ActiveRecord::RecordInvalid, model
            else
              throw :abort
            end
          end
        end
      end
    end

    def run_after_commit_transition_callbacks(to, model, from)
      callbacks = Array(@after_commit_transitions_to[to.to_sym]) +
                  Array(@after_commit_transitions_from[from.to_sym])

      process_callbacks(to, model, from, callbacks, ignore_result: true) if callbacks.length > 0
    end

    def run_before_transition_callbacks(to, model, from)
      callbacks = Array(@before_transitions_to[to.to_sym]) +
                  Array(@before_transitions_from[from.to_sym])

      process_callbacks(to, model, from, callbacks) if callbacks.length > 0
    end

    def run_after_transition_callbacks(to, model, from)
      callbacks = Array(@after_transitions_to[to.to_sym]) +
                  Array(@after_transitions_from[from.to_sym])

      process_callbacks(to, model, from, callbacks, raise_not_throw: true) if callbacks.length > 0
    end
  end
end
