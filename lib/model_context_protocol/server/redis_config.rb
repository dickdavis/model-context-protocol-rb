require "singleton"

module ModelContextProtocol
  class Server::RedisConfig
    include Singleton

    class NotConfiguredError < StandardError
      def initialize
        super("Redis not configured. Set redis_url in the StreamableHttpConfiguration block.")
      end
    end

    attr_reader :manager

    def self.configure(&block)
      instance.configure(&block)
    end

    def self.configured?
      instance.configured?
    end

    def self.pool
      instance.pool
    end

    def self.shutdown!
      instance.shutdown!
    end

    def self.reset!
      instance.reset!
    end

    def self.stats
      instance.stats
    end

    def initialize
      reset!
    end

    def configure(&block)
      shutdown! if configured?

      config = Configuration.new
      yield(config) if block_given?

      @manager = Server::RedisPoolManager.new(
        redis_url: config.redis_url,
        pool_size: config.pool_size,
        pool_timeout: config.pool_timeout,
        ssl_params: config.ssl_params
      )

      if config.enable_reaper
        @manager.configure_reaper(
          enabled: true,
          interval: config.reaper_interval,
          idle_timeout: config.idle_timeout
        )
      end

      @manager.start
    end

    def configured?
      !@manager.nil? && !@manager.pool.nil?
    end

    def pool
      raise NotConfiguredError unless configured?
      @manager.pool
    end

    def shutdown!
      @manager&.shutdown
      @manager = nil
    end

    def reset!
      shutdown!
      @manager = nil
    end

    def stats
      return {} unless configured?
      @manager.stats
    end

    class Configuration
      attr_accessor :redis_url, :pool_size, :pool_timeout,
        :enable_reaper, :reaper_interval, :idle_timeout, :ssl_params

      def initialize
        @redis_url = nil
        @pool_size = 20
        @pool_timeout = 5
        @enable_reaper = true
        @reaper_interval = 60
        @idle_timeout = 300
        @ssl_params = nil
      end
    end
  end
end
