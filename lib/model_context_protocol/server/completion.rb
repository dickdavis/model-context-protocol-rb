module ModelContextProtocol
  class Server::Completion
    attr_reader :argument_name, :argument_value

    def initialize(argument_name, argument_value)
      @argument_name = argument_name
      @argument_value = argument_value
    end

    def call
      raise NotImplementedError, "Subclasses must implement the call method"
    end

    def self.call(...)
      new(...).call
    end

    private

    Response = Data.define(:values, :total, :hasMore) do
      def serialized
        {completion: {values:, total:, hasMore:}}
      end
    end

    def respond_with(values:)
      values_to_return = values.take(100)
      total = values.size
      has_more = values_to_return.size != total
      Response[values:, total:, hasMore: has_more]
    end
  end

  class Server::NullCompletion
    Response = Data.define(:values, :total, :hasMore) do
      def serialized
        {completion: {values:, total:, hasMore:}}
      end
    end

    def self.call(_argument_name, _argument_value)
      Response[values: [], total: 0, hasMore: false]
    end
  end
end
