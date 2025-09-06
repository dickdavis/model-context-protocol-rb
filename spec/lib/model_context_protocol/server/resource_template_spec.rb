require "spec_helper"

RSpec.describe ModelContextProtocol::Server::ResourceTemplate do
  describe "with_metadata" do
    it "sets the class metadata" do
      aggregate_failures do
        expect(TestResourceTemplate.name).to eq("project-document-resource-template")
        expect(TestResourceTemplate.description).to eq("A resource template for retrieving project documents")
        expect(TestResourceTemplate.mime_type).to eq("text/plain")
        expect(TestResourceTemplate.uri_template).to eq("file:///{name}")
        expect(TestResourceTemplate.completions["name"]).to respond_to(:call)
      end
    end
  end

  describe "metadata" do
    it "returns class metadata" do
      metadata = TestResourceTemplate.metadata
      expect(metadata[:name]).to eq("project-document-resource-template")
      expect(metadata[:description]).to eq("A resource template for retrieving project documents")
      expect(metadata[:mimeType]).to eq("text/plain")
      expect(metadata[:uriTemplate]).to eq("file:///{name}")
      expect(metadata[:completions]["name"]).to respond_to(:call)
    end
  end

  describe "array-based completions" do
    let(:test_array_template) { TestArrayCompletionResourceTemplate }

    it "creates completions from arrays of values" do
      completions = test_array_template.completions
      expect(completions["category"]).to respond_to(:call)
      expect(completions["item"]).to respond_to(:call)
    end

    it "filters completion values based on input for category" do
      result = test_array_template.complete_for("category", "doc")
      expect(result.values).to eq(["documents"])
      expect(result.total).to eq(1)
      expect(result.hasMore).to be(false)
    end

    it "filters completion values based on input for item" do
      result = test_array_template.complete_for("item", "file")
      expect(result.values).to include("file1.txt", "file2.txt")
      expect(result.total).to eq(2)
    end

    it "returns empty array when no matches" do
      result = test_array_template.complete_for("category", "xyz")
      expect(result.values).to eq([])
      expect(result.total).to eq(0)
    end
  end

  describe "old-style completion classes (backward compatibility)" do
    let(:test_old_style_template) { TestOldStyleCompletionResourceTemplate }

    it "creates completions from completion classes" do
      completions = test_old_style_template.completions
      expect(completions["status"]).to eq(TestOldStyleCompletionResourceTemplate::StatusCompletion)
      expect(completions["type"]).to eq(TestOldStyleCompletionResourceTemplate::TypeCompletion)
    end

    it "filters completion values for status parameter" do
      result = test_old_style_template.complete_for("status", "ac")
      expect(result.values).to eq(["active", "inactive"])
      expect(result.total).to eq(2)
    end

    it "filters completion values for type parameter using argument_name" do
      result = test_old_style_template.complete_for("type", "doc")
      expect(result.values).to eq(["document"])
      expect(result.total).to eq(1)
    end

    it "returns empty array when no matches in old-style completion" do
      result = test_old_style_template.complete_for("status", "xyz")
      expect(result.values).to eq([])
      expect(result.total).to eq(0)
    end
  end
end
