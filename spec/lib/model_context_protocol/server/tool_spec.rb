require "spec_helper"

RSpec.describe ModelContextProtocol::Server::Tool do
  let(:client_logger) { double("client_logger") }

  describe ".call" do
    context "when input schema validation fails" do
      let(:invalid_arguments) { {foo: "bar"} }

      it "raises a ParameterValidationError" do
        allow(client_logger).to receive(:info)
        expect {
          TestToolWithTextResponse.call(invalid_arguments, client_logger)
        }.to raise_error(ModelContextProtocol::Server::ParameterValidationError)
      end
    end

    context "when input schema validation succeeds" do
      let(:valid_arguments) { {number: "21"} }

      it "instantiates the tool with the provided arguments" do
        allow(client_logger).to receive(:info)
        expect(TestToolWithTextResponse).to receive(:new).with(valid_arguments, client_logger, {}).and_call_original
        TestToolWithTextResponse.call(valid_arguments, client_logger)
      end

      it "returns the response from the instance's call method" do
        allow(client_logger).to receive(:info)
        response = TestToolWithTextResponse.call(valid_arguments, client_logger)
        aggregate_failures do
          expect(response.content.first.text).to eq("21 doubled is 42")
          expect(response.serialized).to eq(
            content: [
              {
                type: "text",
                text: "21 doubled is 42"
              }
            ],
            isError: false
          )
        end
      end

      context "when an unexpected error occurs" do
        before do
          allow_any_instance_of(TestToolWithTextResponse).to receive(:call).and_raise("Test error")
        end

        it "returns an error response" do
          allow(client_logger).to receive(:info)
          response = TestToolWithTextResponse.call(valid_arguments, client_logger)
          aggregate_failures do
            expect(response.error).to eq("Test error")
            expect(response.serialized).to eq(
              content: [
                {
                  type: "text",
                  text: "Test error"
                }
              ],
              isError: true
            )
          end
        end
      end
    end
  end

  describe "#initialize" do
    it "validates the parameters against the schema" do
      expect(JSON::Validator).to receive(:validate!).with(
        TestToolWithTextResponse.input_schema,
        {"text" => "Hello, world!"}
      )
      allow(client_logger).to receive(:info)
      TestToolWithTextResponse.new({"text" => "Hello, world!"}, client_logger)
    end

    it "stores the arguments" do
      allow(client_logger).to receive(:info)
      tool = TestToolWithTextResponse.new({number: "42"}, client_logger)
      expect(tool.arguments).to eq({number: "42"})
    end

    it "stores context when provided" do
      context = {"user_id" => "123", "session" => "abc"}
      allow(client_logger).to receive(:info)
      tool = TestToolWithTextResponse.new({"number" => "42"}, client_logger, context)
      expect(tool.context).to eq(context)
    end

    it "defaults to empty hash when no context provided" do
      allow(client_logger).to receive(:info)
      tool = TestToolWithTextResponse.new({number: "42"}, client_logger)
      expect(tool.context).to eq({})
    end
  end

  describe ".call with context" do
    let(:valid_arguments) { {number: "21"} }
    let(:context) { {user_id: "123456"} }

    it "passes context to the instance" do
      allow(client_logger).to receive(:info)
      allow(TestToolWithTextResponse).to receive(:new).with(valid_arguments, client_logger, context).and_call_original
      response = TestToolWithTextResponse.call(valid_arguments, client_logger, context)
      aggregate_failures do
        expect(TestToolWithTextResponse).to have_received(:new).with(valid_arguments, client_logger, context)
        expect(response.content.first.text).to eq("User 123456, 21 doubled is 42")
      end
    end

    it "works with empty context" do
      allow(client_logger).to receive(:info)
      response = TestToolWithTextResponse.call(valid_arguments, client_logger, {})
      expect(response.content.first.text).to eq("21 doubled is 42")
    end

    it "works when context is not provided" do
      allow(client_logger).to receive(:info)
      response = TestToolWithTextResponse.call(valid_arguments, client_logger)
      expect(response.content.first.text).to eq("21 doubled is 42")
    end
  end

  describe "responses" do
    describe "text response" do
      it "formats text response correctly" do
        arguments = {number: "21"}
        allow(client_logger).to receive(:info)
        response = TestToolWithTextResponse.call(arguments, client_logger)
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "21 doubled is 42"
            }
          ],
          isError: false
        )
      end
    end

    describe "image response" do
      it "formats image responses correctly" do
        arguments = {chart_type: "bar", format: "jpg"}
        allow(client_logger).to receive(:info)
        response = TestToolWithImageResponse.call(arguments, client_logger)
        expect(response.serialized).to eq(
          content: [
            {
              type: "image",
              data: "dGVzdA==",
              mimeType: "image/jpeg"
            }
          ],
          isError: false
        )
      end
    end

    describe "resource response" do
      context "when resource does not have annotations" do
        it "formats resource responses correctly" do
          arguments = {name: "test_resource"}
          allow(client_logger).to receive(:info)
          response = TestToolWithResourceResponse.call(arguments, client_logger)
          expect(response.serialized).to eq(
            content: [
              type: "resource",
              resource: {
                mimeType: "text/plain",
                text: "I'm finna eat all my wife's leftovers.",
                title: "Top Secret Plans",
                uri: "file:///top-secret-plans.txt"
              }
            ],
            isError: false
          )
        end
      end

      context "when resource has annotations" do
        it "formats resource responses correctly" do
          arguments = {name: "test_annotated_resource"}
          allow(client_logger).to receive(:info)
          response = TestToolWithResourceResponse.call(arguments, client_logger)
          expect(response.serialized).to eq(
            content: [
              type: "resource",
              resource: {
                mimeType: "text/markdown",
                text: "# Annotated Document\n\nThis document has annotations.",
                uri: "file:///docs/annotated-document.md",
                annotations: {
                  audience: ["user", "assistant"],
                  priority: 0.9,
                  lastModified: "2025-01-12T15:00:58Z"
                }
              }
            ],
            isError: false
          )
        end
      end
    end

    describe "mixed content response" do
      it "formats mixed content responses correctly" do
        arguments = {zip: "12345"}
        allow(client_logger).to receive(:info)
        response = TestToolWithMixedContentResponse.call(arguments, client_logger)
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "85.2, 87.4, 89.0, 95.3, 96.0"
            },
            {
              type: "image",
              data: "dGVzdA==",
              mimeType: "image/png"
            }
          ],
          isError: false
        )
      end
    end

    describe "tool error response" do
      it "formats error responses correctly" do
        arguments = {api_endpoint: "http://example.com", method: "GET"}
        allow(client_logger).to receive(:info)
        response = TestToolWithToolErrorResponse.call(arguments, client_logger)
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: "Failed to call API at http://example.com: Connection timed out"
            }
          ],
          isError: true
        )
      end
    end

    describe "structured content response" do
      it "formats structured content responses correctly with backward compatibility" do
        arguments = {location: "San Francisco"}
        allow(client_logger).to receive(:info)
        response = TestToolWithStructuredContentResponse.call(arguments, client_logger)
        expect(response.serialized).to eq(
          content: [
            {
              type: "text",
              text: '{"temperature":22.5,"conditions":"Partly cloudy","humidity":65}'
            }
          ],
          structuredContent: {
            temperature: 22.5,
            conditions: "Partly cloudy",
            humidity: 65
          },
          isError: false
        )
      end

      it "raises OutputSchemaValidationError when structured content violates schema" do
        arguments = {location: "San Francisco"}
        allow(client_logger).to receive(:info)

        expect {
          response = TestToolWithInvalidStructuredContent.call(arguments, client_logger)
          response.serialized
        }.to raise_error(ModelContextProtocol::Server::Tool::OutputSchemaValidationError)
      end
    end
  end

  describe "define" do
    it "sets the class definition" do
      aggregate_failures do
        expect(TestToolWithTextResponse.name).to eq("double")
        expect(TestToolWithTextResponse.title).to eq("Number Doubler")
        expect(TestToolWithTextResponse.description).to eq("Doubles the provided number")
        expect(TestToolWithTextResponse.input_schema).to eq(
          type: "object",
          properties: {
            number: {
              type: "string"
            }
          },
          required: ["number"]
        )
      end
    end
  end

  describe "definition" do
    it "returns class definition" do
      expect(TestToolWithTextResponse.definition).to eq(
        name: "double",
        title: "Number Doubler",
        description: "Doubles the provided number",
        inputSchema: {
          type: "object",
          properties: {
            number: {
              type: "string"
            }
          },
          required: ["number"]
        }
      )
    end

    it "includes output schema when provided" do
      expect(TestToolWithStructuredContentResponse.definition).to eq(
        name: "get_weather_data",
        title: "Weather Data Retriever",
        description: "Get current weather data for a location",
        inputSchema: {
          type: "object",
          properties: {
            location: {
              type: "string",
              description: "City name or zip code"
            }
          },
          required: ["location"]
        },
        outputSchema: {
          type: "object",
          properties: {
            temperature: {
              type: "number",
              description: "Temperature in celsius"
            },
            conditions: {
              type: "string",
              description: "Weather conditions description"
            },
            humidity: {
              type: "number",
              description: "Humidity percentage"
            }
          },
          required: ["temperature", "conditions", "humidity"]
        }
      )
    end
  end

  describe "optional title field" do
    let(:tool_without_title) do
      Class.new(ModelContextProtocol::Server::Tool) do
        define do
          name "test_tool"
          description "A test tool without title"
          input_schema do
            {type: "object", properties: {}, required: []}
          end
        end

        def call
          respond_with content: text_content(text: "test response")
        end
      end
    end

    it "does not include title in definition when not provided" do
      metadata = tool_without_title.definition
      expect(metadata).not_to have_key(:title)
    end
  end
end
