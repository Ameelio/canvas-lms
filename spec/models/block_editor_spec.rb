# frozen_string_literal: true

describe BlockEditor do
  let_once(:page) do
    course_factory
    @course.wiki_pages.create!(title: "Block page")
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

  it "sanitizes blocks at rest before persistence" do
    editor = described_class.create!(context: page, blocks: unsafe_blocks)
    stored_props = described_class.where(id: editor).pick(:blocks).dig("ROOT", "props")

    expect(stored_props["text"]).to include("Stored content")
    expect(stored_props["text"]).not_to include("onmouseover")
    expect(stored_props["href"]).to eql("")
  end

  it "sanitizes legacy records when they are read" do
    editor = described_class.create!(context: page, blocks: { "ROOT" => {} })
    editor.update_column(:blocks, unsafe_blocks)
    props = editor.reload.blocks.dig("ROOT", "props")

    expect(props["text"]).not_to include("onmouseover")
    expect(props["href"]).to eql("")
  end

  it "memoizes sanitization instead of re-sanitizing every read" do
    editor = described_class.create!(context: page, blocks: { "ROOT" => {} }).reload
    allow(BlockEditorContentSanitizer).to receive(:sanitize).and_call_original

    2.times { editor.blocks }

    expect(BlockEditorContentSanitizer).to have_received(:sanitize).once
  end

  it "does not re-sanitize saves that do not change blocks" do
    editor = described_class.create!(context: page, blocks: { "ROOT" => {} }).reload
    allow(BlockEditorContentSanitizer).to receive(:sanitize).and_call_original

    editor.update!(editor_version: BlockEditor::LATEST_VERSION)

    expect(BlockEditorContentSanitizer).not_to have_received(:sanitize)
  end

  it "persists in-place mutations made through the getter" do
    editor = described_class.create!(context: page, blocks: { "ROOT" => { "props" => {} } }).reload
    editor.blocks["ROOT"]["props"]["text"] = "<p>Updated copy</p>"
    editor.save!

    stored_text = described_class.where(id: editor).pick(:blocks).dig("ROOT", "props", "text")
    expect(stored_text).to eql("<p>Updated copy</p>")
  end
end
