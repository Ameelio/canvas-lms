# frozen_string_literal: true

#
# Copyright (C) 2024 - present Instructure, Inc.
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

class VideoCaptionService < ApplicationService
  def initialize(media_object, skip_polling: false)
    super()

    @skip_polling = skip_polling # for testing purposes
    @media_object = media_object
    @type = media_object.media_type
    @title = media_object.title
    @media_id = media_object.media_id
  end

  def call
    update_status(:processing)
    return update_status(:failed_initial_validation) unless pass_initial_checks

    # send to Notorious so it can process the media; grab and use the media_id from the handoff response
    @media_id = handoff_video_for_processing
    return update_status(:failed_handoff) unless @media_id

    @media_object.update_attribute(:auto_caption_media_id, @media_id)
    if @skip_polling
      # tell Notorious to start generating captions -- must be complete with handoff first
      request_caption_response = request_caption
      return update_status(:failed_request) unless (200..299).cover?(request_caption_response.code)

      process_captions_ready
    else
      delay.poll_if_we_can_request_captions_yet
    end
  end

  private

  def pass_initial_checks
    return false unless config["app-host"].present?
    return false unless auth_token.present?
    return false unless @type&.include?("video")
    return false unless @media_id
    return false if @media_object.media_tracks.where(kind: "subtitles").exists?
    return false if url.nil?

    true
  end

  def save_media_track(content, srclang)
    if content.present?
      @media_object.media_tracks.first_or_create(user: @media_object.user, locale: srclang, kind: "subtitles", content:)
      update_status(:complete)
    else
      update_status(:failed_to_pull)
    end
  end

  def handoff_video_for_processing
    response = request_handoff
    response&.dig("media", "id")
  end
  alias_method :handoff, :handoff_video_for_processing

  def grab_captions(srclang)
    response = collect_captions(srclang)
    if (200..299).cover?(response.code)
      return response.body
    end

    nil
  end

  def url
    @url ||= grab_url_from_media_sources
  end

  def grab_url_from_media_sources
    media_sources = @media_object.reload.media_sources
    media_source = media_sources.min_by { |ms| ms[:bitrate]&.to_i }
    media_source&.fetch(:url, nil)
  end

  def handoff_url
    "#{notorious_host}/api/media"
  end

  def caption_request_url
    "#{notorious_host}/api/media/#{@media_id}/captions"
  end

  def media_url
    "#{notorious_host}/api/media/#{@media_id}"
  end

  def caption_collect_url(srclang)
    "#{notorious_host}/api/media/#{@media_id}/captions/#{srclang}"
  end

  def notorious_host
    config["app-host"]
  end

  def auth_token
    Rails.application.credentials.send(:"notorious-admin")&.[](:client_authentication_key)
  end

  def request_headers
    { "Authorization" => auth_token }
  end

  def request_handoff
    HTTParty.post(handoff_url, body: { url:, name: @title }, headers: request_headers)
  end

  def request_caption
    HTTParty.post(caption_request_url, headers: request_headers)
  end

  def media
    HTTParty.get(media_url, headers: request_headers)
  end

  def collect_captions(srclang)
    HTTParty.get(caption_collect_url(srclang), headers: request_headers)
  end

  def config
    @config ||= DynamicSettings.find("notorious-admin", tree: :private) || {}
  end

  def update_status(status)
    @media_object.update_attribute(:auto_caption_status, status)
  end

  def process_captions_ready
    response = media
    srclang = response.dig("media", "captions", 0, "language")
    if srclang && response.dig("media", "captions", 0, "status") == "succeeded"
      save_media_track(grab_captions(srclang), srclang)
    else
      update_status(:failed_captions)
    end
  end

  def poll_if_we_can_request_captions_yet(attempts = 1)
    response = media
    response_succeeded = response.dig("media", "status") == "succeeded"

    if response_succeeded
      delay.request_to_start_caption_generation
    elsif attempts < 10
      delay(run_at: reschedule_time(attempts)).poll_if_we_can_request_captions_yet(attempts + 1)
    else
      update_status(:failed_request)
    end
  end

  def request_to_start_caption_generation(attempts = 1)
    # no need to actually poll here since we have a 'succeeded' video status, but it doesn't hurt
    response = request_caption
    if (200..299).cover?(response.code)
      delay.check_if_captions_are_ready
    elsif attempts < 10
      delay(run_at: reschedule_time(attempts)).request_to_start_caption_generation(attempts + 1)
    else
      update_status(:failed_request)
    end
  end
  alias_method :poll_caption_request, :request_to_start_caption_generation

  def check_if_captions_are_ready(attempts = 1)
    response = media
    response_succeeded = response.dig("media", "captions", 0, "status") == "succeeded"
    srclang = response.dig("media", "captions", 0, "language")

    if response_succeeded && srclang
      save_media_track(grab_captions(srclang), srclang)
    elsif attempts < 10
      delay(run_at: reschedule_time(attempts)).check_if_captions_are_ready(attempts + 1)
    else
      update_status(:failed_captions)
    end
  end
  alias_method :poll_captions_ready, :check_if_captions_are_ready

  def reschedule_time(attempt)
    # This mimics the exponential backoff algorithm used by inst jobs
    (5 + (attempt**4)).seconds.from_now
  end
end
