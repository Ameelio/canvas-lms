# frozen_string_literal: true

# Sanitizes the user-controlled portions of both block editor document formats.
class BlockEditorContentSanitizer
  LINK_URL_FIELD_NAMES = %w[buttonLink href linkUrl url].freeze
  SOURCE_URL_FIELD_NAMES = %w[fileUrl iframe_url poster src].freeze
  URL_FIELD_NAMES = (LINK_URL_FIELD_NAMES + SOURCE_URL_FIELD_NAMES).freeze
  URL_FIELD_SUFFIX = /(?:href|src|url)\z/i
  LINK_SCHEMES = %w[ftp http https mailto tel].freeze
  SOURCE_SCHEMES = %w[http https].freeze
  HTML_MARKUP = %r{</?[A-Za-z]}
  SCHEME = /\A([A-Za-z][A-Za-z0-9+.-]*):/

  class << self
    def sanitize(data)
      return sanitize_serialized_document(data) if serialized_document?(data)

      sanitize_value(data)
    end

    private

    def sanitize_value(value, field_name = nil)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), sanitized|
          sanitized[key] = sanitize_value(child, key.to_s)
        end
      when Array
        value.map { |child| sanitize_value(child) }
      when String
        sanitize_string(value, field_name)
      else
        value
      end
    end

    def sanitize_string(value, field_name)
      return sanitize_url(value, field_name) if url_field?(field_name)
      return Sanitize.clean(value, CanvasSanitize::SANITIZE) if value.match?(HTML_MARKUP)

      value
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
      JSON.generate(sanitize_value(JSON.parse(data)))
    rescue JSON::ParserError
      data
    end
  end
end
