require "spec_helper"

RSpec.describe ModelContextProtocol::Server::StreamableHttpTransport::EventCounter do
  subject(:counter) { described_class.new(redis, server_instance) }

  let(:redis) { MockRedis.new }
  let(:server_instance) { "test-server-123" }

  before do
    redis.flushdb
  end

  describe "#initialize" do
    it "creates a counter with the correct configuration" do
      expect(counter.instance_variable_get(:@redis)).to eq(redis)
      expect(counter.instance_variable_get(:@server_instance)).to eq(server_instance)
      expect(counter.instance_variable_get(:@counter_key)).to eq("event_counter:#{server_instance}")
    end

    it "initializes the counter to 0 if it doesn't exist" do
      fresh_redis = MockRedis.new
      described_class.new(fresh_redis, server_instance)
      expect(fresh_redis.get("event_counter:#{server_instance}")).to eq("0")
    end

    it "doesn't overwrite existing counter value" do
      redis.set("event_counter:#{server_instance}", "42")

      described_class.new(redis, server_instance)

      expect(redis.get("event_counter:#{server_instance}")).to eq("42")
    end
  end

  describe "#next_event_id" do
    it "generates incrementing event IDs" do
      id1 = counter.next_event_id
      id2 = counter.next_event_id
      id3 = counter.next_event_id

      expect(id1).to eq("#{server_instance}-1")
      expect(id2).to eq("#{server_instance}-2")
      expect(id3).to eq("#{server_instance}-3")
    end

    it "uses atomic increments" do
      ids = []
      threads = 10.times.map do
        Thread.new do
          5.times { ids << counter.next_event_id }
        end
      end

      threads.each(&:join)

      aggregate_failures do
        expect(ids.size).to eq(50)
        expect(ids.uniq.size).to eq(50)

        ids.each do |id|
          expect(id).to match(/^#{Regexp.escape(server_instance)}-\d+$/)
        end
      end
    end

    it "continues from existing counter value" do
      redis.set("event_counter:#{server_instance}", "100")

      id = counter.next_event_id

      expect(id).to eq("#{server_instance}-101")
    end

    it "handles very large numbers" do
      redis.set("event_counter:#{server_instance}", "999999999")

      id = counter.next_event_id

      expect(id).to eq("#{server_instance}-1000000000")
    end
  end

  describe "thread safety" do
    it "maintains consistency under concurrent access" do
      counters = 5.times.map { described_class.new(redis, server_instance) }

      ids = []
      mutex = Mutex.new

      threads = counters.map do |c|
        Thread.new do
          10.times do
            id = c.next_event_id
            mutex.synchronize { ids << id }
          end
        end
      end

      threads.each(&:join)

      aggregate_failures do
        expect(ids.size).to eq(50)
        expect(ids.uniq.size).to eq(50)
      end
    end
  end

  describe "multiple server instances" do
    it "maintains separate counters for different server instances" do
      server2 = "different-server-456"
      counter2 = described_class.new(redis, server2)

      id1 = counter.next_event_id
      id2 = counter2.next_event_id
      id3 = counter.next_event_id

      aggregate_failures do
        expect(id1).to eq("#{server_instance}-1")
        expect(id2).to eq("#{server2}-1")
        expect(id3).to eq("#{server_instance}-2")
      end
    end
  end
end
