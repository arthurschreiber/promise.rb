# encoding: utf-8

require 'promise/version'

require 'promise/callback'
require 'promise/progress'
require 'promise/group'

class Promise
  Error = Class.new(RuntimeError)
  BrokenError = Class.new(Error)

  include Promise::Progress

  attr_accessor :source
  attr_reader :state, :value, :reason

  def self.resolve(obj = nil)
    return obj if obj.is_a?(self)
    new.tap { |promise| promise.fulfill(obj) }
  end

  def self.all(enumerable)
    Group.new(new, enumerable).promise
  end

  def self.map_value(obj)
    if obj.is_a?(Promise)
      obj.then { |value| yield value }
    else
      yield obj
    end
  end

  def self.sync(obj)
    obj.is_a?(Promise) ? obj.sync : obj
  end

  def initialize
    @state = :pending
    @callbacks = []
  end

  def pending?
    state.equal?(:pending)
  end

  def fulfilled?
    state.equal?(:fulfilled)
  end

  def rejected?
    state.equal?(:rejected)
  end

  def then(on_fulfill = nil, on_reject = nil)
    on_fulfill = Proc.new if on_fulfill.nil? && block_given?
    next_promise = self.class.new

    add_callback(Callback.new(on_fulfill, on_reject, next_promise))
    next_promise
  end

  def rescue(&block)
    self.then(nil, block)
  end
  alias_method :catch, :rescue

  def sync
    if pending?
      wait
      raise BrokenError if pending?
    end
    raise reason if rejected?
    value
  end

  def fulfill(value = nil)
    return self unless pending?

    if Promise === value
      value.add_callback(self)
    else
      @state = :fulfilled
      @source = nil
      @value = value

      dispatch
    end
    self
  end

  def reject(reason = nil)
    return self unless pending?

    @state = :rejected
    @source = nil
    @reason = reason_coercion(reason || Error)

    dispatch

    self
  end

  # Override to support sync on a promise without a source or to wait
  # for deferred callbacks on the source
  def wait
    while source
      saved_source = source
      saved_source.wait
      break if saved_source.equal?(source)
    end
  end

  protected

  # Override to defer calling the callback for Promises/A+ spec compliance
  def defer
    yield
  end

  def add_callback(callback)
    if pending?
      @callbacks << callback
      callback.source = self
    else
      dispatch!(callback)
    end
  end

  private

  def reason_coercion(reason)
    case reason
    when Exception
      reason.set_backtrace(caller) unless reason.backtrace
    when Class
      reason = reason_coercion(reason.new) if reason <= Exception
    end
    reason
  end

  def dispatch
    @callbacks.each { |callback| dispatch!(callback) }
  end

  def dispatch!(callback)
    defer do
      if fulfilled?
        callback.fulfill(value)
      else
        callback.reject(reason)
      end
    end
  end
end
