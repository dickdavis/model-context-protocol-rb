require "json"
require "base64"

module ModelContextProtocol
  class Server::Pagination
    # Raised when an invalid cursor is provided
    class InvalidCursorError < StandardError; end

    DEFAULT_PAGE_SIZE = 100
    MAX_PAGE_SIZE = 1000

    PaginatedResponse = Data.define(:items, :next_cursor) do
      def serialized(key)
        result = {key => items}
        result[:nextCursor] = next_cursor if next_cursor
        result
      end
    end

    class << self
      def paginate(items, cursor: nil, page_size: DEFAULT_PAGE_SIZE, cursor_ttl: nil)
        page_size = [page_size, MAX_PAGE_SIZE].min
        offset = cursor ? decode_cursor(cursor) : 0
        page_items = items[offset, page_size] || []
        next_offset = offset + page_items.length
        next_cursor = if next_offset < items.length
          encode_cursor(next_offset, items.length, ttl: cursor_ttl)
        end

        PaginatedResponse[items: page_items, next_cursor: next_cursor]
      end

      def encode_cursor(offset, total, ttl: nil)
        data = {
          offset: offset,
          total: total,
          timestamp: Time.now.to_i
        }
        data[:expires_at] = Time.now.to_i + ttl if ttl

        Base64.urlsafe_encode64(JSON.generate(data), padding: false)
      end

      def decode_cursor(cursor, validate_ttl: true)
        data = JSON.parse(Base64.urlsafe_decode64(cursor))

        if validate_ttl && data["expires_at"] && Time.now.to_i > data["expires_at"]
          raise InvalidCursorError, "Cursor has expired"
        end

        data["offset"]
      rescue JSON::ParserError, ArgumentError => e
        raise InvalidCursorError, "Invalid cursor format: #{e.message}"
      end

      def pagination_requested?(params)
        params.key?("cursor") || params.key?("pageSize")
      end

      def extract_pagination_params(params, default_page_size: DEFAULT_PAGE_SIZE, max_page_size: MAX_PAGE_SIZE)
        page_size = if params["pageSize"]
          [params["pageSize"].to_i, max_page_size].min
        else
          default_page_size
        end

        {cursor: params["cursor"], page_size:}
      end
    end
  end
end
