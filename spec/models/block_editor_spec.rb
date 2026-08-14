# frozen_string_literal: true

describe BlockEditor do
  before do
    course_factory
    @page = @course.wiki_pages.create!(title: "Block page")
  end

  let(:unsafe_blocks) do
    {
      "ROOT" => {
        "props" => {
          "text" => "<p onmouseover=alert(1)>Stored content</p>",
          "href" => "javascript:alert(1)"
        }
      }
    }
  end

  it "sanitizes blocks before persistence" do
    editor = described_class.create!(context: @page, blocks: unsafe_blocks)
    props = editor.reload.blocks.dig("ROOT", "props")

    expect(props["text"]).to include("Stored content")
    expect(props["text"]).not_to include("onmouseover")
    expect(props["href"]).to eq("")
  end

  it "sanitizes legacy records when they are read" do
    editor = described_class.create!(context: @page, blocks: { "ROOT" => {} })
    editor.update_column(:blocks, unsafe_blocks)
    props = editor.reload.blocks.dig("ROOT", "props")

    expect(props["text"]).not_to include("onmouseover")
    expect(props["href"]).to eq("")
  end
end
