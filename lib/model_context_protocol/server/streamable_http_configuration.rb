module ModelContextProtocol
  # Settings for servers that communicate via the MCP streamable HTTP transport, typically
  # used by Rack applications serving multiple clients concurrently with Redis-backed coordination.
  #
  # Created by Server.with_streamable_http_transport, which yields an instance to a configuration
  # block before passing it to Router. Adds session management (require_sessions), CORS control
  # (validate_origin, allowed_origins), and connection timeouts (session_ttl, ping_timeout) on
  # top of the base class. Requires RedisConfig.configured? to be true at validation time because
  # StreamableHttpTransport stores session state, cursor data, and cross-server notifications in Redis.
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

    # Check whether session IDs are mandatory for incoming requests.
    # StreamableHttpTransport reads this at request handling time to decide whether
    # to reject requests without session_id query parameters.
    #
    # @return [Boolean] false by default (sessions are optional)
    def require_sessions
      @require_sessions.nil? ? false : @require_sessions
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

    # Verify that Redis is configured before allowing HTTP transport.
    # Overrides the base class template method; called by validate! after checking name/version/registry.
    # StreamableHttpTransport requires Redis for SessionStore (client state), NotificationQueue
    # (cross-server messages), and StreamRegistry (active connections), so it cannot function without it.
    #
    # @raise [InvalidTransportError] if RedisConfig.configured? returns false
    # @return [void]
    def validate_transport!
      unless ModelContextProtocol::Server::RedisConfig.configured?
        raise InvalidTransportError,
          "streamable_http transport requires Redis. Call Server.configure_redis first."
      end
    end
  end
end
