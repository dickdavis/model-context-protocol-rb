class TestAnnotatedResource < ModelContextProtocol::Server::Resource
  with_metadata do
    name "annotated-document.md"
    description "A document with annotations showing priority and audience"
    mime_type "text/markdown"
    uri "file:///docs/annotated-document.md"

    with_annotations do
      audience [:user, :assistant]
      priority 0.9
      last_modified "2025-01-12T15:00:58Z"
    end
  end

  def call
    respond_with text: "# Annotated Document\n\nThis document has annotations."
  end
end
