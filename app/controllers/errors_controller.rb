# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
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

# @API Error Reports
#
# @model ErrorReport
#   {
#     "id": "ErrorReport",
#     "description": "A collection of information around a specific notification of a problem",
#     "properties": {
#       "subject": {
#         "description": "The users problem summary, like an email subject line",
#         "type": "string",
#         "example": "File upload breaking"
#       },
#       "comments": {
#         "description": "long form documentation of what was witnessed",
#         "type": "string",
#         "example": "When I went to upload a .mov file to my files page, I got an error.  Retrying didn't help, other file types seem ok"
#       },
#       "user_perceived_severity": {
#         "description": "categorization of how bad the user thinks the problem is.  Should be one of [just_a_comment, not_urgent, workaround_possible, blocks_what_i_need_to_do, extreme_critical_emergency].",
#         "type": "string",
#         "example": "just_a_comment"
#       },
#       "email": {
#         "description": "the email address of the reporting user",
#         "type": "string",
#         "example": "name@example.com"
#       },
#       "url": {
#         "description": "URL of the page on which the error was reported",
#         "type": "string",
#         "example": "https://canvas.instructure.com/courses/1"
#       },
#       "context_asset_string": {
#         "description": "string describing the asset being interacted with at the time of error.  Formatted '[type]_[id]'",
#         "type": "string",
#         "example": "user_1"
#       },
#       "user_roles": {
#         "description": "comma seperated list of roles the reporting user holds.  Can be one [student], or many [teacher,admin]",
#         "type": "string",
#         "example": "user,teacher,admin"
#       }
#     }
#   }
#
class ErrorsController < ApplicationController
  include CaptchaValidation

  PER_PAGE = 20
  PUBLIC_ERROR_FIELDS = %i[
    backtrace
    category
    comments
    email
    exception_message
    message
    subject
    user_perceived_severity
  ].freeze

  before_action :require_view_error_reports, except: [:create]
  before_action :validate_captcha!, only: [:create]
  skip_before_action :verify_authenticity_token, only: [:create]
  skip_before_action :require_user, only: :create

  def require_view_error_reports
    require_site_admin_with_permission(:view_error_reports)
  end

  def index
    params[:page] = (params[:page].to_i > 0) ? params[:page].to_i : 1
    @reports = ErrorReport.preload(:user, :account)

    @message = params[:message]
    if error_search_enabled? && @message.present?
      @reports = @reports.where("message LIKE ?", "%" + @message + "%")
    elsif params[:category].blank?
      @reports = @reports.where("category<>'404'")
    end
    if params[:category].present?
      @reports = @reports.where(category: params[:category])
    end

    @reports = @reports.order(created_at: :desc).paginate(per_page: PER_PAGE, page: params[:page], total_entries: nil)
  end

  def show
    @reports = [ErrorReport.find(params[:id])]
    render :index
  end

  # @API Create Error Report
  #
  # Create a new error report documenting an experienced problem
  #
  # Performs the same action as when a user uses the "help -> report a problem"
  # dialog.
  #
  # @argument error[subject] [Required, String]
  #   The summary of the problem
  #
  # @argument error[email] [Optional, String]
  #   Email address for the reporting user
  #
  # @argument error[comments] [Optional, String]
  #   The long version of the story from the user one what they experienced
  #
  # @argument error[url] [Optional, String]
  #   The URL of the page where the problem occurred. Honored only for API
  #   requests, and only when it is a valid http(s) URL; otherwise Canvas
  #   derives the URL from the request.
  #
  # @argument error[http_env] [Optional, SerializedHash]
  #   A collection of metadata about the client's environment (for example, a
  #   mobile app's device details). Honored only for API requests; for browser
  #   requests Canvas collects it from the request itself.
  #
  # The user identity, account, roles, user agent, and request context are
  # always derived by Canvas and cannot be supplied by the caller.
  #
  # @example_request
  #   # Create error report
  #   curl 'https://<canvas>/api/v1/error_reports' \
  #         -X POST \
  #         -F 'error[subject]="things are broken"' \
  #         -F 'error[comments]="All my thoughts on what I saw"' \
  #         -H 'Authorization: Bearer <token>'
  def create
    # this action can be called by an unauthenticated user.  To prevent
    # abuse, we're representing this as an expensive operation so it would
    # get quickly rate limited if hit repeatedly.
    increment_request_cost(200)

    reporter = @current_user.try(:fake_student?) ? @real_current_user : @current_user

    # this is a honeypot field to catch spambots. it's hidden via css and should always be empty.
    return head(:bad_request) if error_params[:username].present?

    unless Shard.current.in_current_region?
      logger.debug("Out of region error report received")
      return head(:bad_request)
    end

    error = public_error_params
    begin
      report = session_error_report(reporter, error_params[:id])
      report ||= ErrorReport.new
      error.delete(:category) if report.category.present?
      submitted_backtrace = error.delete(:backtrace).to_s
      existing_backtrace = report.backtrace
      report.assign_data(error)
      report.backtrace = [submitted_backtrace, existing_backtrace].compact_blank.join("\n\n-----------------------------------------\n\n")

      # These values cross into support systems and are server-derived; API
      # callers may supply only a validated page URL and client metadata.
      report.user = reporter
      report.account = @domain_root_account
      report.url ||= client_reported_url || clean_return_to(request.referer)
      report.user_agent = request.headers["User-Agent"]
      report.http_env ||= client_http_env || Canvas::Errors::Info.useful_http_env_stuff_from_request(request)
      report.request_context_id = RequestContext::Generator.request_id
      report.data["user_roles"] = reporter.roles(@domain_root_account).join(",") if reporter
      report.save!
      report.delay.send_to_external
    rescue => e
      @exception = e
      Canvas::Errors.capture(
        e,
        message: "Error Report Creation failed",
        user_email: error[:email],
        user_id: reporter.try(:id)
      )
    end
    respond_to do |format|
      format.html do
        flash[:notice] = t("notices.error_reported", "Thanks for your help!  We'll get right on this")
        redirect_to root_url
      end
      format.json { render json: { logged: true, id: report.try(:id) } }
    end
  end

  def error_search_enabled?
    Setting.get("error_search_enabled", "true") == "true"
  end
  helper_method :error_search_enabled?

  private

  # params[:error] may legitimately arrive as a scalar or array from junk
  # clients; treat anything but a params hash as absent.
  def error_params
    @error_params ||= params[:error].is_a?(ActionController::Parameters) ? params[:error] : ActionController::Parameters.new
  end

  def public_error_params
    error_params.permit(*PUBLIC_ERROR_FIELDS).to_h.symbolize_keys
  end

  # The session, not the caller, selects which report may be enriched: the id
  # must be the one render_rescue_action stored for this session. A matching
  # error[id] (posted by the 500-page form) may keep enriching the same report
  # across resubmissions; an id-less submission consumes the session key once.
  def session_error_report(reporter, requested_id)
    session_report_id = session[:last_error_id]
    return if session_report_id.blank?

    if requested_id.present?
      return unless requested_id.to_s == session_report_id.to_s
    else
      session.delete(:last_error_id)
    end

    report = ErrorReport.where(id: session_report_id, created_at: 1.hour.ago..).first
    report if report && session_report_owner?(report, reporter)
  end

  # The auto-created report may be attributed to the fake student (Student
  # View), a cross-shard id, or no user at all (pre-auth errors).
  def session_report_owner?(report, reporter)
    return true if report.user_id.nil?

    [reporter, @current_user, @real_current_user].compact.uniq.any? do |user|
      [user.id, user.global_id].include?(report.user_id)
    end
  end

  def client_reported_url
    return unless api_request?

    url = error_params[:url]
    return unless url.is_a?(String) && url.present?

    uri = URI.parse(url)
    uri.to_s if %w[http https].include?(uri.scheme)
  rescue URI::Error
    nil
  end

  def client_http_env
    return unless api_request?

    env = error_params[:http_env]
    case env
    when ActionController::Parameters
      env.to_unsafe_h
    when String
      parse_client_http_env(env)
    end
  end

  def parse_client_http_env(env)
    parsed = JSON.parse(env)
    parsed.is_a?(Hash) ? parsed : nil
  rescue JSON::ParserError
    nil
  end
end
