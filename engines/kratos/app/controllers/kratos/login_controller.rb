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

      # Kratos can pass the session token via cookie or query parameter
      session_token = extract_session_token

      if session_token.blank?
        logger.warn "No Kratos session token found"
        flash[:delegated_message] = t("There was a problem logging in at %{institution}",
                                      institution: @domain_root_account.display_name)
        return redirect_to login_url
      end

      # only record further information if we're the first incoming session to fill out debugging info
      debugging = aac.debug_set(:session_received, session_token[0..20] + "...", overwrite: false) if aac.debugging?
      increment_statsd(:attempts)

      begin
        timeout_options = { raise_on_timeout: true, fallback_timeout_length: 10.0 }

        session_data = ::Canvas.timeout_protection("kratos:#{aac.global_id}", timeout_options) do
          aac.fetch_session_data(session_token)
        end
      rescue => e
        logger.warn "Failed to validate Kratos session: #{e.inspect}"

        if e.is_a?(::Timeout::Error)
          if e.respond_to?(:error_count)
            increment_statsd(:failure, reason: :timeout, tags: { error_count: e.error_count })
          else
            increment_statsd(:failure, reason: :timeout)
          end
        else
          increment_statsd(:failure, reason: :validation_error)
        end

        aac.debug_set(:whoami_response, t("Failed to validate Kratos session: %{error}", error: e)) if debugging
        flash[:delegated_message] = t("There was a problem logging in at %{institution}",
                                      institution: @domain_root_account.display_name)
        return redirect_to login_url
      end

      aac.debug_set(:whoami_response, session_data.to_json) if debugging

      if session_data && session_data["active"]
        aac.debug_set(:active_session, t("Kratos session is active"))

        reset_session_for_login

        find_pseudonym(session_data)
      else
        if debugging
          aac.debug_set(:active_session, t("Kratos session is not active"))
        end
        logger.warn "Failed Kratos login attempt - session not active"
        flash[:delegated_message] = t("There was a problem logging in at %{institution}",
                                      institution: @domain_root_account.display_name)
        redirect_to login_url
        increment_statsd(:failure, reason: :inactive_session)
      end
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

    def extract_session_token
      # Try to get session token from cookie first (Kratos default)
      session_token = cookies["ory_kratos_session"]

      # Fallback to query parameter if cookie not present
      session_token ||= request.headers["X-Session-Token"]
      session_token ||= params[:session_token]

      session_token
    end

    def find_pseudonym(session_data)
      identity = session_data["identity"]
      return handle_no_identity unless identity

      aac.debug_set(:identity_data, identity.to_json) if aac.debugging?

      # Extract unique identifier from identity
      # This could be the identity ID or a specific trait depending on your Kratos schema
      unique_id = identity.dig("traits", "email") || identity["id"]

      metadata = identity.slice("metadata_admin", "metadata_public", "traits")

      pseudonym = @domain_root_account.pseudonyms.for_auth_configuration(unique_id, aac)
      if pseudonym
        aac.apply_federated_attributes(pseudonym, metadata)
      elsif aac.jit_provisioning?
        pseudonym = aac.provision_user(unique_id, metadata)
      end

      if pseudonym && (user = pseudonym.login_assertions_for_user)
        # Successful login and we have a user

        @domain_root_account.pseudonyms.scoping do
          ::PseudonymSession.create!(pseudonym, false)
        end
        session[:kratos_session_id] = identity["id"]
        session[:login_aac] = aac.id

        pseudonym.infer_auth_provider(aac)
        successful_login(user, pseudonym)
      else
        logger.warn "Received Kratos login for unknown user: #{unique_id}"
        redirect_to_unknown_user_url(t("Canvas doesn't have an account for user: %{user}", user: unique_id))
        increment_statsd(:failure, reason: :unknown_user)
      end
    end

    def handle_no_identity
      logger.warn "No identity found in Kratos session"
      flash[:delegated_message] = t("There was a problem logging in at %{institution}",
                                    institution: @domain_root_account.display_name)
      redirect_to login_url
      increment_statsd(:failure, reason: :no_identity)
    end

    def kratos_callback_url
      # Use url_for with action since we're already in the right controller context
      # This avoids namespace issues with controller: "login/kratos" vs "kratos/login"
      url_for(action: :callback, only_path: false, **params.permit(:id).to_h)
    end
  end
end
