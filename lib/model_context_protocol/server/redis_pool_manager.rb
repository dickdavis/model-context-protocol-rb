module ModelContextProtocol
  class Server::RedisPoolManager
    attr_reader :pool

    def initialize(redis_url:, pool_size: 20, pool_timeout: 5, ssl_params: nil)
      @redis_url = redis_url
      @pool_size = pool_size
      @pool_timeout = pool_timeout
      @ssl_params = ssl_params
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

    def reap_now
      return unless @pool

      @pool.reap(idle_seconds: @reaper_config[:idle_timeout]) do |conn|
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
      redis_options = {url: @redis_url}
      # Only apply ssl_params for SSL connections (rediss://)
      if @ssl_params && @redis_url&.start_with?("rediss://")
        redis_options[:ssl_params] = @ssl_params
      end

      @pool = ConnectionPool.new(size: @pool_size, timeout: @pool_timeout) do
        Redis.new(**redis_options)
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
