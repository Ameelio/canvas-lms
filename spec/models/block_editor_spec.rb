# frozen_string_literal: true

#
# Copyright (C) 2026 - present Ameelio
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

describe BlockEditor do
  before do
    course_with_teacher
    @wiki_page = @course.wiki_pages.create!(title: "Test Page", body: "Test content")
  end

  describe "blocks attribute sanitization" do
    it "sanitizes malicious scripts in blocks" do
      malicious_blocks = '<p>Content</p><script>alert("XSS")</script>'
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: malicious_blocks,
        editor_version: "0.2"
      )

      expect(block_editor.blocks).not_to include("<script>")
      expect(block_editor.blocks).not_to include('alert("XSS")')
      expect(block_editor.blocks).to include("<p>Content</p>")
    end

    it "removes javascript event handlers from blocks" do
      malicious_blocks = '<div onclick="alert(\'XSS\')">Click me</div>'
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: malicious_blocks,
        editor_version: "0.2"
      )

      expect(block_editor.blocks).not_to include("onclick")
      expect(block_editor.blocks).not_to include("alert")
      expect(block_editor.blocks).to include("Click me")
    end

    it "removes dangerous iframe tags from blocks" do
      malicious_blocks = '<p>Content</p><iframe src="https://evil.com"></iframe>'
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: malicious_blocks,
        editor_version: "0.2"
      )

      expect(block_editor.blocks).not_to include("<iframe")
      expect(block_editor.blocks).to include("<p>Content</p>")
    end

    it "removes javascript: protocol from links in blocks" do
      malicious_blocks = '<a href="javascript:alert(\'XSS\')">Click</a>'
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: malicious_blocks,
        editor_version: "0.2"
      )

      expect(block_editor.blocks).not_to include("javascript:")
      expect(block_editor.blocks).not_to include("alert")
    end

    it "preserves safe HTML in blocks" do
      safe_blocks = '<p>Hello <strong>World</strong></p><ul><li>Item 1</li><li>Item 2</li></ul>'
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: safe_blocks,
        editor_version: "0.2"
      )

      expect(block_editor.blocks).to include("<p>")
      expect(block_editor.blocks).to include("<strong>")
      expect(block_editor.blocks).to include("<ul>")
      expect(block_editor.blocks).to include("<li>")
    end

    it "adds security attributes to external links" do
      blocks_with_link = '<a href="https://example.com">Link</a>'
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: blocks_with_link,
        editor_version: "0.2"
      )

      expect(block_editor.blocks).to include('rel="nofollow')
      expect(block_editor.blocks).to include('rel="noopener')
      expect(block_editor.blocks).to include('target="_blank"')
    end

    it "removes onerror attributes from img tags" do
      malicious_blocks = '<img src="invalid" onerror="alert(\'XSS\')">'
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: malicious_blocks,
        editor_version: "0.2"
      )

      expect(block_editor.blocks).not_to include("onerror")
      expect(block_editor.blocks).not_to include("alert")
    end

    it "updates blocks with sanitization on save" do
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: '<p>Initial content</p>',
        editor_version: "0.2"
      )

      malicious_update = '<p>Updated</p><script>alert("XSS")</script>'
      block_editor.update!(blocks: malicious_update)

      expect(block_editor.reload.blocks).not_to include("<script>")
      expect(block_editor.blocks).not_to include('alert("XSS")')
      expect(block_editor.blocks).to include("<p>Updated</p>")
    end
  end

  describe "associations" do
    it "belongs to wiki_page context" do
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: '{"ROOT": {}}',
        editor_version: "0.2"
      )

      expect(block_editor.context).to eq(@wiki_page)
      expect(block_editor.context_type).to eq("WikiPage")
    end
  end

  describe "#set_root_account_id" do
    it "sets root_account_id from context before create" do
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: '{"ROOT": {}}',
        editor_version: "0.2"
      )

      expect(block_editor.root_account_id).to eq(@course.root_account_id)
    end
  end

  describe "#viewer_iframe_html" do
    it "generates iframe HTML for viewing block editor content" do
      block_editor = BlockEditor.create!(
        context: @wiki_page,
        blocks: '{"ROOT": {}}',
        editor_version: "0.2"
      )

      html = block_editor.viewer_iframe_html
      expect(html).to include("iframe")
      expect(html).to include("block_editor_view")
      expect(html).to include(block_editor.id.to_s)
    end
  end
end
