require "ar_state_machine/version"
require "ar_state_machine/configuration"
require "active_record"

module ARStateMachine
  extend ActiveSupport::Concern

  included do
    cattr_accessor    :states

    attr_accessor     :last_edited_by_id
    attr_accessor     :skipped_transition

    after_initialize  :state_machine_set_initial_state
    before_update     :do_state_change_before_callbacks,
                      if: "state_changed? or (skipped_transition and skipped_transition.to_s == state.to_s)"
    after_update      :do_state_change_do_after_callbacks,
                      if: "state_changed? or (skipped_transition and skipped_transition.to_s == state.to_s)"
    before_update     :save_state_change,
                      if: "state_changed? or (skipped_transition and skipped_transition.to_s == state.to_s)"
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

  def old_state
    old_state = self.changed_attributes['state']

    # we usually only want to create the state change if the state actually changes but
    #   we also want to create it if it fails to transition from a state and stays there
    #   example: a SubscriptionSeason in errored attempts to move to purchased, the order
    #   fails to build and it goes back to errored. We want to log the attempt.
    #   we also want to do any callbacks
    old_state ||= skipped_transition if skipped_transition.to_s == state.to_s

    old_state
  end

  def do_state_change_do_after_callbacks
    self.class.run_after_transition_callbacks(self.state, self, old_state) if self.state_changed?
  end

  # Set up something like https://github.com/wantable/card_connect_gateway/blob/master/lib/card_connect_gateway/configuration.rb
  # for the SYSTEM ID. shouldn't require USER at all. oops.
  # Also add config to turn state changing on and off altogether.

  def save_state_change
    return unless ArStateMachine.configuration.should_log_state_change
    self.state_changes.create({
      previous_state: old_state,
      next_state:     self.state,
      created_by_id:  self.last_edited_by_id || ArStateMachine.configuration.system_id
    })
  end

  def do_state_change_before_callbacks
    rollback = self.class.run_before_transition_callbacks(self.state, self, old_state)
    if self.skipped_transition and self.respond_to?("#{self.skipped_transition}_at=")
      self.send("#{self.skipped_transition}_at=", Time.now)
    end
    if self.respond_to?("#{self.state}_at=")
      overwrite = true
      if self.respond_to?("overwrite_#{self.state}_at")
         # could be nil, want to assume we overwrite if it isn't exactly false
        overwrite = !(self.send("overwrite_#{self.state}_at") == false)
      elsif self.class.respond_to?("overwrite_#{self.state}_at")
        overwrite = !(self.class.send("overwrite_#{self.state}_at") == false)
      end
      if self.send("#{self.state}_at").blank? or overwrite
        self.send("#{self.state}_at=", Time.now)
      end
    end
    rollback
  end

  def state_machine_validation
    return if !self.state.present?
    if !self.class.states.keys.include?(self.state.to_sym)
      self.errors[:state] << "#{self.state} is not a valid state."
    elsif self.state_changed? and !allow_transition?(self.class.states, old_state, self.state)
      self.errors[:state] << "Cannot transition from #{old_state} to #{self.state}."
    end
  end

  def state_machine_set_initial_state
    self.state ||= self.class.states.first.first
  end

  def allow_transition?(states, from, to)
    first_state = self.class.states.first.first
    return (to.to_sym == first_state or self.skipped_transition.try(:to_sym) == first_state) if from.blank? # happens on new
    states[from.to_sym].include?(to.to_sym)
  end


  module ActiveRecordExtensions
    def state_machine(states)
      include ARStateMachine
      self.setup(states)
    end
  end

  module ClassMethods
    def setup(states)
      @before_transitions ||= {}
      @after_transitions ||= {}

      states_sym = states.keys.map(&:to_sym)

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
          self.state = ss
          self.last_edited_by_id = last_edited_by_override if last_edited_by_override

          if self.respond_to?("#{ss}_by_id=") and last_edited_by_id
            self.send("#{ss}_by_id=", last_edited_by_id)
          end
          # check that the state actually changed in case AR callback chain/transactions are ignored and it gets reverted
          self.save and (self.send("is_#{ss}?") || self.skipped_transition.to_s == ss)
        end
        define_method "is_not_#{ss}?" do
          !self.send("is_#{ss}?")
        end
        define_method "make_#{ss}!" do |last_edited_by_override = nil|
          self.last_edited_by_id = last_edited_by_override if last_edited_by_override
          self.state = ss
          if self.respond_to?("#{ss}_by_id=") and last_edited_by_id
            self.send("#{ss}_by_id=", last_edited_by_id)
          end
          self.save!
          if self.send("is_#{ss}?") or self.skipped_transition.to_s == ss
            true
          else
            messages = self.errors.map{|x, y| "#{x}=#{y}"}.join(" | ")
            raise Exception.new("Cannot transition to #{ss}. #{messages}")
          end
        end
        can_make_function = "can_make_#{ss}?"
        if !respond_to?(can_make_function)
          define_method can_make_function do |user=nil, ability=nil|
            if user and ability.blank?
              ability = Ability.new(user)
            end
            allow_transition?(self.class.states, self.state, ss) and (ability.blank? or ability.can?(:change_state, self))
          end
        end

        self.class.send :define_method, ss do
          where(state: ss)
        end

        self.class.send :define_method, "not_#{ss}" do
          where.not(state: ss)
        end
      end
    end

    # this sets all the state names as a constant on the class so we can do things like Product::ACTIVE
    # instead of having string everywhere
    def const_missing(name)
      state_name = name.downcase
      return const_set(name, state_name.to_sym) if self.states.keys.include?(state_name)
      super(name)
    end

    def before_transition_to(to, method=nil, rollback_on_failure=true, &block)
      if to.class != Array
        to = [to]
      end
      to.each do |to_|
        @before_transitions[to_.to_sym] ||= []
        if !method.present?
          method = "_before_transitions_#{to_.to_sym}_#{@before_transitions[to_.to_sym].length}"
          define_method method, block
        end

        @before_transitions[to_.to_sym].push({method: method, rollback_on_failure: rollback_on_failure})
      end
      true
    end

    def after_transition_to(to, method=nil, &block)
      if to.class != Array
        to = [to]
      end
      to.each do |to_|
        @after_transitions[to_.to_sym] ||= []
        if !method.present?
          method = "_after_transition_to_#{to_.to_sym}_#{@after_transitions[to_.to_sym].length}"
          define_method method, block
        end

        @after_transitions[to_.to_sym].push({method: method}) # AR doesn't do rollbacks for after_* callbacks
      end
      true
    end

    def process_callbacks(to, model, from, callbacks)
      callbacks.each do |callback|
        args = case model.method(callback[:method]).parameters.count
        when 1
          [from.to_sym]
        when 2
          [from.to_sym, to.to_sym]
        else
          []
        end

        if model.send(callback[:method], *args) == false

          # cancel others if any returned false

          if model.state == to # revert the state if AR won't and it hasn't been changed already
            model.state = from
            if model.respond_to?("#{to}_at=")
              model.send("#{to}_at=", nil)
            end
          end

          if callback[:rollback_on_failure] == false
            break # just exit THIS chain; not the whole rails callback chain
          else
            # rollback changes / cancel subsequent other callbacks
            return false
          end
        end
      end
      true
    end

    def run_before_transition_callbacks(to, model, from)
      callbacks = @before_transitions[to.to_sym]
      return process_callbacks(to, model, from, callbacks) if callbacks
    end

    def run_after_transition_callbacks(to, model, from)
      callbacks = @after_transitions[to.to_sym]
      return process_callbacks(to, model, from, callbacks) if callbacks
    end
  end
end
ActiveRecord::Base.extend(ARStateMachine::ActiveRecordExtensions)