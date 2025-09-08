require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::NotificationQueue do
  subject(:queue) { described_class.new(redis, server_instance, max_size: max_size) }

  let(:redis) { MockRedis.new }
  let(:server_instance) { "test-server-123" }
  let(:max_size) { 5 }
  let(:sample_notification) do
    {
      jsonrpc: "2.0",
      method: "test_method",
      params: {data: "test_data"}
    }
  end

  def serialized(notification)
    JSON.parse(notification.to_json)
  end

  def serialized_array(notifications)
    notifications.map { |n| serialized(n) }
  end

  before do
    redis.flushdb
  end

  describe "#initialize" do
    it "creates a queue with the correct configuration" do
      aggregate_failures do
        expect(queue.instance_variable_get(:@redis)).to eq(redis)
        expect(queue.instance_variable_get(:@server_instance)).to eq(server_instance)
        expect(queue.instance_variable_get(:@queue_key)).to eq("notifications:#{server_instance}")
        expect(queue.instance_variable_get(:@max_size)).to eq(max_size)
      end
    end
  end

  describe "#push" do
    it "adds a notification to the queue" do
      queue.push(sample_notification)

      aggregate_failures do
        expect(queue.size).to eq(1)
        expect(queue.pop).to eq(serialized(sample_notification))
      end
    end

    it "maintains FIFO order" do
      notification1 = {method: "first"}
      notification2 = {method: "second"}

      queue.push(notification1)
      queue.push(notification2)

      aggregate_failures do
        expect(queue.pop).to eq(serialized(notification1))
        expect(queue.pop).to eq(serialized(notification2))
      end
    end

    it "enforces max_size by removing oldest items" do
      (max_size + 2).times do |i|
        queue.push({method: "notification_#{i}"})
      end

      expect(queue.size).to eq(max_size)

      popped = queue.pop
      expect(popped["method"]).to eq("notification_2")
    end
  end

  describe "#pop" do
    it "returns nil when queue is empty" do
      expect(queue.pop).to be_nil
    end

    it "removes and returns the oldest notification" do
      queue.push(sample_notification)

      result = queue.pop

      aggregate_failures do
        expect(result).to eq(serialized(sample_notification))
        expect(queue.size).to eq(0)
      end
    end

    it "maintains FIFO order across multiple operations" do
      notifications = 3.times.map { |i| {method: "notification_#{i}"} }
      notifications.each { |n| queue.push(n) }

      results = 3.times.map { queue.pop }

      expect(results).to eq(serialized_array(notifications))
    end
  end

  describe "#pop_all" do
    it "returns empty array when queue is empty" do
      expect(queue.pop_all).to eq([])
    end

    it "returns all notifications in FIFO order and empties the queue" do
      notifications = 3.times.map { |i| {method: "notification_#{i}"} }
      notifications.each { |n| queue.push(n) }

      results = queue.pop_all

      aggregate_failures do
        expect(results).to eq(serialized_array(notifications))
        expect(queue.size).to eq(0)
      end
    end

    it "is atomic - returns all or nothing" do
      queue.push(sample_notification)

      Thread.new { queue.push({method: "concurrent"}) }
      sleep 0.01

      results = queue.pop_all

      aggregate_failures do
        expect(results.size).to be >= 1
        expect(queue.size).to eq(0)
      end
    end
  end

  describe "#peek_all" do
    it "returns empty array when queue is empty" do
      expect(queue.peek_all).to eq([])
    end

    it "returns all notifications without removing them" do
      notifications = 3.times.map { |i| {method: "notification_#{i}"} }
      notifications.each { |n| queue.push(n) }

      results = queue.peek_all

      aggregate_failures do
        expect(results).to eq(serialized_array(notifications))
        expect(queue.size).to eq(3)
      end
    end

    it "returns notifications in FIFO order" do
      notification1 = {method: "first"}
      notification2 = {method: "second"}

      queue.push(notification1)
      queue.push(notification2)

      expect(queue.peek_all).to eq([serialized(notification1), serialized(notification2)])
    end
  end

  describe "#size" do
    it "returns 0 for empty queue" do
      expect(queue.size).to eq(0)
    end

    it "returns correct size after adding items" do
      3.times { queue.push(sample_notification) }

      expect(queue.size).to eq(3)
    end

    it "updates correctly after popping items" do
      3.times { queue.push(sample_notification) }
      queue.pop

      expect(queue.size).to eq(2)
    end
  end

  describe "#empty?" do
    it "returns true for empty queue" do
      expect(queue.empty?).to be true
    end

    it "returns false for non-empty queue" do
      queue.push(sample_notification)

      expect(queue.empty?).to be false
    end
  end

  describe "#clear" do
    it "removes all notifications from the queue" do
      3.times { queue.push(sample_notification) }

      queue.clear

      aggregate_failures do
        expect(queue.size).to eq(0)
        expect(queue.empty?).to be true
      end
    end

    it "works on empty queue without error" do
      aggregate_failures do
        expect { queue.clear }.not_to raise_error
        expect(queue.size).to eq(0)
      end
    end
  end

  describe "#push_bulk" do
    it "adds multiple notifications at once" do
      notifications = 3.times.map { |i| {method: "notification_#{i}"} }

      queue.push_bulk(notifications)

      aggregate_failures do
        expect(queue.size).to eq(3)
        expect(queue.pop_all).to eq(serialized_array(notifications))
      end
    end

    it "maintains FIFO order for bulk operations" do
      batch1 = 2.times.map { |i| {method: "batch1_#{i}"} }
      batch2 = 2.times.map { |i| {method: "batch2_#{i}"} }

      queue.push_bulk(batch1)
      queue.push_bulk(batch2)

      results = queue.pop_all
      expected = serialized_array(batch1 + batch2)

      expect(results).to eq(expected)
    end

    it "enforces max_size for bulk operations" do
      notifications = (max_size + 2).times.map { |i| {method: "notification_#{i}"} }

      queue.push_bulk(notifications)

      expect(queue.size).to eq(max_size)

      results = queue.pop_all
      expected = serialized_array(notifications.last(max_size))

      expect(results).to eq(expected)
    end

    it "handles empty array gracefully" do
      aggregate_failures do
        expect { queue.push_bulk([]) }.not_to raise_error
        expect(queue.size).to eq(0)
      end
    end
  end

  describe "JSON serialization" do
    it "properly serializes and deserializes complex data structures" do
      complex_notification = {
        jsonrpc: "2.0",
        method: "complex_method",
        params: {
          nested: {
            array: [1, 2, 3],
            string: "test",
            boolean: true,
            null_value: nil
          }
        }
      }

      queue.push(complex_notification)
      result = queue.pop

      expected = JSON.parse(complex_notification.to_json)
      expect(result).to eq(expected)
    end
  end
end
