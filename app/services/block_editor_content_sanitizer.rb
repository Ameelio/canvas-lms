# frozen_string_literal: true

# Sanitizes the user-controlled portions of both block editor document formats.
class BlockEditorContentSanitizer
  LINK_URL_FIELD_NAMES = %w[buttonLink href linkUrl url].freeze
  SOURCE_URL_FIELD_NAMES = %w[fileUrl iframe_url poster src].freeze
  URL_FIELD_NAMES = (LINK_URL_FIELD_NAMES + SOURCE_URL_FIELD_NAMES).freeze
  URL_FIELD_SUFFIX = /(?:href|src|url)\z/i
  LINK_SCHEMES = %w[ftp http https mailto tel].freeze
  SOURCE_SCHEMES = %w[http https].freeze
  SCHEME = /\A([A-Za-z][A-Za-z0-9+.-]*):/
  # Plain text containing a bare "<" (e.g. "if a<b then") must survive, so
  # only strings holding a complete tag, or an unterminated tag that could
  # become live markup if completed downstream, go through Sanitize.
  HTML_MARKUP_PATTERNS = [
    %r{</?[A-Za-z][^>]*>},                                                  # complete tag
    /<[A-Za-z][^>]*\s\S+=/,                                                 # dangling open tag with an attribute
    %r{</[A-Za-z]},                                                         # dangling close tag
    /<(?:base|embed|form|iframe|link|math|meta|object|script|style|svg)\b/i # dangling risky tag
  ].freeze
  # Content nested deeper than this is dropped rather than risking a
  # SystemStackError while recursing.
  MAX_DEPTH = 500

  class << self
    def sanitize(data)
      return sanitize_serialized_document(data) if serialized_document?(data)

      sanitize_value(data)
    end

    private

    def sanitize_value(value, field_name = nil, depth = 0)
      case value
      when Hash
        return nil if depth >= MAX_DEPTH

        value.each_with_object({}) do |(key, child), sanitized|
          sanitized[key] = sanitize_value(child, key.to_s, depth + 1)
        end
      when Array
        return nil if depth >= MAX_DEPTH

        value.map { |child| sanitize_value(child, field_name, depth + 1) }
      when String
        sanitize_string(value, field_name)
      else
        value
      end
    end

    def sanitize_string(value, field_name)
      return sanitize_url(value, field_name) if url_field?(field_name)
      return Sanitize.clean(value, CanvasSanitize::SANITIZE) if html_markup?(value)

      value
    end

    def html_markup?(value)
      HTML_MARKUP_PATTERNS.any? { |pattern| value.match?(pattern) }
    end

    def sanitize_url(value, field_name)
      normalized = value.strip.delete("\u0000-\u0020")
      scheme = normalized.match(SCHEME)&.captures&.first&.downcase
      return value unless scheme

      allowed_schemes = LINK_URL_FIELD_NAMES.include?(field_name) ? LINK_SCHEMES : SOURCE_SCHEMES
      allowed_schemes.include?(scheme) ? value : ""
    end

    def url_field?(field_name)
      field_name && (URL_FIELD_NAMES.include?(field_name) || field_name.match?(URL_FIELD_SUFFIX))
    end

    def serialized_document?(data)
      data.is_a?(String) && ["{", "["].include?(data.lstrip.first)
    end

    def sanitize_serialized_document(data)
      JSON.generate(sanitize_value(JSON.parse(data, max_nesting: MAX_DEPTH)), max_nesting: false)
    rescue JSON::ParserError
      # Fail closed: an unparseable "document" (JSON::NestingError included) is
      # scrubbed as a plain string rather than returned verbatim.
      sanitize_string(data, nil)
    end
  end
end
