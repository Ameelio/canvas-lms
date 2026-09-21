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

# Contains routes that should fallback to the main app.
module Kratos
  module FallbackRoutesConcern
    extend ActiveSupport::Concern

    included do
      delegate :dashboard_url,
               :login_path,
               :login_url,
               :root_path,
               :root_url,
               :otp_login_url,
               :otp_login_path,
               :course_url,
               :registration_confirmation_path,
               to: :main_app

      helper_method :dashboard_url
    end
  end
end
