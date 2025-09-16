module ModelContextProtocol
  class Server::RedisPoolManager
    attr_reader :pool, :reaper_thread

    def initialize(redis_url:, pool_size: 20, pool_timeout: 5)
      @redis_url = redis_url
      @pool_size = pool_size
      @pool_timeout = pool_timeout
      @pool = nil
      @reaper_thread = nil
      @reaper_config = {
        enabled: false,
        interval: 60,
        idle_timeout: 300
      }
    end

    def configure_reaper(enabled:, interval: 60, idle_timeout: 300)
      @reaper_config = {
        enabled: enabled,
        interval: interval,
        idle_timeout: idle_timeout
      }
    end

    def start
      validate!
      create_pool
      start_reaper if @reaper_config[:enabled]
      true
    end

    def shutdown
      stop_reaper
      close_pool
    end

    def healthy?
      return false unless @pool

      @pool.with do |conn|
        conn.ping == "PONG"
      end
    rescue
      false
    end

    def reap_now
      return unless @pool

      @pool.reap(@reaper_config[:idle_timeout]) do |conn|
        conn.close
      end
    end

    def stats
      return {} unless @pool

      {
        size: @pool.size,
        available: @pool.available,
        idle: @pool.instance_variable_get(:@idle_since)&.size || 0
      }
    end

    private

    def validate!
      raise ArgumentError, "redis_url is required" if @redis_url.nil? || @redis_url.empty?
      raise ArgumentError, "pool_size must be positive" if @pool_size <= 0
      raise ArgumentError, "pool_timeout must be positive" if @pool_timeout <= 0
    end

    def create_pool
      @pool = ConnectionPool.new(size: @pool_size, timeout: @pool_timeout) do
        Redis.new(url: @redis_url)
      end
    end

    def close_pool
      @pool&.shutdown { |conn| conn.close }
      @pool = nil
    end

    def start_reaper
      return if @reaper_thread&.alive?

      @reaper_thread = Thread.new do
        loop do
          sleep @reaper_config[:interval]
          begin
            reap_now
          rescue => e
            warn "Redis reaper error: #{e.message}"
          end
        end
      end

      @reaper_thread.name = "MCP-Redis-Reaper"
    end

    def stop_reaper
      return unless @reaper_thread&.alive?

      @reaper_thread.kill
      @reaper_thread.join(5)
      @reaper_thread = nil
    end
  end
end
