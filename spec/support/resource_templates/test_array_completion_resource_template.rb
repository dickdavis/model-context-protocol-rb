class TestArrayCompletionResourceTemplate < ModelContextProtocol::Server::ResourceTemplate
  define do
    name "test-array-completion-resource-template"
    description "A resource template to test array-based completions"
    mime_type "text/plain"
    uri_template "file:///{category}/{item}" do
      completion :category, ["documents", "images", "videos", "audio"]
      completion :item, ["file1.txt", "file2.txt", "image.png", "video.mp4"]
    end
  end
end
