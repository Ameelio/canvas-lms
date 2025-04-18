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

class Checkpoints::GroupOverrideUpdaterService < ApplicationService
  require_relative "discussion_checkpoint_error"
  include Checkpoints::DateOverrider
  include Checkpoints::GroupOverrideCommon

  def initialize(checkpoint:, override:)
    super()
    @checkpoint = checkpoint
    @override = override
  end

  def call
    is_differentiation_tag_override = differentiation_tag_override?(@override, @checkpoint)
    if @checkpoint.effective_group_category_id.nil? && !is_differentiation_tag_override
      raise Checkpoints::GroupAssignmentRequiredError, "must be a group assignment in order to create group overrides"
    end

    override = @checkpoint.assignment_overrides.find_by(id: @override[:id], set_type: AssignmentOverride::SET_TYPE_GROUP)
    raise Checkpoints::OverrideNotFoundError unless override

    group_id = @override.fetch(:set_id, nil) || override.set_id

    raise Checkpoints::SetIdRequiredError, "set_id is required, but was not provided" if group_id.blank?

    group = is_differentiation_tag_override ? get_differentiation_tag_from_override(@override, @checkpoint) : get_group_from_override(@override, @checkpoint)

    current_group = override.set

    update_override(override:, group:)

    parent_override = @checkpoint.parent_assignment.active_assignment_overrides.find_by(set: current_group)
    raise Checkpoints::OverrideNotFoundError unless parent_override

    update_override(override: parent_override, group:, shell_override: true)

    override
  end

  private

  def update_override(override:, group:, shell_override: false)
    override.set = group if group.id != override.set_id
    apply_overridden_dates(override, @override, shell_override:)
    override.save!
    override
  end
end
