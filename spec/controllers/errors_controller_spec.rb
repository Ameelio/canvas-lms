# frozen_string_literal: true

#
# Copyright (C) 2013 - present Instructure, Inc.
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

describe ErrorsController do
  def authenticate_user!
    @user = User.create!
    Account.site_admin.account_users.create!(user: @user)
    user_session(@user)
  end

  describe "index" do
    before { authenticate_user! }

    it "does not error" do
      get "index"
    end
  end

  describe "POST create" do
    def assert_recorded_error(msg = "Thanks for your help!  We'll get right on this")
      expect(flash[:notice]).to eql(msg)
      expect(response).to be_redirect
      expect(response).to redirect_to(root_url)
    end

    it "creates a new error report" do
      authenticate_user!
      post "create", params: {
        error: {
          url: "someurl",
          message: "BigError",
          email: "testerrors42@example.com",
          user_roles: "spoofed-admin"
        }
      }
      assert_recorded_error
      expect(ErrorReport.last.email).to eq("testerrors42@example.com")
      expect(ErrorReport.last.data["user_roles"]).to eq(@user.roles(Account.default).join(","))
      expect(ErrorReport.last.url).to be_nil
    end

    it "doesnt need authentication" do
      post "create", params: { error: { message: "BigError" } }
      assert_recorded_error
    end

    it "is successful without data" do
      post "create"
      assert_recorded_error
    end

    it "is successful with limited data" do
      post "create", params: { error: { title: "ugly", message: "bacon", fried_ham: "stupid" } }
      assert_recorded_error
    end

    it "is successful when error is submitted as a string" do
      expect do
        post "create", params: { error: "broken" }
      end.to change { ErrorReport.count }.by(1)
      assert_recorded_error
    end

    it "is successful when error is submitted as an array" do
      expect do
        post "create", params: { error: ["broken"] }
      end.to change { ErrorReport.count }.by(1)
      assert_recorded_error
    end

    it "does not update a caller-selected error report" do
      existing_report = ErrorReport.create!(message: "original", account: Account.default)

      expect do
        post "create", params: { error: { id: existing_report.id, message: "replacement" } }
      end.to change { ErrorReport.count }.by(1)

      expect(existing_report.reload.message).to eq("original")
      expect(ErrorReport.order(:id).last.message).to eq("replacement")
    end

    it "ignores caller-supplied identity and environment fields" do
      authenticate_user!
      current_user = @user
      other_user = user_factory
      other_account = account_model
      request.headers["HTTP_REFERER"] = "http://test.host/courses/1"
      request.headers["HTTP_USER_AGENT"] = "real-agent"

      post "create",
           params: {
             error: {
               account_id: other_account.id,
               context_asset_string: "course_123",
               http_env: { "HTTP_AUTHORIZATION" => "secret" },
               request_context_id: "attacker-request",
               url: "https://attacker.example/",
               user_id: other_user.id,
               user_roles: "admin",
               zendesk_ticket_id: 123
             }
           }

      report = ErrorReport.order(:id).last
      expect(report.user).to eq(current_user)
      expect(report.account).to eq(Account.default)
      expect(report.url).to eq("http://test.host/courses/1")
      expect(report.user_agent).to eq("real-agent")
      expect(report.request_context_id).not_to eq("attacker-request")
      expect(report.zendesk_ticket_id).to be_nil
      expect(report.http_env).not_to include("HTTP_AUTHORIZATION" => "secret")
      expect(report.data["context_asset_string"]).to be_nil
      expect(report.data["user_roles"]).to eq(current_user.roles(Account.default).join(","))
    end

    it "enriches only the error report stored in the same user's session" do
      authenticate_user!
      existing_report = ErrorReport.create!(
        message: "original",
        user: @user,
        account: Account.default
      )
      session[:last_error_id] = existing_report.id

      expect do
        post "create", params: { error: { comments: "more detail" } }
      end.not_to change { ErrorReport.count }

      expect(existing_report.reload.comments).to eq("more detail")
    end

    it "does not enrich a session report owned by another user" do
      authenticate_user!
      existing_report = ErrorReport.create!(
        message: "original",
        user: user_factory,
        account: Account.default
      )
      session[:last_error_id] = existing_report.id

      expect do
        post "create", params: { error: { comments: "more detail" } }
      end.to change { ErrorReport.count }.by(1)

      expect(existing_report.reload.comments).to be_nil
    end

    it "does not enrich a stale session report" do
      authenticate_user!
      existing_report = ErrorReport.create!(message: "original", user: @user, account: Account.default)
      existing_report.update_column(:created_at, 2.hours.ago)
      session[:last_error_id] = existing_report.id

      expect do
        post "create", params: { error: { comments: "late" } }
      end.to change { ErrorReport.count }.by(1)

      expect(existing_report.reload.comments).to be_nil
    end

    it "enriches a session report created in student view for the real user" do
      authenticate_user!
      fake_student = course_factory.student_view_student
      existing_report = ErrorReport.create!(message: "original", user: fake_student, account: Account.default)
      session[:become_user_id] = fake_student.id
      session[:last_error_id] = existing_report.id

      expect do
        post "create", params: { error: { comments: "more detail" } }
      end.not_to change { ErrorReport.count }

      expect(existing_report.reload.comments).to eq("more detail")
      expect(existing_report.user_id).to eq(@user.id)
    end

    it "enriches a session report that has no user" do
      existing_report = ErrorReport.create!(message: "original", account: Account.default)
      session[:last_error_id] = existing_report.id

      expect do
        post "create", params: { error: { comments: "more detail" } }
      end.not_to change { ErrorReport.count }

      expect(existing_report.reload.comments).to eq("more detail")
    end

    it "keeps enriching the same report when the form resubmits its id" do
      authenticate_user!
      existing_report = ErrorReport.create!(message: "original", user: @user, account: Account.default)
      session[:last_error_id] = existing_report.id

      expect do
        post "create", params: { error: { id: existing_report.id, comments: "first try" } }
        post "create", params: { error: { id: existing_report.id, comments: "second try" } }
      end.not_to change { ErrorReport.count }

      expect(existing_report.reload.comments).to eq("second try")
      expect(session[:last_error_id]).to eq(existing_report.id)
    end

    it "ignores an error id that does not match the session" do
      authenticate_user!
      session_report = ErrorReport.create!(message: "mine", user: @user, account: Account.default)
      other_report = ErrorReport.create!(message: "not mine", user: @user, account: Account.default)
      session[:last_error_id] = session_report.id

      expect do
        post "create", params: { error: { id: other_report.id, comments: "sneaky" } }
      end.to change { ErrorReport.count }.by(1)

      expect(other_report.reload.comments).to be_nil
      expect(session_report.reload.comments).to be_nil
    end

    it "derives the report url from the referer even when the referer port differs" do
      request.headers["HTTP_REFERER"] = "https://test.host:8443/courses/1?m=1"
      post "create", params: { error: { message: "boom" } }

      expect(ErrorReport.order(:id).last.url).to eq("http://test.host/courses/1?m=1")
    end

    context "for API requests" do
      before do
        allow(controller).to receive(:api_request?).and_return(true)
      end

      it "stores a caller-supplied http(s) url" do
        post "create", params: { error: { message: "boom", url: "https://school.example/courses/1" } }, format: :json

        expect(ErrorReport.order(:id).last.url).to eq("https://school.example/courses/1")
      end

      it "ignores a caller-supplied url with an unsafe scheme" do
        post "create", params: { error: { message: "boom", url: "javascript:alert(1)" } }, format: :json

        expect(ErrorReport.order(:id).last.url).to be_nil
      end

      it "stores caller-supplied http_env metadata" do
        post "create", params: { error: { message: "boom", http_env: { "device" => "test-phone" } } }, format: :json

        expect(ErrorReport.order(:id).last.http_env).to include("device" => "test-phone")
      end

      it "stores serialized caller-supplied http_env metadata" do
        post "create", params: { error: { message: "boom", http_env: { "device" => "test-phone" }.to_json } }, format: :json

        expect(ErrorReport.order(:id).last.http_env).to include("device" => "test-phone")
      end
    end

    it "infers user_roles" do
      student_in_course(active_all: true)
      user_session(@student)
      post "create", params: { error: { user_roles: "admin", message: "it broke :(" } }
      assert_recorded_error
      expect(ErrorReport.order(:id).last.data["user_roles"]).to eq("user,student")
    end

    context "caller-supplied user roles" do
      it "ignores array roles for an unauthenticated report" do
        post :create,
             params: {
               error: {
                 subject: "test error",
                 user_roles: ["student", "teacher"]
               }
             },
             format: :json

        created_report = ErrorReport.take
        expect(created_report.data["user_roles"]).to be_nil
      end

      it "ignores hash roles for an unauthenticated report" do
        post :create,
             params: {
               error: {
                 subject: "test error",
                 user_roles: { "primary" => "student", "secondary" => "admin" }
               }
             },
             format: :json

        created_report = ErrorReport.take
        expect(created_report.data["user_roles"]).to be_nil
      end
    end

    it "records the real user if they are in student view" do
      authenticate_user!
      svs = course_factory.student_view_student
      session[:become_user_id] = svs.id
      post "create", params: { error: { message: "test message" } }
      expect(ErrorReport.order(:id).last.user_id).to eq @user.id
    end

    it "records the masqueradee user if not in student view" do
      other_user = user_with_pseudonym(name: "other", active_all: true)
      authenticate_user! # reassigns @user
      session[:become_user_id] = other_user.id
      post "create", params: { eerror: { message: "test message" } }
      expect(ErrorReport.order(:id).last.user_id).to eq other_user.id
    end

    it "doesn't create a report if we're out of region" do
      expect(Shard.current).to receive(:in_current_region?).and_return(false)
      expect do
        post "create", params: { error: { id: "garbage" } }
      end.not_to change { ErrorReport.count }
    end

    it "400s if we're out of region" do
      expect(Shard.current).to receive(:in_current_region?).and_return(false)
      post "create", params: { error: { id: "garbage" } }
      expect(response).to be_bad_request
    end

    it "400s if username is sent" do
      post "create", params: { error: { username: "causes_error" } }
      expect(response).to be_bad_request
    end

    describe "captcha validation" do
      before do
        allow(subject).to receive(:captcha_server_key).and_return("test_key")
      end

      it "skips validation if captcha key is not configured" do
        allow(subject).to receive(:captcha_server_key).and_return(nil)
        post "create", params: { error: { message: "test" } }
        assert_recorded_error
      end

      it "skips validation for authenticated users" do
        user_session(user_factory)
        post "create", params: { error: { message: "test" } }
        assert_recorded_error
      end

      it "validates captcha for unauthenticated users" do
        response_double = instance_double(Net::HTTPResponse, code: "200", body: { success: true, hostname: "test.host" }.to_json)
        allow(CanvasHttp).to receive(:post).and_return(response_double)

        post "create", params: { :error => { message: "test" }, "g-recaptcha-response" => "valid_response" }
        assert_recorded_error
      end

      it "returns error on captcha validation failure" do
        response_double = instance_double(Net::HTTPResponse, code: "200", body: { success: false, "error-codes": ["invalid-input"] }.to_json)
        allow(CanvasHttp).to receive(:post).and_return(response_double)

        post "create", params: { :error => { message: "test" }, "g-recaptcha-response" => "invalid_response" }, format: :json
        expect(response).to be_bad_request
        expect(response.parsed_body["errors"]).to eq(["invalid-input"])
      end

      it "returns error on hostname mismatch" do
        response_double = instance_double(Net::HTTPResponse, code: "200", body: { success: true, hostname: "wrong.host" }.to_json)
        allow(CanvasHttp).to receive(:post).and_return(response_double)

        post "create", params: { :error => { message: "test" }, "g-recaptcha-response" => "valid_response" }, format: :json
        expect(response).to be_bad_request
        expect(response.parsed_body["errors"]).to eq(["invalid-hostname"])
      end

      it "raises error if captcha service is unavailable" do
        response_double = instance_double(Net::HTTPResponse, code: "500")
        allow(CanvasHttp).to receive(:post).and_return(response_double)
        post "create", params: { :error => { message: "test" }, "g-recaptcha-response" => "valid_response" }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end
end
