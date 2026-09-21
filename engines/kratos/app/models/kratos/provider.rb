# frozen_string_literal: true

#
# Copyright (C) 2026 - present Ameelio.
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

module Kratos
  class Provider < ::AuthenticationProvider::Delegated
    store_accessor :settings, :kratos_admin_url, :kratos_public_url

    after_create :disable_open_registration

    def self.sti_name
      "Kratos::Provider"
    end

    def self.display_name
      "Ory Kratos"
    end

    def self.recognized_params
      %i[kratos_public_url kratos_admin_url jit_provisioning].freeze
    end

    def self.recognized_federated_attributes
      # we allow any attribute from Kratos identity traits
      nil
    end

    def self.supports_debugging?
      debugging_enabled?
    end

    def self.debugging_sections
      [nil]
    end

    def self.debugging_keys
      [{
        debugging: -> { t("Testing state") },
        session_received: -> { t("Received Kratos Session Token") },
        whoami_response: -> { t("Whoami Response") },
        identity_data: -> { t("Identity Data") },
      }]
    end

    def user_logout_redirect(controller, _current_user)
      # Kratos logout endpoint
      return "#{kratos_public_url}/self-service/logout/browser" if kratos_public_url.present?

      super
    end

    private

    def disable_open_registration
      if account.open_registration?
        account.settings[:open_registration] = false
        account.save!
      end
    end

    # The base URL for Kratos API calls (defaults to admin URL if set, otherwise public URL)
    def kratos_api_url
      kratos_admin_url.presence || kratos_public_url
    end

    # Validate a Kratos session token and return session data
    def validate_session(session_token)
      return nil if session_token.blank?

      uri = ::URI.join(kratos_api_url, "/sessions/whoami")

      response = ::CanvasHttp.get(uri.to_s) do |request|
        request["X-Session-Token"] = session_token
        request["Accept"] = "application/json"
      end

      if response.is_a?(::Net::HTTPSuccess)
        ::JSON.parse(response.body)
      else
        ::Rails.logger.warn("Kratos session validation failed: #{response.code} #{response.body}")
        nil
      end
    rescue => e
      ::Rails.logger.error("Error validating Kratos session: #{e.message}")
      ::Canvas::Errors.capture_exception(:kratos, e)
      nil
    end
  end
end
