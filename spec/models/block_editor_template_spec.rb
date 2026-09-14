# frozen_string_literal: true

#
# Copyright (C) 2024 - present Instructure, Inc.
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
#

describe BlockEditorTemplate do
  before do
    course_with_teacher
  end

  it "should have a valid factory" do
    template = BlockEditorTemplate.new({
                                         context_type: "Course",
                                         context_id: @course.id,
                                         name: "name",
                                         description: "description",
                                         node_tree: '{"ROOT": {}}',
                                         editor_version: "1.0",
                                         template_type: "block"
                                       })
    expect(template).to be_valid
    expect(template.workflow_state).to eq("unpublished")
  end

  it "should soft delete" do
    template = BlockEditorTemplate.create!({
                                             context_type: "Course",
                                             context_id: @course.id,
                                             name: "name",
                                             description: "description",
                                             node_tree: '{"ROOT": {}}',
                                             editor_version: "1.0",
                                             template_type: "block"
                                           })
    template.destroy
    expect(BlockEditorTemplate.find_by(id: template.id).workflow_state).to eq("deleted")
  end

  it "should be active when published" do
    template = BlockEditorTemplate.create!({
                                             context_type: "Course",
                                             context_id: @course.id,
                                             name: "name",
                                             description: "description",
                                             node_tree: '{"ROOT": {}}',
                                             editor_version: "1.0",
                                             template_type: "block"
                                           })
    expect(template.active?).to be_falsey
    expect(template.published?).to be_falsey
    template.publish
    expect(template.active?).to be_truthy
    expect(template.published?).to be_truthy
  end

  describe "node_tree sanitization" do
    it "sanitizes malicious scripts in node_tree" do
      malicious_tree = '<p>Content</p><script>alert("XSS")</script>'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: malicious_tree,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).not_to include("<script>")
      expect(template.node_tree).not_to include('alert("XSS")')
      expect(template.node_tree).to include("<p>Content</p>")
    end

    it "removes javascript event handlers from node_tree" do
      malicious_tree = '<div onclick="alert(\'XSS\')">Click me</div>'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: malicious_tree,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).not_to include("onclick")
      expect(template.node_tree).not_to include("alert")
      expect(template.node_tree).to include("Click me")
    end

    it "removes dangerous iframe tags from node_tree" do
      malicious_tree = '<p>Content</p><iframe src="https://evil.com"></iframe>'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: malicious_tree,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).not_to include("<iframe")
      expect(template.node_tree).to include("<p>Content</p>")
    end

    it "removes javascript: protocol from links in node_tree" do
      malicious_tree = '<a href="javascript:alert(\'XSS\')">Click</a>'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: malicious_tree,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).not_to include("javascript:")
      expect(template.node_tree).not_to include("alert")
    end

    it "preserves safe HTML in node_tree" do
      safe_tree = '<p>Hello <strong>World</strong></p><ul><li>Item 1</li><li>Item 2</li></ul>'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: safe_tree,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).to include("<p>")
      expect(template.node_tree).to include("<strong>")
      expect(template.node_tree).to include("<ul>")
      expect(template.node_tree).to include("<li>")
    end

    it "adds security attributes to external links" do
      tree_with_link = '<a href="https://example.com">Link</a>'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: tree_with_link,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).to include('rel="nofollow')
      expect(template.node_tree).to include('rel="noopener')
      expect(template.node_tree).to include('target="_blank"')
    end

    it "removes onerror attributes from img tags" do
      malicious_tree = '<img src="invalid" onerror="alert(\'XSS\')">'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: malicious_tree,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).not_to include("onerror")
      expect(template.node_tree).not_to include("alert")
    end

    it "updates node_tree with sanitization on save" do
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: '<p>Initial</p>',
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      malicious_update = '<p>Updated</p><script>alert("XSS")</script>'
      template.update!(node_tree: malicious_update)

      expect(template.reload.node_tree).not_to include("<script>")
      expect(template.node_tree).not_to include('alert("XSS")')
      expect(template.node_tree).to include("<p>Updated</p>")
    end

    it "removes SVG with embedded scripts" do
      malicious_tree = '<svg><script>alert("XSS")</script></svg>'
      template = BlockEditorTemplate.create!({
                                               context_type: "Course",
                                               context_id: @course.id,
                                               name: "test",
                                               node_tree: malicious_tree,
                                               editor_version: "1.0",
                                               template_type: "block"
                                             })

      expect(template.node_tree).not_to include("<script>")
      expect(template.node_tree).not_to include("alert")
    end
  end
end
