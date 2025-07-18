# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
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

require_relative "../../spec_helper"
require "rotp"

describe Login::CasController do
  def stubby(stub_response, use_mock = true)
    cas_client = use_mock ? double(:cas_client).as_null_object : controller.client
    cas_client.instance_variable_set(:@stub_response, stub_response)
    def cas_client.validate_service_ticket(st)
      response = CASClient::ValidationResponse.new(@stub_response)
      st.user = response.user
      st.success = response.is_success?
      st
    end
    allow_any_instance_of(AuthenticationProvider::CAS).to receive(:client).and_return(cas_client) if use_mock
  end

  it "logouts with specific cas ticket" do
    account = account_with_cas(account: Account.default)
    user_with_pseudonym(active_all: true, account:)

    cas_ticket = CanvasUuid::Uuid.generate_securish_uuid
    request_text = <<~XML.strip
      <samlp:LogoutRequest
        xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"
        xmlns:saml="urn:oasis:names:tc:SAML:2.0:assertion"
        ID="_42"
        Version="2.0"
        IssueInstant="#{Time.zone.now.iso8601}">
        <saml:NameID>@NOT_USED@</saml:NameID>
        <samlp:SessionIndex>#{cas_ticket}</samlp:SessionIndex>
      </samlp:LogoutRequest>
    XML

    session[:cas_session] = cas_ticket
    session[:login_aac] = Account.default.authentication_providers.first.id

    post :destroy, params: { logoutRequest: request_text }
    expect(response).to have_http_status :ok
  end

  it "doesn't allow deleted users to login" do
    account = account_with_cas(account: Account.default)
    user_with_pseudonym(active_all: true, account:)
    @user.update!(workflow_state: "deleted")

    response_text = <<~XML
      <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
        <cas:authenticationSuccess>
          <cas:user>#{@user.email}</cas:user>
        </cas:authenticationSuccess>
      </cas:serviceResponse>
    XML

    controller.instance_variable_set(:@domain_root_account, Account.default)
    cas_client = controller.client
    cas_client.instance_variable_set(:@stub_response, response_text)
    def cas_client.request_cas_response(_uri, type, _options = {})
      type.new(@stub_response, @conf_options)
    end

    get "new", params: { ticket: "ST-abcd" }
    expect(response).to redirect_to(login_url)
  end

  it "doesn't allow suspended users to login" do
    account = account_with_cas(account: Account.default)
    user_with_pseudonym(active_all: true, account:)
    @pseudonym.update!(workflow_state: "suspended")

    response_text = <<~XML
      <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
        <cas:authenticationSuccess>
          <cas:user>#{@user.email}</cas:user>
        </cas:authenticationSuccess>
      </cas:serviceResponse>
    XML

    controller.instance_variable_set(:@domain_root_account, Account.default)
    cas_client = controller.client
    cas_client.instance_variable_set(:@stub_response, response_text)
    def cas_client.request_cas_response(_uri, type, _options = {})
      type.new(@stub_response, @conf_options)
    end

    get "new", params: { ticket: "ST-abcd" }
    expect(response).to redirect_to(login_url)
  end

  it "accepts extra attributes" do
    account = account_with_cas(account: Account.default)
    user_with_pseudonym(active_all: true, account:)

    response_text = <<~XML
      <cas:serviceResponse xmlns:cas="http://www.yale.edu/tp/cas">
        <cas:authenticationSuccess>
          <cas:user>#{@user.email}</cas:user>
          <cas:attributes>
            <cas:name>#{@user.name}</cas:name>
            <cas:email><![CDATA[#{@user.email}]]></cas:email>
            <cas:yaml><![CDATA[--- true]]></cas:yaml>
            <cas:json><![CDATA[{"id":#{@user.id}]]></cas:json>
          </cas:attributes>
        </cas:authenticationSuccess>
      </cas:serviceResponse>
    XML

    controller.instance_variable_set(:@domain_root_account, Account.default)
    cas_client = controller.client
    cas_client.instance_variable_set(:@stub_response, response_text)
    def cas_client.request_cas_response(_uri, type, _options = {})
      type.new(@stub_response, @conf_options)
    end

    get "new", params: { ticket: "ST-abcd" }
    expect(response).to redirect_to(dashboard_url(login_success: 1))
    expect(session[:cas_session]).to eq "ST-abcd"
    # the auth provider got set on the pseudonym
    expect(assigns[:current_pseudonym].authentication_provider).to eq account.authentication_providers.active.find("cas")
  end

  it "scopes logins to the correct domain root account" do
    unique_id = "foo@example.com"

    account1 = account_with_cas
    user1 = user_with_pseudonym({ active_all: true, username: unique_id })
    @pseudonym.account = account1
    @pseudonym.save!

    account2 = account_with_cas
    user2 = user_with_pseudonym({ active_all: true, username: unique_id })
    @pseudonym.account = account2
    @pseudonym.save!

    stubby("yes\n#{unique_id}\n")

    controller.request.env["canvas.domain_root_account"] = account1
    get "new", params: { ticket: "ST-abcd" }
    expect(response).to redirect_to(dashboard_url(login_success: 1))
    expect(session[:cas_session]).to eq "ST-abcd"
    expect(Pseudonym.find(session["pseudonym_credentials_id"])).to eq user1.pseudonyms.first

    (controller.instance_variables.grep(/@[^_]/) - ["@mock_proxy"]).each do |var|
      controller.send :remove_instance_variable, var
    end
    session.clear

    stubby("yes\n#{unique_id}\n")

    controller.request.env["canvas.domain_root_account"] = account2
    get "new", params: { ticket: "ST-efgh" }
    expect(response).to redirect_to(dashboard_url(login_success: 1))
    expect(session[:cas_session]).to eq "ST-efgh"
    expect(Pseudonym.find(session["pseudonym_credentials_id"])).to eq user2.pseudonyms.first
  end

  context "unknown user" do
    let!(:account) { account_with_cas(account: Account.default) }

    before do
      stubby("yes\nfoo@example.com\n")
    end

    it "redirects when a user is authorized but not found in canvas" do
      # We dont want to log them out of everything.
      expect(controller).not_to receive(:logout_user_action)

      # Default to Login url with a nil value
      session[:sentinel] = true
      get "new", params: { ticket: "ST-abcd" }
      expect(response).to redirect_to(login_url)
      expect(session[:cas_session]).to be_nil
      expect(flash[:delegated_message]).to match(/Canvas doesn't have an account for user/)
      expect(session[:sentinel]).to be_nil
    end

    it "sends to login page if unknown_user_url is blank" do
      # Default to Login url with an empty string value
      account.unknown_user_url = ""
      account.save!

      get "new", params: { ticket: "ST-abcd" }
      expect(response).to redirect_to(login_url)
      expect(session[:cas_session]).to be_nil
      expect(flash[:delegated_message]).to match(/Canvas doesn't have an account for user/)
    end

    it "uses the unknown_user_url from the aac" do
      unknown_user_url = "https://example.com/unknown_user"
      account.unknown_user_url = unknown_user_url
      account.save!
      get "new", params: { ticket: "ST-abcd" }
      expect(response).to redirect_to(/^#{unknown_user_url}\?message=Canvas/)
      expect(session[:cas_session]).to be_nil
    end

    it "provisions automatically when enabled" do
      ap = account.authentication_providers.first
      ap.update_attribute(:jit_provisioning, true)
      unique_id = "foo@example.com"

      expect(account.pseudonyms.active.by_unique_id(unique_id)).to_not be_exists
      get "new", params: { ticket: "ST-abcd" }
      expect(response).to redirect_to(dashboard_url(login_success: 1))
      expect(session[:cas_session]).to eq "ST-abcd"
      p = account.pseudonyms.active.by_unique_id(unique_id).first!
      expect(p.authentication_provider).to eq ap
    end
  end

  it "times out correctly" do
    account_with_cas(account: Account.default)
    ap = Account.default.authentication_providers.detect { |a| a.auth_type == "cas" }
    Setting.set("service_cas:#{ap.global_id}_timeout", "0.01")
    cas_client = double
    allow(controller).to receive(:client).and_return(cas_client)
    start = Time.now.utc
    allow(Canvas::Errors).to receive(:capture_exception).and_return(true)
    allow(InstStatsd::Statsd).to receive(:distributed_increment)
    expect(cas_client).to receive(:validate_service_ticket) { sleep 5 }
    session[:sentinel] = true
    get "new", params: { ticket: "ST-abcd" }
    expect(response).to redirect_to(login_url)
    expect(flash[:delegated_message]).to_not be_blank
    expect(Time.now.utc - start).to be < 1
    expect(session[:sentinel]).to be true
    expect(InstStatsd::Statsd).to have_received(:distributed_increment).with(
      "auth.create.failure.v2", tags: { auth_type: ap.auth_type.to_s, auth_provider_id: ap.global_id, target_auth_type: "cas", domain: request.host, reason: :timeout }
    )
  end

  it "sets a cookie for site admin login" do
    user_with_pseudonym(account: Account.site_admin)
    stubby("yes\n#{@pseudonym.unique_id}\n")
    account_with_cas(account: Account.site_admin)

    controller.request.env["canvas.domain_root_account"] = Account.site_admin
    get "new", params: { ticket: "ST-efgh" }
    expect(response).to redirect_to(dashboard_url(login_success: 1))
    expect(session[:cas_session]).to eq "ST-efgh"
    expect(cookies["canvas_sa_delegated"]).to eq "1"
  end

  it "redirects to site admin CAS if cookie set" do
    user_with_pseudonym(account: Account.site_admin)
    stubby("yes\n#{@pseudonym.unique_id}\n")
    account_with_cas(account: Account.site_admin)
    controller.instance_variable_set(:@domain_root_account, Account.site_admin)
    expect(controller.client).to receive(:login_url).and_return("someurl")

    cookies["canvas_sa_delegated"] = "1"
    # *don't* double domain_root_account
    get "new"
    expect(response).to be_redirect
  end

  it "does not force otp reconfiguration on succesful login" do
    Account.default.settings[:mfa_settings] = :required
    Account.default.save!
    account_with_cas(account: Account.default)

    user_with_pseudonym(active_all: 1, username: "user")
    @user.otp_secret_key = ROTP::Base32.random
    @user.save!

    stubby("yes\nuser\n")

    get "new", params: { ticket: "ST-efgh" }
    expect(response).to redirect_to(otp_login_url)
    expect(session[:cas_session]).to eq "ST-efgh"
    expect(session[:pending_otp_secret_key]).to be_nil
  end
end
