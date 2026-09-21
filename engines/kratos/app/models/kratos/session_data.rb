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
  SessionData = Struct.new(:active, :identity, :metadata, :unique_id, keyword_init: true) do
    def self.from_json(payload)
      h = ::JSON.parse(payload.to_s) || {}

      unique_id = h.dig("traits", "email") || h["id"]

      metadata = h.slice("metadata_admin", "metadata_public", "traits")

      new(
        active: h["active"],
        identity: h["identity"],
        metadata:,
        unique_id:
      )
    end

    def valid?
      active == true
    end
  end
end
