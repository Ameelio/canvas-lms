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

describe HtmlSantization do
  describe ".call" do
    it "removes script tags" do
      malicious_html = '<p>Hello</p><script>alert("XSS")</script>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<script>")
      expect(result.to_s).not_to include('alert("XSS")')
      expect(result.to_s).to include("<p>Hello</p>")
    end

    it "removes inline javascript event handlers" do
      malicious_html = '<div onclick="alert(\'XSS\')">Click me</div>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("onclick")
      expect(result.to_s).not_to include("alert")
      expect(result.to_s).to include("Click me")
    end

    it "removes javascript: protocol in links" do
      malicious_html = '<a href="javascript:alert(\'XSS\')">Click</a>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("javascript:")
      expect(result.to_s).not_to include("alert")
    end

    it "removes onerror attributes from img tags" do
      malicious_html = '<img src="invalid" onerror="alert(\'XSS\')">'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("onerror")
      expect(result.to_s).not_to include("alert")
    end

    it "removes malformed HTML tags" do
      malicious_html = "<p>Hello<script>alert('XSS')"
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<script>")
      expect(result.to_s).not_to include("alert")
      expect(result.to_s).to include("Hello")
    end

    it "adds noopener to links" do
      html = '<a href="https://example.com" target="_blank">Link</a>'
      result = described_class.call(html)
      expect(result.to_s).to include('rel="noopener')
    end

    it "adds nofollow to links" do
      html = '<a href="https://example.com">Link</a>'
      result = described_class.call(html)
      expect(result.to_s).to include('rel="nofollow')
    end

    it "adds target=_blank to links" do
      html = '<a href="https://example.com">Link</a>'
      result = described_class.call(html)
      expect(result.to_s).to include('target="_blank"')
    end

    it "removes unprintable characters" do
      html_with_unprintable = "<p>Hello\u0000World</p>"
      result = described_class.call(html_with_unprintable)
      expect(result.to_s).not_to include("\u0000")
      expect(result.to_s).to include("HelloWorld")
    end

    it "removes data: protocol in img src" do
      malicious_html = '<img src="data:text/html,<script>alert(\'XSS\')</script>">'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("data:text/html")
    end

    it "removes iframe tags" do
      malicious_html = '<iframe src="https://evil.com"></iframe>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<iframe")
    end

    it "removes embed tags" do
      malicious_html = '<embed src="https://evil.com">'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<embed")
    end

    it "removes object tags" do
      malicious_html = '<object data="https://evil.com"></object>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<object")
    end

    it "preserves safe HTML content" do
      safe_html = '<p>Hello <strong>World</strong></p><ul><li>Item 1</li><li>Item 2</li></ul>'
      result = described_class.call(safe_html)
      expect(result.to_s).to include("<p>")
      expect(result.to_s).to include("<strong>")
      expect(result.to_s).to include("<ul>")
      expect(result.to_s).to include("<li>")
      expect(result.to_s).to include("Hello")
      expect(result.to_s).to include("World")
    end

    it "handles nil input" do
      expect { described_class.call(nil) }.not_to raise_error
    end

    it "handles empty string" do
      result = described_class.call("")
      expect(result.to_s).to eq("")
    end

    it "removes SVG with embedded scripts" do
      malicious_html = '<svg><script>alert("XSS")</script></svg>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<script>")
      expect(result.to_s).not_to include("alert")
    end

    it "removes base64 encoded javascript in links" do
      malicious_html = '<a href="data:text/html;base64,PHNjcmlwdD5hbGVydCgnWFNTJyk8L3NjcmlwdD4=">Click</a>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("data:text/html")
    end

    it "removes onload attributes" do
      malicious_html = '<body onload="alert(\'XSS\')">Content</body>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("onload")
      expect(result.to_s).not_to include("alert")
    end

    it "removes form tags" do
      malicious_html = '<form action="https://evil.com"><input name="password"></form>'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<form")
    end

    it "removes meta refresh tags" do
      malicious_html = '<meta http-equiv="refresh" content="0;url=https://evil.com">'
      result = described_class.call(malicious_html)
      expect(result.to_s).not_to include("<meta")
    end
  end
end
