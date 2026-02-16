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

      expect(queue.pop_all).to eq([serialized(sample_notification)])
    end

    it "maintains FIFO order" do
      notification1 = {method: "first"}
      notification2 = {method: "second"}

      queue.push(notification1)
      queue.push(notification2)

      expect(queue.pop_all).to eq([serialized(notification1), serialized(notification2)])
    end

    it "enforces max_size by removing oldest items" do
      (max_size + 2).times do |i|
        queue.push({method: "notification_#{i}"})
      end

      results = queue.pop_all
      aggregate_failures do
        expect(results.length).to eq(max_size)
        expect(results.first["method"]).to eq("notification_2")
      end
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
        expect(queue.pop_all).to eq([])
      end
    end

    it "is atomic - returns all or nothing" do
      queue.push(sample_notification)

      Thread.new { queue.push({method: "concurrent"}) }
      sleep 0.01

      results = queue.pop_all

      aggregate_failures do
        expect(results.size).to be >= 1
        expect(queue.pop_all).to eq([])
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
      results = queue.pop_all

      expected = JSON.parse(complex_notification.to_json)
      expect(results).to eq([expected])
    end
  end
end
