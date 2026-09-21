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
        active_session: -> { t("Active") },
        identity_data: -> { t("Identity Data") },
        unique_id: -> { t("Unique ID") },
      }]
    end

    def fetch_session_url
      ::URI.join(kratos_api_url, "/sessions/whoami").to_s
    end

    def login_authentication_provider_path
      unless persisted?
        raise ActionController::UrlGenerationError, "Cannot generate URL for unsaved authentication provider"
      end

      "kratos/#{id}"
    end

    def login_url_options
      Kratos::Engine.routes.url_helpers.kratos_login_path(id:)
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

    def translate_provider_attributes(provider_attributes)
      # Ory Kratos likes to nest their traits, this allows for specifying via dot notation the nested trait.
      federated_attributes.each_with_object({}) do |(canvas_attribute_name, provider_attribute_config), memo|
        chain = provider_attribute_config["attribute"].split(".")

        deepest_hash = if chain.length > 1
                         provider_attributes.dig(*chain[0...-1])
                       else
                         provider_attributes
                       end

        if deepest_hash.key?(chain.last)
          memo[canvas_attribute_name] = deepest_hash[chain.last]
        end
      end
    end
  end
end
