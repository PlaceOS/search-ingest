require "./error"

module RubberSoul
  # Borrowed with modifications from `crystal-db`
  # TODO: Generalise crystal-db ConnectionPool to seperate library
  class Pool(T)
    @initial_pool : Int32

    # maximum amount of objects in the pool. Either available or in use.
    @max_pool : Int32
    @available = Set(T).new
    @total = [] of T
    @timeout : Float64

    def initialize(
      @initial_pool = 1,
      @max_pool = 0,
      @max_idle_pool = 1,
      @timeout = 1.0,
      &@factory : -> T
    )
      @initial_pool.times { build_resource }

      @availability_channel = Channel(Nil).new
      @waiting_resource = 0
      @mutex = Mutex.new
    end

    # Close off connections in the pool of GC
    #
    def finalize
      close
    end

    # Close all resources in the pool
    #
    def close : Nil
      @total.each &.close
      @total.clear
      @available.clear
    end

    def available_resources
      @available.size
    end

    # - Checks out resource to captured block, blocks until resource attained
    # - Yields resource to block
    # - Releases resource on block return
    #
    def acquire
      connection = checkout
      result = yield connection
      release(connection)
      result
    end

    # Acquire connection from pool, block until connection available
    #
    protected def checkout : T
      resource = if @available.empty?
                   if can_increase_pool?
                     build_resource
                   else
                     wait_for_available
                     pick_available
                   end
                 else
                   pick_available
                 end

      @available.delete resource
      resource
    end

    # Release connection to the pool
    #
    private def release(resource : T) : Nil
      if can_increase_idle_pool?
        @available << resource
        @availability_channel.send nil if are_waiting_for_resource?
      else
        resource.close
        @total.delete(resource)
      end
    end

    # :nodoc:
    def each_available
      @available.each do |resource|
        yield resource
      end
    end

    # Generate a resource and place in the pool
    private def build_resource : T
      resource = @factory.call
      @total << resource
      @available << resource
      resource
    end

    private def can_increase_pool?
      @max_pool == 0 || @total.size < @max_pool
    end

    private def can_increase_idle_pool?
      @available.size < @max_idle_pool
    end

    private def pick_available
      @available.first
    end

    private def wait_for_available
      timeout = TimeoutHelper.new(@timeout)
      inc_waiting_resource

      timeout.start
      index, _ = Channel.select(@availability_channel.receive_select_action, timeout.receive_select_action)

      case TimeoutHelper::Event.from_value?(index)
      when TimeoutHelper::Event::Ready
        timeout.cancel
        dec_waiting_resource
      when TimeoutHelper::Event::Timeout
        dec_waiting_resource
        raise Error::PoolTimeout.new
      else
        raise Error.new
      end
    end

    private def inc_waiting_resource
      @mutex.synchronize do
        @waiting_resource += 1
      end
    end

    private def dec_waiting_resource
      @mutex.synchronize do
        @waiting_resource -= 1
      end
    end

    private def are_waiting_for_resource?
      @mutex.synchronize do
        @waiting_resource > 0
      end
    end

    class TimeoutHelper
      enum Event
        Ready
        Timeout
      end

      def initialize(@timeout : Float64)
        @abort_timeout = false
        @timeout_channel = Channel(Nil).new
      end

      def receive_select_action
        @timeout_channel.receive_select_action
      end

      def start
        spawn do
          sleep @timeout
          unless @abort_timeout
            @timeout_channel.send nil
          end
        end
      end

      def cancel
        @abort_timeout = true
      end
    end
  end
end
