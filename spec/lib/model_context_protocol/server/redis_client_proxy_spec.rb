require "spec_helper"

RSpec.describe ModelContextProtocol::Server::RedisClientProxy do
  subject(:wrapper) { described_class.new(pool) }

  let(:pool) { double("connection_pool") }
  let(:redis_mock) { double("redis") }

  before do
    allow(pool).to receive(:with).and_yield(redis_mock)
  end

  describe "#initialize" do
    it "stores the pool" do
      expect(wrapper.instance_variable_get(:@pool)).to eq(pool)
    end
  end

  describe "basic Redis operations" do
    describe "#get" do
      it "calls get on the Redis connection" do
        expect(redis_mock).to receive(:get).with("test_key").and_return("test_value")

        result = wrapper.get("test_key")
        expect(result).to eq("test_value")
      end
    end

    describe "#set" do
      it "calls set on the Redis connection" do
        expect(redis_mock).to receive(:set).with("test_key", "test_value").and_return("OK")

        result = wrapper.set("test_key", "test_value")
        expect(result).to eq("OK")
      end

      it "passes options to set" do
        expect(redis_mock).to receive(:set).with("test_key", "test_value", nx: true, ex: 60).and_return("OK")

        result = wrapper.set("test_key", "test_value", nx: true, ex: 60)
        expect(result).to eq("OK")
      end
    end

    describe "#del" do
      it "calls del on the Redis connection with single key" do
        expect(redis_mock).to receive(:del).with("test_key").and_return(1)

        result = wrapper.del("test_key")
        expect(result).to eq(1)
      end

      it "calls del on the Redis connection with multiple keys" do
        expect(redis_mock).to receive(:del).with("key1", "key2", "key3").and_return(3)

        result = wrapper.del("key1", "key2", "key3")
        expect(result).to eq(3)
      end
    end

    describe "#exists" do
      it "calls exists on the Redis connection" do
        expect(redis_mock).to receive(:exists).with("test_key").and_return(1)

        result = wrapper.exists("test_key")
        expect(result).to eq(1)
      end

      it "handles multiple keys" do
        expect(redis_mock).to receive(:exists).with("key1", "key2").and_return(2)

        result = wrapper.exists("key1", "key2")
        expect(result).to eq(2)
      end
    end

    describe "#expire" do
      it "calls expire on the Redis connection" do
        expect(redis_mock).to receive(:expire).with("test_key", 60).and_return(1)

        result = wrapper.expire("test_key", 60)
        expect(result).to eq(1)
      end
    end

    describe "#ttl" do
      it "calls ttl on the Redis connection" do
        expect(redis_mock).to receive(:ttl).with("test_key").and_return(60)

        result = wrapper.ttl("test_key")
        expect(result).to eq(60)
      end
    end
  end

  describe "hash operations" do
    describe "#hget" do
      it "calls hget on the Redis connection" do
        expect(redis_mock).to receive(:hget).with("hash_key", "field").and_return("value")

        result = wrapper.hget("hash_key", "field")
        expect(result).to eq("value")
      end
    end

    describe "#hset" do
      it "calls hset on the Redis connection" do
        expect(redis_mock).to receive(:hset).with("hash_key", "field", "value").and_return(1)

        result = wrapper.hset("hash_key", "field", "value")
        expect(result).to eq(1)
      end

      it "handles multiple field-value pairs" do
        expect(redis_mock).to receive(:hset).with("hash_key", "field1", "value1", "field2", "value2").and_return(2)

        result = wrapper.hset("hash_key", "field1", "value1", "field2", "value2")
        expect(result).to eq(2)
      end
    end

    describe "#hgetall" do
      it "calls hgetall on the Redis connection" do
        hash_data = {"field1" => "value1", "field2" => "value2"}
        expect(redis_mock).to receive(:hgetall).with("hash_key").and_return(hash_data)

        result = wrapper.hgetall("hash_key")
        expect(result).to eq(hash_data)
      end
    end
  end

  describe "list operations" do
    describe "#lpush" do
      it "calls lpush on the Redis connection with single value" do
        expect(redis_mock).to receive(:lpush).with("list_key", "value").and_return(1)

        result = wrapper.lpush("list_key", "value")
        expect(result).to eq(1)
      end

      it "calls lpush on the Redis connection with multiple values" do
        expect(redis_mock).to receive(:lpush).with("list_key", "value1", "value2").and_return(2)

        result = wrapper.lpush("list_key", "value1", "value2")
        expect(result).to eq(2)
      end
    end

    describe "#rpop" do
      it "calls rpop on the Redis connection" do
        expect(redis_mock).to receive(:rpop).with("list_key").and_return("value")

        result = wrapper.rpop("list_key")
        expect(result).to eq("value")
      end
    end

    describe "#lrange" do
      it "calls lrange on the Redis connection" do
        list_data = ["value1", "value2", "value3"]
        expect(redis_mock).to receive(:lrange).with("list_key", 0, -1).and_return(list_data)

        result = wrapper.lrange("list_key", 0, -1)
        expect(result).to eq(list_data)
      end
    end

    describe "#llen" do
      it "calls llen on the Redis connection" do
        expect(redis_mock).to receive(:llen).with("list_key").and_return(3)

        result = wrapper.llen("list_key")
        expect(result).to eq(3)
      end
    end

    describe "#ltrim" do
      it "calls ltrim on the Redis connection" do
        expect(redis_mock).to receive(:ltrim).with("list_key", 0, 99).and_return("OK")

        result = wrapper.ltrim("list_key", 0, 99)
        expect(result).to eq("OK")
      end
    end
  end

  describe "counter operations" do
    describe "#incr" do
      it "calls incr on the Redis connection" do
        expect(redis_mock).to receive(:incr).with("counter_key").and_return(1)

        result = wrapper.incr("counter_key")
        expect(result).to eq(1)
      end
    end

    describe "#decr" do
      it "calls decr on the Redis connection" do
        expect(redis_mock).to receive(:decr).with("counter_key").and_return(0)

        result = wrapper.decr("counter_key")
        expect(result).to eq(0)
      end
    end
  end

  describe "key pattern operations" do
    describe "#keys" do
      it "calls keys on the Redis connection" do
        key_list = ["key1", "key2", "key3"]
        expect(redis_mock).to receive(:keys).with("test:*").and_return(key_list)

        result = wrapper.keys("test:*")
        expect(result).to eq(key_list)
      end
    end
  end

  describe "multi-get operation" do
    describe "#mget" do
      it "calls mget on the Redis connection" do
        values = ["value1", "value2", nil]
        expect(redis_mock).to receive(:mget).with("key1", "key2", "key3").and_return(values)

        result = wrapper.mget("key1", "key2", "key3")
        expect(result).to eq(values)
      end
    end
  end

  describe "Lua script evaluation" do
    describe "#eval" do
      it "calls eval on the Redis connection with script only" do
        script = "return redis.call('get', KEYS[1])"
        expect(redis_mock).to receive(:eval).with(script, keys: [], argv: []).and_return("result")

        result = wrapper.eval(script)
        expect(result).to eq("result")
      end

      it "calls eval on the Redis connection with keys and argv" do
        script = "return redis.call('set', KEYS[1], ARGV[1])"
        expect(redis_mock).to receive(:eval).with(script, keys: ["test_key"], argv: ["test_value"]).and_return("OK")

        result = wrapper.eval(script, keys: ["test_key"], argv: ["test_value"])
        expect(result).to eq("OK")
      end
    end
  end

  describe "utility methods" do
    describe "#ping" do
      it "calls ping on the Redis connection" do
        expect(redis_mock).to receive(:ping).and_return("PONG")

        result = wrapper.ping
        expect(result).to eq("PONG")
      end
    end

    describe "#flushdb" do
      it "calls flushdb on the Redis connection" do
        expect(redis_mock).to receive(:flushdb).and_return("OK")

        result = wrapper.flushdb
        expect(result).to eq("OK")
      end
    end
  end

  describe "transaction support" do
    describe "#multi" do
      let(:multi_mock) { double("redis_multi") }
      let(:multi_wrapper) { double("redis_multi_wrapper") }

      it "creates a transaction and wraps the multi object" do
        expect(redis_mock).to receive(:multi).and_yield(multi_mock).and_return(["OK", "OK"])
        expect(ModelContextProtocol::Server::RedisClientProxy::RedisMultiWrapper).to receive(:new).with(multi_mock).and_return(multi_wrapper)

        result = wrapper.multi do |multi|
          expect(multi).to eq(multi_wrapper)
        end

        expect(result).to eq(["OK", "OK"])
      end
    end
  end

  describe "pipeline support" do
    describe "#pipelined" do
      let(:pipeline_mock) { double("redis_pipeline") }
      let(:pipeline_wrapper) { double("redis_pipeline_wrapper") }

      it "creates a pipeline and wraps the pipeline object" do
        expect(redis_mock).to receive(:pipelined).and_yield(pipeline_mock).and_return(["OK", "OK"])
        expect(ModelContextProtocol::Server::RedisClientProxy::RedisMultiWrapper).to receive(:new).with(pipeline_mock).and_return(pipeline_wrapper)

        result = wrapper.pipelined do |pipeline|
          expect(pipeline).to eq(pipeline_wrapper)
        end

        expect(result).to eq(["OK", "OK"])
      end
    end
  end

  describe "connection pool interaction" do
    it "uses the pool for each operation" do
      expect(pool).to receive(:with).exactly(3).times.and_yield(redis_mock)
      expect(redis_mock).to receive(:get).with("key1").and_return("value1")
      expect(redis_mock).to receive(:get).with("key2").and_return("value2")
      expect(redis_mock).to receive(:get).with("key3").and_return("value3")

      wrapper.get("key1")
      wrapper.get("key2")
      wrapper.get("key3")
    end

    it "handles pool exceptions gracefully" do
      allow(pool).to receive(:with).and_raise(StandardError.new("Pool exhausted"))

      expect { wrapper.get("test_key") }.to raise_error(StandardError, "Pool exhausted")
    end
  end

  describe ModelContextProtocol::Server::RedisClientProxy::RedisMultiWrapper do
    subject(:multi_wrapper) { described_class.new(multi_mock) }

    let(:multi_mock) { double("redis_multi") }

    describe "#initialize" do
      it "stores the multi object" do
        expect(multi_wrapper.instance_variable_get(:@multi)).to eq(multi_mock)
      end
    end

    describe "method delegation" do
      it "delegates method calls to the underlying multi object" do
        expect(multi_mock).to receive(:set).with("key", "value").and_return("QUEUED")

        result = multi_wrapper.set("key", "value")
        expect(result).to eq("QUEUED")
      end

      it "delegates method calls with keyword arguments" do
        expect(multi_mock).to receive(:set).with("key", "value", nx: true).and_return("QUEUED")

        result = multi_wrapper.set("key", "value", nx: true)
        expect(result).to eq("QUEUED")
      end

      it "delegates method calls with blocks" do
        block = proc { "test" }
        expect(multi_mock).to receive(:eval).with("script", &block).and_return("QUEUED")

        result = multi_wrapper.eval("script", &block)
        expect(result).to eq("QUEUED")
      end
    end

    describe "#respond_to_missing?" do
      it "returns true for methods the multi object responds to" do
        allow(multi_mock).to receive(:respond_to?).with(:set, false).and_return(true)

        expect(multi_wrapper.respond_to?(:set)).to be true
      end

      it "returns false for methods the multi object doesn't respond to" do
        allow(multi_mock).to receive(:respond_to?).with(:nonexistent_method, false).and_return(false)

        expect(multi_wrapper.respond_to?(:nonexistent_method)).to be false
      end

      it "passes include_private parameter" do
        expect(multi_mock).to receive(:respond_to?).with(:private_method, true).and_return(true)

        expect(multi_wrapper.respond_to?(:private_method, true)).to be true
      end
    end
  end
end
