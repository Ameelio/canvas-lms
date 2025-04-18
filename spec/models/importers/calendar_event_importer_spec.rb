# frozen_string_literal: true

#
# Copyright (C) 2014 - present Instructure, Inc.
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

require_relative "../../import_helper"

describe Importers::CalendarEventImporter do
  let_once(:migration_course) { course_factory(active_all: true) }

  let(:migration) { migration_course.content_migrations.create! }

  let(:migration_assignment) do
    assignment = migration_course.assignments.build(title: "migration assignment")
    assignment.workflow_state = "active"
    assignment.migration_id = 42
    assignment.save!
    assignment
  end

  let(:migration_quiz) do
    assignment_quiz([], course: migration_course)
    @quiz.migration_id = 42
    @quiz.save!
    @quiz
  end

  let(:migration_attachment) do
    attachment_with_context(migration_course)
    @attachment.migration_id = 42
    @attachment.save!
    @attachment
  end

  let(:migration_topic) do
    topic = migration_course.discussion_topics.build(title: "migration topic")
    topic.workflow_state = "active"
    topic.migration_id = 42
    topic.save!
    topic
  end

  def attachment_suffix(type, value)
    Importers::CalendarEventImporter.import_migration_attachment_suffix(
      {
        attachment_type: type,
        attachment_value: value,
      },
      migration_course
    )
  end

  def check_paragraph_link(s, type = nil)
    md = s.match(/^<p><a href=['"]([^'"]*)['"]/)
    expect(md).not_to be_nil
    expect(md[1]).to match %r{courses/\d+/#{type}/\d+} if type
  end

  describe ".process_migration" do
    it "keeps calendar series relations and rules" do
      uuid = "8233ffdc-9067-4eaf-a726-19c3718dab29"
      rrule = "FREQ=DAILY;INTERVAL=1;UNTIL=20241001T055959Z"
      data = { "calendar_events" => [
        { "migration_id" => "whatvs1", "series_uuid" => uuid, "series_head" => true, "rrule" => rrule, "blackout_date" => false },
        { "migration_id" => "whatvs2", "series_uuid" => uuid, "series_head" => nil, "rrule" => rrule, "blackout_date" => false },
        { "migration_id" => "whatvs3", "series_uuid" => uuid, "series_head" => nil, "rrule" => rrule, "blackout_date" => false }
      ] }
      Importers::CalendarEventImporter.process_migration(data, migration)
      imported_events = migration_course.calendar_events
      expect(imported_events.count).to eq 3
      expect(imported_events.where.not(series_uuid: nil).where(rrule:, series_head: true).count).to eq 1
      expect(imported_events.where.not(series_uuid: nil).where(rrule:, series_head: nil).count).to eq 2
      expect(imported_events.pluck(:series_uuid)).not_to include(uuid)
    end

    it "migrate blackout days for course pace" do
      data = { "calendar_events" => [
        { "migration_id" => "whatvs1", "blackout_date" => true },
        { "migration_id" => "whatvs2", "blackout_date" => false },
        { "migration_id" => "whatvs3", "blackout_date" => true }
      ] }
      Importers::CalendarEventImporter.process_migration(data, migration)
      imported_events = migration_course.calendar_events
      expect(imported_events.count).to eq 3
      expect(imported_events.where(blackout_date: true).count).to eq 2
      expect(imported_events.where(blackout_date: false).count).to eq 1
    end
  end

  describe ".import_from_migration" do
    it "initializes a calendar event based on hash data" do
      event = migration_course.calendar_events.build
      hash = {
        migration_id: "42",
        title: "event title",
        description: "the event description",
        start_at: Time.zone.now,
        end_at: 2.hours.from_now,
        attachment_type: "external_url",
        attachment_value: "http://example.com",
        blackout_date: true
      }
      Importers::CalendarEventImporter.import_from_migration(hash, migration_course, migration, event)
      expect(event).not_to be_new_record
      expect(event.imported).to be_truthy
      expect(event.migration_id).to eq "42"
      expect(event.title).to eq "event title"
      expect(event.description).to match("the event description")
      expect(event.description).to match("example.com")
      expect(event.blackout_date).to be_truthy
    end
  end

  describe ".import_migration_attachment_suffix" do
    it "handles external_url" do
      result = attachment_suffix("external_url", "http://example.com")
      expect(result).to include "http://example.com"
      check_paragraph_link(result)
    end

    it "handles assignments" do
      result = attachment_suffix("assignment", migration_assignment.migration_id.to_s)
      expect(result).to include migration_assignment.id.to_s
      check_paragraph_link(result, "assignments")
    end

    it "handles assessments" do
      result = attachment_suffix("assessment", migration_quiz.migration_id.to_s)
      expect(result).to include migration_quiz.id.to_s
      check_paragraph_link(result, "quizzes")
    end

    it "handles files" do
      result = attachment_suffix("file", migration_attachment.migration_id.to_s)
      expect(result).to include migration_attachment.id.to_s
      check_paragraph_link(result)
      # Attachment doesn't follow the typical url pattern
      expect(result).to include "/files/#{migration_attachment.id}/download"
    end

    it "handles web_links" do
      expect(migration_course).to receive(:external_url_hash).and_return("value" => { "url" => "http://example.com", "name" => "example link" })
      result = attachment_suffix("web_link", "value")
      expect(result).to include "example link"
      expect(result).to include "http://example.com"
      check_paragraph_link(result)
    end

    it "handles discussion topics" do
      result = attachment_suffix("topic", migration_topic.migration_id.to_s)
      expect(result).to include migration_topic.id.to_s
      check_paragraph_link(result, "discussion_topics")
    end

    it "returns empty string on unrecognized types" do
      result = attachment_suffix("invalid", "42")
      expect(result).to be_empty
    end
  end

  SYSTEMS.each do |system|
    next unless import_data_exists? system, "calendar_event"

    it "imports calendar events for #{system}" do
      data = get_import_data(system, "calendar_event")
      context = get_import_context(system)
      migration = context.content_migrations.create!

      data[:events_to_import] = {}
      expect(Importers::CalendarEventImporter.import_from_migration(data, context, migration)).to be_nil
      expect(context.calendar_events.count).to eq 0

      data[:events_to_import][data[:migration_id]] = true
      Importers::CalendarEventImporter.import_from_migration(data, context, migration)
      Importers::CalendarEventImporter.import_from_migration(data, context, migration)
      expect(context.calendar_events.count).to eq 1

      event = CalendarEvent.where(migration_id: data[:migration_id]).first
      expect(event.title).to eq data[:title]
      expect(event.description.gsub("&#x27;", "'").index(data[:description])).not_to be_nil
    end
  end
end
