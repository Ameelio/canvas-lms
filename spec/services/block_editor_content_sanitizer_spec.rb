# frozen_string_literal: true

describe BlockEditorContentSanitizer do
  let(:unsafe_document) do
    {
      "ROOT" => {
        "props" => {
          "text" => "<img src=x onerror=alert(1)><p>Safe text</p>",
          "href" => "java\nscript:alert(1)",
          "buttonLink" => "javascript:alert(1)",
          "src" => "data:text/html,<script>alert(1)</script>",
          "linkUrl" => "https://example.com/path",
          "futureContentURL" => "javascript:alert(1)",
          "future_html_field" => "<svg onload=alert(1)></svg>"
        }
      }
    }
  end

  it "sanitizes nested HTML and unsafe URL schemes without mutating the input" do
    result = described_class.sanitize(unsafe_document)
    props = result.dig("ROOT", "props")

    expect(props["text"]).to include("Safe text")
    expect(props["text"]).not_to include("onerror")
    expect(props["href"]).to eq("")
    expect(props["buttonLink"]).to eq("")
    expect(props["src"]).to eq("")
    expect(props["linkUrl"]).to eq("https://example.com/path")
    expect(props["futureContentURL"]).to eq("")
    expect(props["future_html_field"]).not_to include("onload")
    expect(unsafe_document.dig("ROOT", "props", "text")).to include("onerror")
  end

  it "preserves serialized documents while sanitizing their contents" do
    result = described_class.sanitize(unsafe_document.to_json)
    props = JSON.parse(result).dig("ROOT", "props")

    expect(result).to be_a(String)
    expect(props["text"]).not_to include("onerror")
    expect(props["href"]).to eq("")
  end

  it "leaves malformed serialized data unchanged" do
    malformed = '{"ROOT":'

    expect(described_class.sanitize(malformed)).to eq(malformed)
  end

  it "sanitizes unterminated HTML tags" do
    result = described_class.sanitize({ "content" => "<img src=x onerror=alert(1)" })

    expect(result["content"]).not_to include("onerror")
  end
end
