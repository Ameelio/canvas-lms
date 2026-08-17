# frozen_string_literal: true

#
# Copyright (C) 2026 - present Instructure, Inc.
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

# Shares the write-time and legacy-read sanitization pattern between the block
# editor models.
module BlockEditorContentSanitization
  extend ActiveSupport::Concern

  class_methods do
    # Sanitizes +attribute+ before validation when it is changing, and lazily
    # cleans legacy values the first time they are read. The sanitized value is
    # written back to the attribute so reads are not repeatedly re-sanitized
    # and in-place mutations stay dirty-tracked.
    def sanitizes_block_editor_content(attribute)
      attr_name = attribute.to_s

      before_validation do
        if will_save_change_to_attribute?(attr_name)
          self[attr_name] = BlockEditorContentSanitizer.sanitize(self[attr_name])
          sanitized_block_editor_reads << attr_name
        end
      end

      define_method(attribute) do
        read_sanitized_block_editor_content(attr_name)
      end

      define_method(:"#{attr_name}=") do |value|
        sanitized_block_editor_reads.delete(attr_name)
        super(value)
      end
    end
  end

  def reload(*)
    sanitized_block_editor_reads.clear
    super
  end

  private

  def sanitized_block_editor_reads
    @sanitized_block_editor_reads ||= Set.new
  end

  def read_sanitized_block_editor_content(attr_name)
    unless sanitized_block_editor_reads.include?(attr_name)
      raw = self[attr_name]
      sanitized = BlockEditorContentSanitizer.sanitize(raw)
      self[attr_name] = sanitized unless sanitized == raw
      sanitized_block_editor_reads << attr_name
    end
    self[attr_name]
  end
end
