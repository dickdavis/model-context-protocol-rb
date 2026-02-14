require "uri"

module ModelContextProtocol
  # Settings for servers that communicate via the MCP streamable HTTP transport, typically
  # used by Rack applications serving multiple clients concurrently with Redis-backed coordination.
  #
  # Created by Server.with_streamable_http_transport, which yields an instance to a configuration
  # block before passing it to Router. Adds session management (require_sessions), CORS control
  # (validate_origin, allowed_origins), connection timeouts (session_ttl, ping_timeout), and
  # Redis connection pool settings (redis_url, redis_pool_size, etc.) on top of the base class.
  # validate_transport! verifies that redis_url is a valid Redis URL, and setup_transport!
  # configures the Redis connection pool via RedisConfig before the server starts.
  #
  # Router queries supports_list_changed? (true for this subclass, false for stdio) to advertise
  # listChanged capabilities in the initialize response. StreamableHttpTransport reads require_sessions,
  # validate_origin, allowed_origins, session_ttl, and ping_timeout directly from this configuration.
  class Server::StreamableHttpConfiguration < Server::Configuration
    # @return [Symbol] :streamable_http (used by Server.start to instantiate StreamableHttpTransport)
    def transport_type = :streamable_http

    # @return [Boolean] true (Router advertises listChanged in initialize response capabilities;
    #   StreamableHttpTransport can push unsolicited notifications to clients)
    def supports_list_changed? = true

    # @!attribute [w] require_sessions
    #   Whether to enforce that clients send a session ID with each request.
    #   StreamableHttpTransport checks this and returns 400 Bad Request if session_id is missing.
    #   @see StreamableHttpTransport#handle
    attr_writer :require_sessions

    # @!attribute [w] validate_origin
    #   Whether to enforce CORS origin validation against allowed_origins.
    #   StreamableHttpTransport checks this in the OPTIONS preflight handler.
    #   @see StreamableHttpTransport#handle
    attr_writer :validate_origin

    # @!attribute [w] allowed_origins
    #   List of origins permitted in CORS requests; checked by StreamableHttpTransport
    #   when validate_origin is true. Supports exact strings or "*" wildcard.
    #   @see StreamableHttpTransport#handle
    attr_writer :allowed_origins

    # @!attribute [w] session_ttl
    #   How long (in seconds) Redis session entries persist after last activity.
    #   StreamableHttpTransport passes this to SessionStore.new to set key expiration.
    #   @see StreamableHttpTransport#initialize
    attr_writer :session_ttl

    # @!attribute [w] ping_timeout
    #   How long (in seconds) to wait for ping responses before considering a stream dead.
    #   StreamableHttpTransport passes this to StreamMonitor to detect stale connections.
    #   @see StreamableHttpTransport#initialize
    attr_writer :ping_timeout

    # @!attribute [w] redis_url
    #   The Redis connection URL (redis:// or rediss:// scheme). Required.
    #   Passed to RedisConfig during setup_transport! to create the connection pool.
    attr_writer :redis_url

    # @!attribute [w] redis_pool_size
    #   Number of Redis connections in the pool.
    #   Passed to RedisConfig during setup_transport!.
    attr_writer :redis_pool_size

    # @!attribute [w] redis_pool_timeout
    #   Seconds to wait for a connection from the pool before raising.
    #   Passed to RedisConfig during setup_transport!.
    attr_writer :redis_pool_timeout

    # @!attribute [w] redis_ssl_params
    #   SSL parameters for Redis connections (e.g., { verify_mode: OpenSSL::SSL::VERIFY_NONE }).
    #   Passed to RedisConfig during setup_transport!.
    attr_writer :redis_ssl_params

    # @!attribute [w] redis_enable_reaper
    #   Whether to enable the idle connection reaper thread.
    #   Passed to RedisConfig during setup_transport!.
    attr_writer :redis_enable_reaper

    # @!attribute [w] redis_reaper_interval
    #   How often (in seconds) the reaper checks for idle connections.
    #   Passed to RedisConfig during setup_transport!.
    attr_writer :redis_reaper_interval

    # @!attribute [w] redis_idle_timeout
    #   How long (in seconds) a connection can sit idle before the reaper closes it.
    #   Passed to RedisConfig during setup_transport!.
    attr_writer :redis_idle_timeout

    # Check whether session IDs are mandatory for incoming requests.
    # StreamableHttpTransport reads this at request handling time to decide whether
    # to reject requests without session_id query parameters.
    #
    # @return [Boolean] true by default (sessions are required)
    def require_sessions
      @require_sessions.nil? ? true : @require_sessions
    end

    # Check whether CORS origin validation is enforced.
    # StreamableHttpTransport reads this during OPTIONS preflight handling to decide
    # whether to reject requests with disallowed Origin headers.
    #
    # @return [Boolean] true by default (validate origins against allowed_origins list)
    def validate_origin
      @validate_origin.nil? ? true : @validate_origin
    end

    # Retrieve the list of permitted CORS origins.
    # StreamableHttpTransport reads this during OPTIONS preflight handling to check
    # the request's Origin header against allowed values.
    #
    # @return [Array<String>] list of allowed origins (localhost on standard ports by default);
    #   supports exact matches or "*" for any origin
    def allowed_origins
      @allowed_origins || DEFAULT_ALLOWED_ORIGINS
    end

    # Retrieve the session expiration time in seconds.
    # StreamableHttpTransport passes this to SessionStore.new, which sets Redis key TTLs
    # to automatically expire inactive sessions.
    #
    # @return [Integer] seconds until session data expires (3600 = 1 hour by default)
    def session_ttl
      @session_ttl || 3600
    end

    # Retrieve the ping response timeout in seconds.
    # StreamableHttpTransport passes this to StreamMonitor, which closes streams that
    # don't respond to ping messages within this window (indicating client disconnection
    # or network failure).
    #
    # @return [Integer] seconds to wait for ping responses (10 seconds by default)
    def ping_timeout
      @ping_timeout || 10
    end

    # @return [String, nil] the Redis connection URL
    attr_reader :redis_url

    # @return [Integer] number of Redis connections in the pool (default: 20)
    def redis_pool_size
      @redis_pool_size || 20
    end

    # @return [Integer] seconds to wait for a pool connection (default: 5)
    def redis_pool_timeout
      @redis_pool_timeout || 5
    end

    # @return [Hash, nil] SSL parameters for Redis connections
    attr_reader :redis_ssl_params

    # @return [Boolean] whether the idle connection reaper is enabled (default: true)
    def redis_enable_reaper
      @redis_enable_reaper.nil? ? true : @redis_enable_reaper
    end

    # @return [Integer] seconds between reaper checks (default: 60)
    def redis_reaper_interval
      @redis_reaper_interval || 60
    end

    # @return [Integer] seconds before idle connections are reaped (default: 300)
    def redis_idle_timeout
      @redis_idle_timeout || 300
    end

    private

    # Default CORS origins permitted for HTTP transport: localhost and 127.0.0.1 on both HTTP and HTTPS.
    # StreamableHttpTransport uses this list when allowed_origins hasn't been explicitly set,
    # allowing development and testing without additional configuration. Production deployments
    # should override with actual client origins or ["*"] for unrestricted access.
    #
    # @return [Array<String>] four localhost variants with http/https and localhost/127.0.0.1
    DEFAULT_ALLOWED_ORIGINS = [
      "http://localhost", "https://localhost",
      "http://127.0.0.1", "https://127.0.0.1"
    ].freeze

    # Verify that redis_url is a valid Redis URL before allowing HTTP transport.
    # Overrides the base class template method; called by validate! after checking name/version/registry.
    # Uses URI parsing ("parse, don't validate") to catch nil, empty, malformed, and non-Redis URLs.
    #
    # @raise [InvalidTransportError] if redis_url is nil, empty, malformed, or not a redis:// / rediss:// URL
    # @return [void]
    def validate_transport!
      uri = URI.parse(redis_url.to_s)
      unless %w[redis rediss].include?(uri.scheme)
        raise InvalidTransportError,
          "streamable_http transport requires a valid Redis URL (redis:// or rediss://). " \
          "Set config.redis_url in the configuration block."
      end
    rescue URI::InvalidURIError
      raise InvalidTransportError,
        "streamable_http transport requires a valid Redis URL (redis:// or rediss://). " \
        "Set config.redis_url in the configuration block."
    end

    # Configure the Redis connection pool via RedisConfig.
    # Overrides the base class template method; called by Server.build_server after validate! passes.
    # Maps the redis_* attributes on this configuration to the corresponding RedisConfig::Configuration
    # attributes, then starts the pool manager.
    #
    # @return [void]
    def setup_transport!
      ModelContextProtocol::Server::RedisConfig.configure do |redis_config|
        redis_config.redis_url = redis_url
        redis_config.pool_size = redis_pool_size
        redis_config.pool_timeout = redis_pool_timeout
        redis_config.enable_reaper = redis_enable_reaper
        redis_config.reaper_interval = redis_reaper_interval
        redis_config.idle_timeout = redis_idle_timeout
        redis_config.ssl_params = redis_ssl_params
      end
    end
  end
end
