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

describe SanitizedHtmlType do
  let(:type) { described_class.new }

  describe "#cast_value" do
    it "sanitizes HTML when casting" do
      malicious_html = '<p>Hello</p><script>alert("XSS")</script>'
      result = type.cast_value(malicious_html)
      expect(result.to_s).not_to include("<script>")
      expect(result.to_s).not_to include('alert("XSS")')
      expect(result.to_s).to include("<p>Hello</p>")
    end

    it "removes javascript event handlers" do
      malicious_html = '<div onclick="alert(\'XSS\')">Click me</div>'
      result = type.cast_value(malicious_html)
      expect(result.to_s).not_to include("onclick")
      expect(result.to_s).not_to include("alert")
    end

    it "preserves safe HTML" do
      safe_html = '<p>Safe <strong>content</strong></p>'
      result = type.cast_value(safe_html)
      expect(result.to_s).to include("<p>")
      expect(result.to_s).to include("<strong>")
      expect(result.to_s).to include("Safe")
      expect(result.to_s).to include("content")
    end

    it "handles nil values" do
      expect { type.cast_value(nil) }.not_to raise_error
    end

    it "handles empty strings" do
      result = type.cast_value("")
      expect(result.to_s).to eq("")
    end
  end

  describe "ActiveRecord integration" do
    it "is registered as :santized_html type" do
      type_from_registry = ActiveRecord::Type.lookup(:santized_html)
      expect(type_from_registry).to be_a(SanitizedHtmlType)
    end
  end
end
