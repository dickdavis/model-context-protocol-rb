class TestProgressiveResource < ModelContextProtocol::Server::Resource
  define do
    mime_type "text/plain"
    uri "progressive://test"
    title "Progressive Test Resource"
    description "A test resource that demonstrates progressable functionality"
  end

  def call
    duration = 15

    content = progressable(max_duration: duration, message: "Loading resource data") do
      simulate_resource_loading(duration)
    end

    respond_with(text: content)
  end

  private

  def extract_duration_from_uri(uri)
    return nil unless uri&.query

    params = URI.decode_www_form(uri.query).to_h
    params["duration"]&.to_f
  end

  def simulate_resource_loading(duration)
    chunks = []
    num_chunks = 5
    chunk_duration = duration / num_chunks.to_f

    num_chunks.times do |i|
      sleep chunk_duration
      chunks << "Chunk #{i + 1} data: #{generate_chunk_data(i)}"
    end

    chunks.join("\n")
  end

  def generate_chunk_data(chunk_index)
    "This is sample data for chunk #{chunk_index + 1}. " * 10
  end
end
