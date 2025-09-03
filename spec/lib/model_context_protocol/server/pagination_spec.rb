require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Pagination do
  describe ".paginate" do
    let(:items) { (1..250).map { |i| {id: i, name: "Item #{i}"} } }

    it "returns first page when no cursor provided" do
      result = described_class.paginate(items, page_size: 100)

      aggregate_failures do
        expect(result.items.length).to eq(100)
        expect(result.items.first[:id]).to eq(1)
        expect(result.items.last[:id]).to eq(100)
        expect(result.next_cursor).not_to be_nil
      end
    end

    it "returns subsequent page with cursor" do
      first_page = described_class.paginate(items, page_size: 100)
      second_page = described_class.paginate(
        items,
        cursor: first_page.next_cursor,
        page_size: 100
      )

      aggregate_failures do
        expect(second_page.items.length).to eq(100)
        expect(second_page.items.first[:id]).to eq(101)
        expect(second_page.items.last[:id]).to eq(200)
        expect(second_page.next_cursor).not_to be_nil
      end
    end

    it "returns nil cursor on last page" do
      first_page = described_class.paginate(items, page_size: 100)
      second_page = described_class.paginate(
        items,
        cursor: first_page.next_cursor,
        page_size: 100
      )
      last_page = described_class.paginate(
        items,
        cursor: second_page.next_cursor,
        page_size: 100
      )

      aggregate_failures do
        expect(last_page.items.length).to eq(50)
        expect(last_page.items.first[:id]).to eq(201)
        expect(last_page.items.last[:id]).to eq(250)
        expect(last_page.next_cursor).to be_nil
      end
    end

    it "handles empty collections" do
      result = described_class.paginate([], page_size: 10)

      aggregate_failures do
        expect(result.items).to be_empty
        expect(result.next_cursor).to be_nil
      end
    end

    it "handles page size larger than collection" do
      small_items = [{id: 1}, {id: 2}, {id: 3}]
      result = described_class.paginate(small_items, page_size: 100)

      aggregate_failures do
        expect(result.items.length).to eq(3)
        expect(result.next_cursor).to be_nil
      end
    end

    it "respects max page size" do
      result = described_class.paginate(items, page_size: 2000)

      expect(result.items.length).to eq([items.length, described_class::MAX_PAGE_SIZE].min)
    end

    it "handles single item per page" do
      result = described_class.paginate(items, page_size: 1)

      aggregate_failures do
        expect(result.items.length).to eq(1)
        expect(result.items.first[:id]).to eq(1)
        expect(result.next_cursor).not_to be_nil
      end
    end
  end

  describe "cursor encoding/decoding" do
    it "creates opaque cursor strings" do
      encoded_cursor = described_class.encode_cursor(100, 500)
      decoded_cursor = described_class.decode_cursor(encoded_cursor)

      aggregate_failures do
        expect(encoded_cursor).to be_a(String)
        expect(encoded_cursor).not_to include("100")
        expect(encoded_cursor).not_to include("500")
        expect(decoded_cursor).to eq(100)
      end
    end

    it "includes TTL in cursor when provided" do
      cursor = described_class.encode_cursor(50, 200, ttl: 3600)
      offset = described_class.decode_cursor(cursor)

      expect(offset).to eq(50)
    end

    it "validates TTL when decoding" do
      cursor = described_class.encode_cursor(50, 200, ttl: -1) # Expired 1 second ago

      expect {
        described_class.decode_cursor(cursor)
      }.to raise_error(ModelContextProtocol::Server::Pagination::InvalidCursorError, /expired/)
    end

    it "skips TTL validation when requested" do
      cursor = described_class.encode_cursor(50, 200, ttl: -1)
      offset = described_class.decode_cursor(cursor, validate_ttl: false)

      expect(offset).to eq(50)
    end

    it "raises error for invalid cursor" do
      expect {
        described_class.decode_cursor("invalid_cursor")
      }.to raise_error(ModelContextProtocol::Server::Pagination::InvalidCursorError, /Invalid cursor format/)
    end

    it "raises error for malformed base64" do
      expect {
        described_class.decode_cursor("not-valid-base64!")
      }.to raise_error(ModelContextProtocol::Server::Pagination::InvalidCursorError)
    end

    it "handles cursor with no TTL" do
      cursor = described_class.encode_cursor(25, 100)
      offset = described_class.decode_cursor(cursor)

      expect(offset).to eq(25)
    end
  end

  describe ".pagination_requested?" do
    it "returns true when cursor is provided" do
      params = {"cursor" => "some_cursor"}
      expect(described_class.pagination_requested?(params)).to be true
    end

    it "returns true when pageSize is provided" do
      params = {"pageSize" => 50}
      expect(described_class.pagination_requested?(params)).to be true
    end

    it "returns true when both cursor and pageSize are provided" do
      params = {"cursor" => "cursor", "pageSize" => 50}
      expect(described_class.pagination_requested?(params)).to be true
    end

    it "returns false when neither is provided" do
      params = {}
      expect(described_class.pagination_requested?(params)).to be false
    end

    it "returns false for unrelated params" do
      params = {"other_param" => "value"}
      expect(described_class.pagination_requested?(params)).to be false
    end
  end

  describe ".extract_pagination_params" do
    it "extracts cursor and pageSize" do
      params = {"cursor" => "test_cursor", "pageSize" => 25}
      result = described_class.extract_pagination_params(params)

      aggregate_failures do
        expect(result[:cursor]).to eq("test_cursor")
        expect(result[:page_size]).to eq(25)
      end
    end

    it "uses default page size when not provided" do
      params = {"cursor" => "test_cursor"}
      result = described_class.extract_pagination_params(params)

      expect(result[:page_size]).to eq(described_class::DEFAULT_PAGE_SIZE)
    end

    it "uses custom defaults" do
      params = {}
      result = described_class.extract_pagination_params(
        params,
        default_page_size: 50,
        max_page_size: 200
      )

      expect(result[:page_size]).to eq(50)
    end

    it "respects max page size" do
      params = {"pageSize" => 5000}
      result = described_class.extract_pagination_params(
        params,
        max_page_size: 500
      )

      expect(result[:page_size]).to eq(500)
    end

    it "converts string pageSize to integer" do
      params = {"pageSize" => "75"}
      result = described_class.extract_pagination_params(params)

      expect(result[:page_size]).to eq(75)
    end

    it "handles invalid pageSize gracefully" do
      params = {"pageSize" => "invalid"}
      result = described_class.extract_pagination_params(params)

      expect(result[:page_size]).to eq(0)
    end
  end

  describe "PaginatedResponse#serialized" do
    it "includes nextCursor when present" do
      response = described_class::PaginatedResponse.new(
        items: [{id: 1}],
        next_cursor: "test_cursor"
      )

      result = response.serialized(:testKey)

      expect(result).to eq({
        testKey: [{id: 1}],
        nextCursor: "test_cursor"
      })
    end

    it "omits nextCursor when nil" do
      response = described_class::PaginatedResponse.new(
        items: [{id: 1}],
        next_cursor: nil
      )

      result = response.serialized(:testKey)

      expect(result).to eq({
        testKey: [{id: 1}]
      })
    end
  end
end
