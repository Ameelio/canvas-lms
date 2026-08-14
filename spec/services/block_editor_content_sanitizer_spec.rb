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

  it "leaves malformed serialized data without markup unchanged" do
    malformed = '{"ROOT":'

    expect(described_class.sanitize(malformed)).to eq(malformed)
  end

  it "strips markup from malformed serialized data instead of returning it verbatim" do
    malformed = '{"evil":"<img src=x onerror=alert(1)>",'

    expect(described_class.sanitize(malformed)).not_to include("onerror")
  end

  it "fails closed when a serialized document is nested beyond the parser limit" do
    pad = ("[" * 600) + ("]" * 600)
    payload = %({"evil":"<img src=x onerror=alert(1)>","pad":#{pad}})

    expect(described_class.sanitize(payload)).not_to include("onerror")
  end

  it "sanitizes unterminated HTML tags" do
    result = described_class.sanitize({ "content" => "<img src=x onerror=alert(1)" })

    expect(result["content"]).not_to include("onerror")
  end

  it "sanitizes url fields whose value is an array" do
    result = described_class.sanitize({ "props" => { "buttonLink" => ["javascript:alert(1)", "https://example.com/ok"] } })

    expect(result.dig("props", "buttonLink")).to eql(["", "https://example.com/ok"])
  end

  it "preserves plain text containing a bare '<'" do
    value = { "title" => "if a<b then", "caption" => "1 < 2 and 3 > 2" }

    expect(described_class.sanitize(value)).to eql(value)
  end

  it "drops content nested beyond the depth limit instead of overflowing the stack" do
    deep = 600.times.inject({ "text" => "<script>alert(1)</script>" }) { |acc, _| { "child" => acc } }

    expect { described_class.sanitize(deep) }.not_to raise_error
  end
end
