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
  class LoginController < ::ApplicationController
    include FallbackRoutesConcern
    include ::Login::Shared

    class LoginError < ::StandardError; end

    protect_from_forgery except: :callback, with: :exception

    before_action :forbid_on_files_domain
    before_action :run_login_hooks, :fix_ms_office_redirects, only: :new
    skip_before_action :require_user, only: %i[new callback destroy]

    def new
      aac
      increment_statsd(:attempts)

      # Redirect to Kratos login flow
      uri = ::URI.join(aac.kratos_public_url, "/self-service/login/browser")
      params_hash = { return_to: kratos_callback_url }
      uri.query = URI.encode_www_form(params_hash)

      redirect_to uri.to_s
    end

    def callback
      logger.info "Attempting Kratos login with session token in account #{@domain_root_account.id}"

      session_cookie = extract_session_cookie

      increment_statsd(:attempts)

      session_data = fetch_session_data(session_cookie)

      unless session_data["active"]
        if debugging
          aac.debug_set(:active_session, t("Kratos session is not active"))
        end

        increment_statsd(:failure, reason: :inactive_session)

        raise LoginError, "Failed Kratos login attempt - session not active"
      end

      if aac.debugging?
        aac.debug_set(:active_session, t("Kratos session is active"))
      end

      reset_session_for_login

      (metadata, unique_id) = extract_identity(session_data)

      pseudonym = if aac.jit_provisioning?
                    find_pseudonym(metadata, unique_id) || aac.provision_user(unique_id, metadata)
                  else
                    find_pseudonym(metadata, unique_id)
                  end

      user = pseudonym&.login_assertions_for_user

      if user
        aac.debug_set(:user, user.id) if aac.debugging?

        login_pseudonym(pseudonym, user)
      else
        aac.debug_set(:user, t("Unknown user")) if aac.debugging?

        logger.warn "Received Kratos login for unknown user: #{unique_id}"
        redirect_to_unknown_user_url(t("Canvas doesn't have an account for user: %{user}", user: unique_id))
        increment_statsd(:failure, reason: :unknown_user)
      end
    rescue LoginError => e
      logger.warn e.message
      flash[:delegated_message] = t("There was a problem logging in at %{institution}",
                                    institution: @domain_root_account.display_name)
      redirect_to login_url
    end

    def destroy
      # Kratos handles logout through its own endpoint
      # This is called as part of Canvas logout flow
      render plain: "OK", status: :ok
    end

    private

    def aac
      @aac ||= begin
        scope = @domain_root_account.authentication_providers.active.where(auth_type: "Kratos::Provider")
        params[:id] ? scope.find(params[:id]) : scope.first!
      end
    end

    def auth_type
      Kratos.sti_name
    end

    def find_pseudonym(metadata, unique_id)
      @domain_root_account.pseudonyms.for_auth_configuration(unique_id, aac).tap do |pseudonym|
        if pseudonym
          aac.apply_federated_attributes(pseudonym, metadata)
        end
      end
    end

    def extract_session_cookie
      # Kratos can pass the session token via cookie or query parameter
      session_cookie = cookies["ory_kratos_session"]

      if session_cookie.blank?
        raise LoginError, "No Kratos session token found"
      end

      aac.debug_set(:session_received, session_cookie[0..20] + "...") if aac.debugging?

      session_cookie
    end

    def extract_identity(session_data)
      identity = session_data["identity"]

      unless identity
        increment_statsd(:failure, reason: :no_identity)

        raise LoginError, "No identity found in Kratos session"
      end

      aac.debug_set(:identity_data, identity.to_json) if aac.debugging?

      unique_id = identity.dig("traits", "email") || identity["id"]

      raise LoginError, "No unique identifier found in Kratos session" unless unique_id

      aac.debug_set(:unique_id, unique_id.to_s) if aac.debugging?

      metadata = identity.slice("metadata_admin", "metadata_public", "traits")

      [metadata, unique_id]
    end

    # Fetch the Kratos Session Data.
    def fetch_session_data(session_cookie)
      return nil if session_cookie.blank?

      cookie = "ory_kratos_session=#{session_cookie}"

      response = ::Canvas.timeout_protection("kratos:#{aac.global_id}", { raise_on_timeout: true, fallback_timeout_length: 10.0 }) do
        ::CanvasHttp.get(aac.fetch_session_url, { "Cookie" => cookie, "Accept" => "application/json" })
      end

      if response.is_a?(::Net::HTTPSuccess)
        aac.debug_set(:whoami_response, response.body) if aac.debugging?

        ::JSON.parse(response.body)
      else
        if aac.debugging?
          aac.debug_set(:whoami_response, "Kratos session fetch failed: #{response.code} #{response.body}")
        end

        raise LoginError, "Kratos session fetch failed: #{response.code} #{response.body}"
      end
    rescue LoginError
      raise
    rescue Timeout::Error => e
      if e.respond_to?(:error_count)
        increment_statsd(:failure, reason: :timeout, tags: { error_count: e.error_count })
      else
        increment_statsd(:failure, reason: :timeout)
      end

      if aac.debugging?
        aac.debug_set(:whoami_response, "Error fetching Kratos session: #{e.message}")
      end

      ::Canvas::Errors.capture_exception(:kratos, e)

      raise LoginError, "Error fetching Kratos session: #{e.message}"
    rescue => e
      increment_statsd(:failure, reason: :validation_error)

      if aac.debugging?
        aac.debug_set(:whoami_response, "Error fetching Kratos session: #{e.message}")
      end

      ::Canvas::Errors.capture_exception(:kratos, e)

      raise LoginError, "Error fetching Kratos session: #{e.message}"
    end

    def kratos_callback_url
      # Use url_for with action since we're already in the right controller context
      # This avoids namespace issues with controller: "login/kratos" vs "kratos/login"
      url_for(action: :callback, only_path: false, **params.permit(:id).to_h)
    end

    def login_pseudonym(pseudonym, user)
      # Successful login and we have a user

      @domain_root_account.pseudonyms.scoping do
        ::PseudonymSession.create!(pseudonym, false)
      end
      session[:kratos_session_id] = identity["id"]
      session[:login_aac] = aac.id

      pseudonym.infer_auth_provider(aac)
      successful_login(user, pseudonym)
    end
  end
end
