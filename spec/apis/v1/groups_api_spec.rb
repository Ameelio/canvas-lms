# frozen_string_literal: true

#
# Copyright (C) 2012 - 2014 Instructure, Inc.
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

require_relative "../api_spec_helper"
require_relative "../file_uploads_spec_helper"

describe "Groups API", type: :request do
  def group_json(group, opts = {})
    opts[:is_admin] ||= false
    opts[:include_users] ||= false
    opts[:include_category] ||= false
    opts[:include_permissions] ||= false
    json = {
      "id" => group.id,
      "name" => group.name,
      "description" => group.description,
      "is_public" => group.is_public,
      "join_level" => group.join_level,
      "members_count" => group.members_count,
      "max_membership" => group.max_membership,
      "avatar_url" => group.avatar_attachment && "http://www.example.com/images/thumbnails/#{group.avatar_attachment.id}/#{group.avatar_attachment.uuid}",
      "context_name" => group.context.name,
      "context_type" => group.context_type,
      "#{group.context_type.downcase}_id" => group.context_id,
      "role" => group.group_category.role,
      "group_category_id" => group.group_category_id,
      "storage_quota_mb" => group.storage_quota_mb,
      "leader" => group.leader,
      "has_submission" => group.submission?,
      "concluded" => group.context.concluded? || group.context.deleted?,
      "created_at" => group.created_at.iso8601,
      "non_collaborative" => false
    }
    if opts[:include_users]
      json["users"] = users_json(group.users, **opts)
    end
    if opts[:include_permissions]
      json["permissions"] = {
        "join" => group.grants_right?(@user, nil, :join),
        "create_discussion_topic" => DiscussionTopic.context_allows_user_to_create?(group, @user, nil),
        "create_announcement" => Announcement.context_allows_user_to_create?(group, @user, nil)
      }
    end
    if opts[:include_category]
      json["group_category"] = group_category_json(group.group_category, @user)
    end
    if group.context_type == "Account" && opts[:is_admin]
      json["sis_import_id"] = group.sis_batch_id
      json["sis_group_id"] = group.sis_source_id
    end
    json
  end

  def group_category_json(group_category, user)
    json = {
      "auto_leader" => group_category.auto_leader,
      "group_limit" => group_category.group_limit,
      "id" => group_category.id,
      "name" => group_category.name,
      "role" => group_category.role,
      "self_signup" => group_category.self_signup,
      "self_signup_end_at" => group_category.self_signup_end_at,
      "context_type" => group_category.context_type,
      "#{group_category.context_type.underscore}_id" => group_category.context_id,
      "protected" => group_category.protected?,
      "allows_multiple_memberships" => group_category.allows_multiple_memberships?,
      "is_member" => group_category.is_member?(user),
      "created_at" => group_category.created_at.iso8601
    }
    json["sis_group_category_id"] = group_category.sis_source_id if group_category.context.grants_any_right?(user, :read_sis, :manage_sis)
    json["sis_import_id"] = group_category.sis_batch_id if group_category.context.grants_right?(user, :manage_sis)
    json
  end

  def users_json(users, **)
    users.map { |user| user_json(user, **) }
  end

  def user_json(user, **)
    {
      "id" => user.id,
      "created_at" => user.created_at.iso8601,
      "name" => user.name,
      "sortable_name" => user.sortable_name,
      "short_name" => user.short_name
    }
  end

  def membership_json(membership, is_admin = false)
    json = {
      "id" => membership.id,
      "group_id" => membership.group_id,
      "user_id" => membership.user_id,
      "workflow_state" => membership.workflow_state,
      "moderator" => membership.moderator,
      "created_at" => membership.created_at.iso8601
    }
    json["sis_import_id"] = membership.sis_batch_id if membership.group.context_type == "Account" && is_admin
    json["sis_group_id"] = membership.group.sis_source_id if membership.group.context_type == "Account" && is_admin
    json
  end

  before :once do
    @moderator = user_model
    @member = user_with_pseudonym

    @communities = GroupCategory.communities_for(Account.default)
    @community = group_model(name: "Algebra Teachers", group_category: @communities, context: Account.default)
    @community.add_user(@member, "accepted", false)
    @community.add_user(@moderator, "accepted", true)
    @community_path = "/api/v1/groups/#{@community.id}"
    @category_path_options = { controller: "groups", format: "json" }
    @context = @community
  end

  it "allows listing all a user's groups" do
    course_with_student(user: @member)
    @group = @course.groups.create!(name: "My Group")
    @group.add_user(@member, "accepted", true)

    @user = @member
    json = api_call(:get, "/api/v1/users/self/groups", @category_path_options.merge(action: "index"))
    expect(json).to eq [group_json(@community), group_json(@group)]
    links = response.headers["Link"].split(",")
    expect(links.all? { |l| l.include?("api/v1/users/self/groups") }).to be_truthy
  end

  describe "show SIS fields based on manage_sis permissions" do
    before :once do
      course_with_student(user: @member)
      @group = @course.groups.create!(name: "My Group")
      @group.add_user(@member, "accepted", true)
      @group.reload
      account = @course.account
      @admin_user = User.create!
      account.account_users.create!(user: @admin_user, account:)
    end

    it "shows if the user has permission", priority: 3 do
      @user = @admin_user
      json = api_call(:get, "/api/v1/groups/#{@group.id}", @category_path_options.merge(action: "show", group_id: @group.id))
      expect(json).to have_key("sis_group_id")
      expect(json).to have_key("sis_import_id")
    end

    it "does not show if the user doesn't have permission", priority: 3 do
      @user = @member
      json = api_call(:get, "/api/v1/users/self/groups", @category_path_options.merge(action: "index"))
      expect(json[0]).not_to have_key("sis_group_id")
      expect(json[0]).not_to have_key("sis_import_id")
    end
  end

  it "indicates if the context is deleted" do
    course_with_student(user: @member)
    @group = @course.groups.create!(name: "My Group")
    @group.add_user(@member, "accepted", true)
    @course.destroy!
    @group.reload

    @user = @member
    json = api_call(:get, "/api/v1/users/self/groups", @category_path_options.merge(action: "index"))
    expect(json.detect { |g| g["id"] == @group.id }["concluded"]).to be_truthy
  end

  it "allows listing all a user's group in a given context_type" do
    @account = Account.default
    course_with_student(user: @member)
    @group = @course.groups.create!(name: "My Group")
    @group.add_user(@member, "accepted", true)

    @user = @member
    json = api_call(:get, "/api/v1/users/self/groups?context_type=Course", @category_path_options.merge(action: "index", context_type: "Course"))
    expect(json).to eq [group_json(@group)]

    json = api_call(:get, "/api/v1/users/self/groups?context_type=Account", @category_path_options.merge(action: "index", context_type: "Account"))
    expect(json).to eq [group_json(@community)]
  end

  it "allows listing all of a course's groups" do
    course_with_teacher(active_all: true)
    @group = @course.groups.create!(name: "New group")

    json = api_call(:get,
                    "/api/v1/courses/#{@course.to_param}/groups.json",
                    @category_path_options.merge(action: "context_index",
                                                 course_id: @course.to_param))
    expect(json.count).to eq 1
    expect(json.first["id"]).to eq @group.id
  end

  it "does not show inactive users to students" do
    course_with_teacher(active_all: true)
    @group = @course.groups.create!(name: "New group")

    inactive_user = user_factory
    enrollment = @course.enroll_student(inactive_user)
    enrollment.deactivate
    @group.add_user(inactive_user, "accepted")

    @course.enroll_student(user_factory).accept!
    @group.add_user(@user, "accepted")

    json = api_call(:get,
                    "/api/v1/courses/#{@course.to_param}/groups.json?include[]=users",
                    @category_path_options.merge(action: "context_index",
                                                 course_id: @course.to_param,
                                                 include: ["users"]))

    expect(json.first["users"].pluck("id")).to eq [@user.id]

    enrollment.reactivate

    json = api_call(:get,
                    "/api/v1/courses/#{@course.to_param}/groups.json?include[]=users",
                    @category_path_options.merge(action: "context_index",
                                                 course_id: @course.to_param,
                                                 include: ["users"]))

    expect(json.first["users"].pluck("id")).to match_array [@user.id, inactive_user.id]
  end

  it "shows inactive users to admins" do
    course_with_teacher(active_all: true)
    @group = @course.groups.create!(name: "New group")

    inactive_user = user_factory
    enrollment = @course.enroll_student(inactive_user)
    enrollment.deactivate
    @group.add_user(inactive_user, "accepted")

    @user = @teacher

    json = api_call(:get,
                    "/api/v1/courses/#{@course.to_param}/groups.json?include[]=users",
                    @category_path_options.merge(action: "context_index",
                                                 course_id: @course.to_param,
                                                 include: ["users"]))

    expect(json.first["users"].pluck("id")).to eq [inactive_user.id]
  end

  it "allows listing all of an account's groups for account admins" do
    @account = Account.default
    sis_batch = @account.sis_batches.create
    SisBatch.where(id: sis_batch).update_all(workflow_state: "imported")
    @community.sis_source_id = "sis"
    @community.sis_batch_id = sis_batch.id
    @community.save!
    account_admin_user(account: @account)

    json = api_call(:get,
                    "/api/v1/accounts/#{@account.to_param}/groups.json",
                    @category_path_options.merge(action: "context_index",
                                                 account_id: @account.to_param))
    expect(json.count).to eq 1
    expect(json.first).to eq group_json(@community, is_admin: true)

    expect(json.first["id"]).to eq @community.id
    expect(json.first["sis_group_id"]).to eq "sis"
    expect(json.first["sis_import_id"]).to eq sis_batch.id
  end

  it "does not allow non-admins to view an account's groups" do
    @account = Account.default
    raw_api_call(:get,
                 "/api/v1/accounts/#{@account.to_param}/groups.json",
                 @category_path_options.merge(action: "context_index",
                                              account_id: @account.to_param))
    expect(response).to have_http_status :forbidden
  end

  it "shows students all groups" do
    course_with_student(active_all: true)
    @group_1 = @course.groups.create!(name: "Group 1")
    @group_2 = @course.groups.create!(name: "Group 2")
    @group_1.add_user(@user, "accepted", false)

    json = api_call(:get,
                    "/api/v1/courses/#{@course.to_param}/groups.json",
                    @category_path_options.merge(action: "context_index",
                                                 course_id: @course.to_param))
    expect(json.count).to eq 2
    expect(json.first["id"]).to eq @group_1.id
  end

  context "sharding" do
    specs_require_sharding

    it "shows cross-shard all groups" do
      @shard1.activate do
        @account_1 = Account.create
        @student = user_with_pseudonym(active_all: true, account: @account_1)
      end

      @shard2.activate do
        @account_2 = Account.create
        course_with_teacher(active_all: true)
        @teacher_1 = @teacher
        @course_1 = @course
        @course_1.enroll_student(@student).accept!
        @group_1 = @course.groups.create!(name: "Group on shard2")
        @group_1.add_user(@student, "accepted", false)
      end

      json = api_call_as_user(@student,
                              :get,
                              "/api/v1/courses/#{@course_1.to_param}/groups.json",
                              @category_path_options.merge(action: "context_index",
                                                           course_id: @course_1.to_param,
                                                           only_own_groups: true))
      expect(json.count).to eq 1
      expect(json.first["id"]).to eq @group_1.id
    end
  end

  describe "filters groups" do
    before(:once) do
      course_with_student(active_all: true)
      @group_1 = @course.groups.create!(name: "Abras")
      @group_2 = @course.groups.create!(name: "Squirtles")
      @group_3 = @course.groups.create!(name: "Fabric")
      @group_4 = @course.groups.create!(name: "Labyrinth")
      @group_2.add_user(@user, "accepted", false)
      @group_4.add_user(@user, "accepted", false)
    end

    it "returns all groups when the filter is present but empty" do
      json = api_call(:get,
                      "/api/v1/courses/#{@course.to_param}/groups.json?filter=",
                      @category_path_options.merge(action: "context_index",
                                                   course_id: @course.to_param,
                                                   filter: ""))
      expect(json.count).to eq(4)
    end

    it "matches group names" do
      json = api_call(:get,
                      "/api/v1/courses/#{@course.to_param}/groups.json?filter=abr",
                      @category_path_options.merge(action: "context_index",
                                                   course_id: @course.to_param,
                                                   filter: "abr"))
      ids = json.pluck("id")
      expect(ids.count).to eq(2)
      expect(ids).to include(@group_1.id)
      expect(ids).to include(@group_3.id)
    end

    it "matches users' names in the group" do
      json = api_call(:get,
                      "/api/v1/courses/#{@course.to_param}/groups.json?filter=#{@user.name}",
                      @category_path_options.merge(action: "context_index",
                                                   course_id: @course.to_param,
                                                   filter: @user.name))
      ids = json.pluck("id")
      expect(ids.count).to eq(2)
      expect(ids).to include(@group_2.id)
      expect(ids).to include(@group_4.id)
    end
  end

  it "allows a member to retrieve the group" do
    @user = @member
    json = api_call(:get, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "show"))
    expect(json).to eq group_json(@community)
  end

  it "allows a member to retrieve a favorite group" do
    @user = @member
    json = api_call(:get,
                    "#{@community_path}.json?include[]=favorites",
                    @category_path_options.merge(group_id: @community.to_param,
                                                 action: "show",
                                                 include: ["favorites"]))
    expect(json).to have_key("is_favorite")
  end

  it "includes the group category" do
    @user = @member
    json = api_call(:get, "#{@community_path}.json?include[]=group_category", @category_path_options.merge(group_id: @community.to_param, action: "show", include: ["group_category"]))
    expect(json).to have_key("group_category")
  end

  it "includes permissions" do
    # Make sure it only returns permissions when asked
    json = api_call(:get, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "show", format: "json"))
    expect(json).not_to have_key("permissions")

    # When its asked to return permissions make sure they are there
    json = api_call(:get, "#{@community_path}.json?include[]=permissions", @category_path_options.merge(group_id: @community.to_param, action: "show", format: "json", include: ["permissions"]))
    expect(json).to have_key("permissions")
  end

  it "includes permission create_discussion_topic" do
    json = api_call(:get, "#{@community_path}.json?include[]=permissions", @category_path_options.merge(group_id: @community.to_param, action: "show", format: "json", include: ["permissions"]))

    expect(json).to have_key("permissions")
    expect(json["permissions"]).to have_key("create_discussion_topic")
  end

  it "includes permission create_student_announcements" do
    json = api_call(:get, "#{@community_path}.json?include[]=permissions", @category_path_options.merge(group_id: @community.to_param, action: "show", format: "json", include: ["permissions"]))

    expect(json).to have_key("permissions")
    expect(json["permissions"]).to have_key("create_announcement")
    expect(json["permissions"]["create_announcement"]).to be_truthy
  end

  it "includes tabs if requested" do
    json = api_call(:get, "#{@community_path}.json?include[]=tabs", @category_path_options.merge(group_id: @community.to_param, action: "show", format: "json", include: ["tabs"]))
    expect(json).to have_key "tabs"
    expect(json["tabs"].pluck("id")).to eq(%w[home announcements pages people discussions files])
  end

  it "allows searching by SIS ID" do
    @community.update_attribute(:sis_source_id, "abc")
    json = api_call(:get, "/api/v1/groups/sis_group_id:abc", @category_path_options.merge(group_id: "sis_group_id:abc", action: "show"))
    expect(json).to eq group_json(@community)
  end

  it "allows anyone to create a new community" do
    user_model
    json = api_call(:post, "/api/v1/groups", @category_path_options.merge(action: "create"), {
                      "name" => "History Teachers",
                      "description" => "Because history is awesome!",
                      "is_public" => false,
                      "join_level" => "parent_context_request",
                    })
    @community2 = Group.order(:id).last
    expect(@community2.group_category).to be_communities
    expect(json).to eq group_json(@community2, include_users: true, include_permissions: true, include_category: true)
  end

  it "allows a teacher to create a group in a course" do
    course_with_teacher(active_enrollment: true)
    @user = @teacher
    project_groups = @course.group_categories.build
    project_groups.name = "Course Project Groups"
    project_groups.save
    api_call(:post, "/api/v1/group_categories/#{project_groups.id}/groups", @category_path_options.merge(action: "create", group_category_id: project_groups.to_param))
    expect(project_groups.groups.active.count).to eq 1
  end

  it "does not allow a student to create a group in a course" do
    course_with_student
    @user = @student
    project_groups = @course.group_categories.build
    project_groups.name = "Course Project Groups"
    project_groups.save
    raw_api_call(:post, "/api/v1/group_categories/#{project_groups.id}/groups", @category_path_options.merge(action: "create", group_category_id: project_groups.to_param))
    expect(response).to have_http_status :forbidden
  end

  it "allows an admin to create a group in a account" do
    @account = Account.default
    account_admin_user(account: @account)
    project_groups = @account.group_categories.build
    project_groups.name = "test group category"
    project_groups.save
    api_call(:post, "/api/v1/group_categories/#{project_groups.id}/groups", @category_path_options.merge(action: "create", group_category_id: project_groups.to_param))
    expect(project_groups.groups.active.count).to eq 1
  end

  it "allows using group category sis id" do
    @account = Account.default
    account_admin_user(account: @account)
    project_groups = @account.group_categories.create(name: "gc1", sis_source_id: "gcsis1")
    api_call(:post,
             "/api/v1/group_categories/sis_group_category_id:gcsis1/groups",
             @category_path_options.merge(action: :create,
                                          group_category_id: "sis_group_category_id:gcsis1"))
    expect(project_groups.groups.active.count).to eq 1
  end

  it "allows setting sis id on group creation" do
    @account = Account.default
    account_admin_user(account: @account)
    @account.group_categories.create(name: "gc1", sis_source_id: "gcsis1")
    json = api_call(:post,
                    "/api/v1/group_categories/sis_group_category_id:gcsis1/groups",
                    @category_path_options.merge(action: :create,
                                                 group_category_id: "sis_group_category_id:gcsis1",
                                                 sis_group_id: "gsis1"))
    expect(json["sis_group_id"]).to eq "gsis1"
  end

  it "validates sis id uniqueness on group creation" do
    @account = Account.default
    account_admin_user(account: @account)
    project_groups = @account.group_categories.create(name: "gc1", sis_source_id: "gcsis1")
    project_groups.groups.create!(sis_source_id: "gsis1", context: @account)
    api_call(:post,
             "/api/v1/group_categories/sis_group_category_id:gcsis1/groups",
             @category_path_options.merge(action: :create,
                                          group_category_id: "sis_group_category_id:gcsis1",
                                          sis_group_id: "gsis1"),
             {},
             {},
             { expected_status: 400 })
  end

  it "does not allow a non-admin to create a group in a account" do
    @account = Account.default
    project_groups = @account.group_categories.build
    project_groups.name = "test group category"
    project_groups.save
    raw_api_call(:post, "/api/v1/group_categories/#{project_groups.id}/groups", @category_path_options.merge(action: "create", group_category_id: project_groups.to_param))
    expect(response).to have_http_status :forbidden
  end

  it "allows a moderator to edit a group" do
    avatar = attachment_model(uploaded_data: stub_png_data, content_type: "image/png", context: @community)
    @user = @moderator
    new_attrs = {
      "name" => "Algebra II Teachers",
      "description" => "Math rocks!",
      "is_public" => true,
      "join_level" => "parent_context_auto_join",
      "avatar_id" => avatar.id,
    }
    json = api_call(:put, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "update"), new_attrs)
    @community.reload
    expect(@community.name).to eq "Algebra II Teachers"
    expect(@community.description).to eq "Math rocks!"
    expect(@community.is_public).to be true
    expect(@community.join_level).to eq "parent_context_auto_join"
    expect(@community.avatar_attachment).to eq avatar
    expect(json).to eq group_json(@community, include_users: true, include_permissions: true, include_category: true)
  end

  it "only allows updating a group from private to public" do
    @user = @moderator
    new_attrs = {
      "is_public" => true,
    }
    api_call(:put, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "update"), new_attrs)
    @community.reload
    expect(@community.is_public).to be true

    new_attrs = {
      "is_public" => false,
    }
    api_call(:put, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "update"), new_attrs, {}, expected_status: 400)
    @community.reload
    expect(@community.is_public).to be true
  end

  it "does not allow a member to edit a group" do
    @user = @member
    new_attrs = {
      "name" => "Algebra II Teachers",
      "is_public" => true,
      "join_level" => "parent_context_auto_join",
    }
    api_call(:put, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "update"), new_attrs, {}, expected_status: 403)
  end

  it "allows a moderator to delete a group" do
    @user = @moderator
    api_call(:delete, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "destroy"))
    expect(@community.reload.workflow_state).to eq "deleted"
  end

  it "does not allow a member to delete a group" do
    @user = @member
    api_call(:delete, @community_path, @category_path_options.merge(group_id: @community.to_param, action: "destroy"), {}, {}, expected_status: 403)
  end

  describe "quota" do
    before :once do
      @account = Account.default
      Setting.set("group_default_quota", 11.decimal_megabytes)
    end

    context "with manage_storage_quotas permission" do
      before :once do
        account_admin_user account: @account
      end

      it "sets the quota on create" do
        json = api_call(:post,
                        "/api/v1/groups?name=TehGroup&storage_quota_mb=22",
                        { controller: "groups", action: "create", format: "json", name: "TehGroup", storage_quota_mb: "22" })
        group = @account.groups.find(json["id"])
        expect(group.storage_quota_mb).to eq 22
      end

      it "sets the quota on update" do
        group = @account.groups.create! name: "TehGroup"
        api_call(:put,
                 "/api/v1/groups/#{group.id}?storage_quota_mb=22",
                 { controller: "groups", action: "update", group_id: group.id.to_s, format: "json", storage_quota_mb: "22" })
        expect(group.reload.storage_quota_mb).to eq 22
      end
    end

    context "without manage_storage_quotas permission" do
      before :once do
        account_admin_user_with_role_changes(role_changes: { manage_storage_quotas: false })
      end

      it "ignores the quota on create" do
        json = api_call(:post,
                        "/api/v1/groups?storage_quota_mb=22",
                        { controller: "groups", action: "create", format: "json", storage_quota_mb: "22" })
        group = @account.groups.find(json["id"])
        expect(group.storage_quota_mb).to eq 11
      end

      it "ignores the quota on update" do
        group = @account.groups.create! name: "TehGroup"
        api_call(:put,
                 "/api/v1/groups/#{group.id}?storage_quota_mb=22&name=TheGruop",
                 { controller: "groups", action: "update", format: "json", group_id: group.id.to_s, name: "TheGruop", storage_quota_mb: "22" })
        group.reload
        expect(group.name).to eq "TheGruop"
        expect(group.storage_quota_mb).to eq 11
      end
    end
  end

  context "memberships" do
    before do
      @memberships_path = "#{@community_path}/memberships"
      @alternate_memberships_path = "#{@community_path}/users"
      @memberships_path_options = { controller: "group_memberships", format: "json" }
    end

    it "allows listing the group memberships" do
      @user = @moderator
      json = api_call(:get, @memberships_path, @memberships_path_options.merge(group_id: @community.to_param, action: "index"))
      expect(json.sort_by { |a| a["id"] }).to eq [membership_json(@community.has_member?(@member)), membership_json(@community.has_member?(@moderator))]
    end

    it "allows filtering to a certain membership state" do
      user_model
      @community.add_user(@user, "invited")
      @user = @moderator
      json = api_call(:get, @memberships_path, @memberships_path_options.merge(group_id: @community.to_param, action: "index"), {
                        filter_states: ["invited"]
                      })
      expect(json.count).to eq 1
      expect(json.first).to eq membership_json(@community.group_memberships.where(workflow_state: "invited").first)
    end

    context "with a membership" do
      before do
        @membership = @community.has_member?(@member)
        @membership_path_options = @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param)
        @alternate_membership_path_options = @memberships_path_options.merge(group_id: @community.to_param, user_id: @member.to_param)
      end

      it "allows a member to read their membership by membership id" do
        @user = @member
        json = api_call(:get, "#{@memberships_path}/#{@membership.id}", @membership_path_options.merge(action: :show))
        expect(json).to eq membership_json(@membership)
      end

      it "allows a moderator to read a membership by membership id" do
        @user = @moderator
        json = api_call(:get, "#{@memberships_path}/#{@membership.id}", @membership_path_options.merge(action: :show))
        expect(json).to eq membership_json(@membership)
      end

      it "does not allow an unrelated user to read a membership by membership id" do
        @user = user_model
        api_call(:get, "#{@memberships_path}/#{@membership.id}", @membership_path_options.merge(action: :show), {}, {}, expected_status: 403)
      end

      it "allows a member to read their membership by user id" do
        @user = @member
        json = api_call(:get, "#{@alternate_memberships_path}/#{@member.id}", @alternate_membership_path_options.merge(action: :show))
        expect(json).to eq membership_json(@membership)
      end

      it "allows a moderator to read a membership by user id" do
        @user = @moderator
        json = api_call(:get, "#{@alternate_memberships_path}/#{@member.id}", @alternate_membership_path_options.merge(action: :show))
        expect(json).to eq membership_json(@membership)
      end

      it "does not allow an unrelated user to read a membership by user id" do
        @user = user_model
        api_call(:get, "#{@alternate_memberships_path}/#{@member.id}", @alternate_membership_path_options.merge(action: :show), {}, {}, expected_status: 403)
      end
    end

    it "allows someone to request to join a group" do
      @user = user_model
      @community.join_level = "parent_context_request"
      @community.save!
      json = api_call(:post, @memberships_path, @memberships_path_options.merge(group_id: @community.to_param, action: "create"), {
                        user_id: @user.id
                      })
      @membership = GroupMembership.where(user_id: @user, group_id: @community).first
      expect(@membership.workflow_state).to eq "requested"
      expect(json).to eq membership_json(@membership).merge("just_created" => true)
    end

    it "allows someone to join a group" do
      @user = user_model
      @community.join_level = "parent_context_auto_join"
      @community.save!
      json = api_call(:post, @memberships_path, @memberships_path_options.merge(group_id: @community.to_param, action: "create"), {
                        user_id: @user.id
                      })
      @membership = GroupMembership.where(user_id: @user, group_id: @community).first
      expect(@membership.workflow_state).to eq "accepted"
      expect(json).to eq membership_json(@membership).merge("just_created" => true)
    end

    it "does not allow a moderator to add someone directly to the group" do
      @new_user = user_model
      @user = @moderator
      @community.join_level = "parent_context_auto_join"
      @community.save!
      api_call(:post,
               @memberships_path,
               @memberships_path_options.merge(group_id: @community.to_param, action: "create"),
               {
                 user_id: @new_user.id
               },
               {},
               expected_status: 403)
    end

    it "allows accepting a join request by a moderator" do
      @user = user_model
      @community.join_level = "parent_context_request"
      @community.save!
      @membership = @community.add_user(@user)
      @user = @moderator
      json = api_call(:put, "#{@memberships_path}/#{@membership.id}", @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"), {
                        workflow_state: "accepted"
                      })
      expect(@membership.reload).to be_active
      expect(json).to eq membership_json(@membership)
    end

    it "allows accepting a join request by a moderator using users/:user_id endpoint" do
      @user = user_model
      user_id = @user.id
      @community.join_level = "parent_context_request"
      @community.save!
      @membership = @community.add_user(@user)
      @user = @moderator
      json = api_call(:put, "#{@alternate_memberships_path}/#{user_id}", @memberships_path_options.merge(group_id: @community.to_param, user_id: user_id.to_param, action: "update"), {
                        workflow_state: "accepted"
                      })
      expect(@membership.reload).to be_active
      expect(json).to eq membership_json(@membership)
    end

    it "does not allow other workflow_state modifications" do
      @user = @moderator
      @membership = @community.group_memberships.where(user_id: @member).first
      api_call(:put, "#{@memberships_path}/#{@membership.id}", @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"), {
                 workflow_state: "requested"
               })
      expect(@membership.reload).to be_active

      api_call(:put, "#{@memberships_path}/#{@membership.id}", @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"), {
                 workflow_state: "invited"
               })
      expect(@membership.reload).to be_active

      api_call(:put, "#{@memberships_path}/#{@membership.id}", @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"), {
                 workflow_state: "deleted"
               })
      expect(@membership.reload).to be_active
    end

    it "does not allow other workflow_state modifications using users/:user_id endpoint" do
      @user = @moderator
      @membership = @community.group_memberships.where(user_id: @member).first
      api_call(:put, "#{@alternate_memberships_path}/#{@user.id}", @memberships_path_options.merge(group_id: @community.to_param, user_id: @user.to_param, action: "update"), {
                 workflow_state: "requested"
               })
      expect(@membership.reload).to be_active

      api_call(:put, "#{@alternate_memberships_path}/#{@user.id}", @memberships_path_options.merge(group_id: @community.to_param, user_id: @user.to_param, action: "update"), {
                 workflow_state: "invited"
               })
      expect(@membership.reload).to be_active

      api_call(:put, "#{@alternate_memberships_path}/#{@user.id}", @memberships_path_options.merge(group_id: @community.to_param, user_id: @user.to_param, action: "update"), {
                 workflow_state: "deleted"
               })
      expect(@membership.reload).to be_active
    end

    it "does not allow a member to accept join requests" do
      @user = user_model
      @community.join_level = "parent_context_request"
      @community.save!
      @membership = @community.add_user(@user)
      @user = @member
      api_call(:put,
               "#{@memberships_path}/#{@membership.id}",
               @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"),
               {
                 workflow_state: "accepted"
               },
               {},
               expected_status: 403)
      expect(@membership.reload).to be_requested
    end

    it "does not allow a member to accept join requests using users/:user_id endpoint" do
      @user = user_model
      @community.join_level = "parent_context_request"
      @community.save!
      @membership = @community.add_user(@user)
      @user = @member
      api_call(:put,
               "#{@alternate_memberships_path}/#{@user.id}",
               @memberships_path_options.merge(group_id: @community.to_param, user_id: @user.to_param, action: "update"),
               {
                 workflow_state: "accepted"
               },
               {},
               expected_status: 403)
      expect(@membership.reload).to be_requested
    end

    it "allows changing moderator privileges" do
      @user = @moderator
      @membership = @community.group_memberships.where(user_id: @member).first
      api_call(:put, "#{@memberships_path}/#{@membership.id}", @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"), {
                 moderator: true
               })
      expect(@membership.reload.moderator).to be_truthy

      api_call(:put, "#{@memberships_path}/#{@membership.id}", @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"), {
                 moderator: false
               })
      expect(@membership.reload.moderator).to be_falsey
    end

    it "allows changing moderator privileges using users/:user_id endpoint" do
      @user = @moderator
      @membership = @community.group_memberships.where(user_id: @member).first
      api_call(:put, "#{@alternate_memberships_path}/#{@member.id}", @memberships_path_options.merge(group_id: @community.to_param, user_id: @member.to_param, action: "update"), {
                 moderator: true
               })
      expect(@membership.reload.moderator).to be_truthy

      api_call(:put, "#{@alternate_memberships_path}/#{@member.id}", @memberships_path_options.merge(group_id: @community.to_param, user_id: @member.to_param, action: "update"), {
                 moderator: false
               })
      expect(@membership.reload.moderator).to be_falsey
    end

    it "does not allow a member to change moderator privileges" do
      @user = @member
      @membership = @community.group_memberships.where(user_id: @moderator).first
      api_call(:put,
               "#{@memberships_path}/#{@membership.id}",
               @memberships_path_options.merge(group_id: @community.to_param, membership_id: @membership.to_param, action: "update"),
               {
                 moderator: false
               },
               {},
               expected_status: 403)
      expect(@membership.reload.moderator).to be_truthy
    end

    it "does not allow a member to change moderator privileges using users/:user_id endpoint" do
      @user = @member
      @membership = @community.group_memberships.where(user_id: @moderator).first
      api_call(:put,
               "#{@alternate_memberships_path}/#{@user.id}",
               @memberships_path_options.merge(group_id: @community.to_param, user_id: @user.to_param, action: "update"),
               {
                 moderator: false
               },
               {},
               expected_status: 403)
      expect(@membership.reload.moderator).to be_truthy
    end

    it "allows someone to leave a group" do
      @user = @member
      @gm = @community.group_memberships.where(user_id: @user).first
      api_call(:delete, "#{@memberships_path}/#{@gm.id}", @memberships_path_options.merge(group_id: @community.to_param, membership_id: @gm.to_param, action: "destroy"))
      @membership = GroupMembership.where(user_id: @user, group_id: @community).first
      expect(@membership.workflow_state).to eq "deleted"
    end

    it "allows someone to leave a group using users/:user_id endpoint" do
      @user = @member
      @gm = @community.group_memberships.where(user_id: @user).first
      api_call(:delete, "#{@alternate_memberships_path}/#{@user.id}", @memberships_path_options.merge(group_id: @community.to_param, user_id: @user.to_param, action: "destroy"))
      @membership = GroupMembership.where(user_id: @user, group_id: @community).first
      expect(@membership.workflow_state).to eq "deleted"
    end

    it "allows leaving a group using 'self'" do
      @user = @member
      api_call(:delete, "#{@memberships_path}/self", @memberships_path_options.merge(group_id: @community.to_param, membership_id: "self", action: "destroy"))
      @membership = GroupMembership.where(user_id: @user, group_id: @community).first
      expect(@membership.workflow_state).to eq "deleted"
    end

    it "allows leaving a group using 'self' using users/:user_id endpoint" do
      @user = @member
      api_call(:delete, "#{@alternate_memberships_path}/self", @memberships_path_options.merge(group_id: @community.to_param, user_id: "self", action: "destroy"))
      @membership = GroupMembership.where(user_id: @user, group_id: @community).first
      expect(@membership.workflow_state).to eq "deleted"
    end

    it "allows leaving a group using sis id using users/:user_id endpoint" do
      @user = @member
      @member.pseudonyms.first.update_attribute(:sis_user_id, "my_sis_id")
      api_call(:delete, "#{@alternate_memberships_path}/sis_user_id:my_sis_id", @memberships_path_options.merge(group_id: @community.to_param, user_id: "sis_user_id:my_sis_id", action: "destroy"))
      @membership = GroupMembership.where(user_id: @user, group_id: @community).first
      expect(@membership.workflow_state).to eq "deleted"
    end

    it "allows a moderator to invite people to a group" do
      @user = @moderator
      invitees = { invitees: ["leonard@example.com", "sheldon@example.com"] }
      expect do
        @json = api_call(:post, "#{@community_path}/invite", @category_path_options.merge(group_id: @community.to_param, action: "invite"), invitees)
      end.to change(User, :count).by(2)
      @memberships = @community.reload.group_memberships.where(workflow_state: "invited").order(:id).to_a
      expect(@memberships.count).to eq 2
      expect(@json.sort_by { |a| a["id"] }).to eq(@memberships.map { |gm| membership_json(gm) })
    end

    it "does not allow a member to invite people to a group" do
      @user = @member
      invitees = { invitees: ["leonard@example.com", "sheldon@example.com"] }
      api_call(:post, "#{@community_path}/invite", @category_path_options.merge(group_id: @community.to_param, action: "invite"), invitees, {}, expected_status: 403)
      @memberships = expect(@community.reload.group_memberships.where(workflow_state: "invited").order(:id).count).to eq 0
    end

    it "finds people when inviting to a group in a non-default account" do
      @account = Account.create!
      @category = @account.group_categories.create!(name: "foo")
      @group = group_model(name: "Blah", group_category: @category, context: @account)

      @moderator = user_model
      @group.add_user(@moderator, "accepted", true)

      @member = user_with_pseudonym(account: @account)

      @user = @moderator
      api_call(
        :post,
        "/api/v1/groups/#{@group.id}/invite",
        { controller: "groups", format: "json", group_id: @group.to_param, action: "invite" },
        { invitees: [@member.pseudonym.unique_id] },
        {},
        { domain_root_account: @account }
      )

      expect(@member.group_memberships.count).to eq 1
    end

    it "allows being added to a non-community account group" do
      @account = Account.default
      @category = @account.group_categories.create!(name: "foo")
      @group = group_model(group_category: @category, context: @account)

      @to_add = user_with_pseudonym(account: @account, active_all: true)
      @user = account_admin_user(account: @account, active_all: true)
      json = api_call(
        :post,
        "/api/v1/groups/#{@group.id}/memberships",
        @memberships_path_options.merge(group_id: @group.to_param, action: "create"),
        { user_id: @to_add.id }
      )

      @membership = GroupMembership.where(user_id: @to_add, group_id: @group).first
      expect(@membership.workflow_state).to eq "accepted"
      expect(json).to eq membership_json(@membership, true).merge("just_created" => true)
    end

    it "shows sis_import_id for group" do
      user_model
      sis_batch = @community.root_account.sis_batches.create
      SisBatch.where(id: sis_batch).update_all(workflow_state: "imported")
      membership = @community.add_user(@user, "invited")
      membership.sis_batch_id = sis_batch.id
      membership.save!
      @user = account_admin_user(account: @account, active_all: true)
      json = api_call(:get, @memberships_path, @memberships_path_options.merge(group_id: @community.to_param, action: "index"), {
                        filter_states: ["invited"]
                      })
      expect(json.first["sis_import_id"]).to eq sis_batch.id
      expect(json.first).to eq membership_json(@community.group_memberships.where(workflow_state: "invited").first, true)
    end

    it "allows a user to join a group whose self sign-up is still open" do
      course_with_student(active_all: true)
      @course.account.enable_feature!(:self_signup_deadline)
      @category = @course.group_categories.create!(name: "foo", self_signup: "enabled", self_signup_end_at: 1.day.from_now)
      @group = group_model(group_category: @category, context: @course)
      user_session(@student)

      json = api_call(
        :post,
        "/api/v1/groups/#{@group.id}/memberships",
        @memberships_path_options.merge(group_id: @group.to_param, action: "create"),
        { user_id: @student.id }
      )

      @membership = GroupMembership.where(user_id: @student, group_id: @group).first
      expect(@membership.workflow_state).to eq "accepted"
      expect(json).to eq membership_json(@membership, true).merge("just_created" => true)
    end

    it "does not allow a user to join a group whose self sign-up is closed" do
      course_with_student(active_all: true)
      @course.account.enable_feature!(:self_signup_deadline)
      @category = @course.group_categories.create!(name: "foo", self_signup: "enabled", self_signup_end_at: 1.day.ago)
      @group = group_model(group_category: @category, context: @course)
      user_session(@student)

      api_call(
        :post,
        "/api/v1/groups/#{@group.id}/memberships",
        @memberships_path_options.merge(group_id: @group.to_param, action: "create"),
        { user_id: @student.id },
        {},
        expected_status: 403
      )
    end

    it "bulks add users to non collaborative groups" do
      course_with_teacher(active_all: true)
      @course.account.enable_feature! :assign_to_differentiation_tags
      @course.account.settings[:allow_assign_to_differentiation_tags] = { value: true }
      @course.account.save!
      @course.account.reload
      category = @course.group_categories.create(name: "category", non_collaborative: true)
      @group = @course.groups.create!(name: "G1", group_category: category, non_collaborative: true)
      user = student_in_course(active_all: true).user
      user2 = student_in_course(active_all: true).user
      user_session(@teacher)
      post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, members: [user.id, user2.id] }

      expect(response).to be_successful
      expect(user.differentiation_tag_memberships.pluck(:group_id)).to include @group.id
      expect(user2.differentiation_tag_memberships.pluck(:group_id)).to include @group.id
    end

    it "calls SLM when assignmnets are assigned to the non-collaborative group" do
      course_with_teacher(active_all: true)
      @course.account.enable_feature! :assign_to_differentiation_tags
      @course.account.settings[:allow_assign_to_differentiation_tags] = { value: true }
      @course.account.save!
      @course.account.reload
      category = @course.group_categories.create(name: "category", non_collaborative: true)
      @group = @course.groups.create!(name: "G1", group_category: category, non_collaborative: true)
      da = assignment_model(course: @course)
      diff_tag_override = assignment_override_model(assignment: da)
      diff_tag_override.set_type = "Group"
      diff_tag_override.set_id = @group.id
      diff_tag_override.save!
      da.update!(only_visible_to_overrides: true)
      user = student_in_course(active_all: true).user
      user2 = student_in_course(active_all: true).user
      user_session(@teacher)

      expect(SubmissionLifecycleManager).not_to receive(:recompute)
      expect(SubmissionLifecycleManager).to receive(:recompute_users_for_course).with(
        [user.id, user2.id],
        @course.id,
        match_array([da.id])
      )
      post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, members: [user.id, user2.id] }
      expect(response).to be_successful
    end

    describe "POST /api/v1/groups/:group_id/memberships (Differentiation Tag Membership)" do
      before do
        course_with_teacher(active_all: true)
        @course.account.enable_feature! :assign_to_differentiation_tags
        @course.account.settings[:allow_assign_to_differentiation_tags] = { value: true }
        @course.account.save!
        @course.account.reload
        category = @course.group_categories.create!(name: "Differentiation", non_collaborative: true)
        @group = @course.groups.create!(name: "Diff Group", group_category: category, non_collaborative: true)
        user_session(@teacher)
      end

      context "when the members param is blank" do
        it "returns ok without processing any memberships" do
          post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, members: [] }
          expect(response).to have_http_status :ok
        end
      end

      context "when the group context is an Account" do
        it "returns ok and does not attempt to add memberships" do
          @account_group = group_model(name: "Algebra Teachers", context: Account.default)
          student = student_in_course(active_all: true).user
          post "/api/v1/groups/#{@account_group.id}/memberships", params: { group_id: @account_group.id, members: [student.id] }
          expect(response).to have_http_status :bad_request
          # Ensure that no differentiation tag memberships were created
          expect(student.differentiation_tag_memberships.pluck(:group_id)).not_to include(@account_group.id)
        end
      end

      context "when the current user is not authorized" do
        it "returns forbidden" do
          # Stub the authorization check to simulate lack of permission.
          student = student_in_course(active_all: true).user
          user_session(student)
          post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, members: [student.id] }
          expect(response).not_to be_successful
        end
      end

      context "when valid users are provided and processing succeeds" do
        it "adds the memberships and returns ok" do
          student = student_in_course(active_all: true).user
          post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, members: [student.id] }
          expect(response).to have_http_status :ok
          expect(student.differentiation_tag_memberships.pluck(:group_id)).to include(@group.id)
        end

        it "processes all enrollments excluding specified users when using params[:all_in_group_course] and params[:exclude]" do
          # Create three enrolled students.
          student1 = student_in_course(active_all: true).user
          student2 = student_in_course(active_all: true).user
          student3 = student_in_course(active_all: true).user

          user_session(@teacher)

          post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, all_in_group_course: true, exclude_user_ids: [student2.id] }

          expect(response).to have_http_status :ok

          @group.reload
          expect(@group.group_memberships.active.count).to eq @course.student_enrollments.active.count - 1
          expect(@group.group_memberships.active.pluck(:user_id)).to include(student1.id, student3.id)
          expect(@group.group_memberships.active.pluck(:user_id)).not_to include(student2.id)
        end

        it "does not include all enrollments excluding when using params[:all_in_group_course] with a string" do
          student_in_course(active_all: true).user
          student_in_course(active_all: true).user

          user_session(@teacher)

          post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, all_in_group_course: "false", members: [@student.id] }

          expect(response).to have_http_status :ok

          @group.reload
          expect(@group.group_memberships.active.count).to eq 1
        end
      end

      context "when some users are not actively enrolled" do
        it "returns partial failure with invalid_user_ids" do
          enrolled_student = student_in_course(active_all: true).user
          not_enrolled_student = course_with_student(active_all: true).user

          post "/api/v1/groups/#{@group.id}/memberships",
               params: { group_id: @group.id, members: [enrolled_student.id, not_enrolled_student.id] }

          expect(response).to have_http_status :ok
          json = JSON.parse(response.body)
          expect(json["message"]).to eq "Partial failure encountered"
          expect(json["invalid_user_ids"]).to include(not_enrolled_student.id)
          expect(enrolled_student.differentiation_tag_memberships.pluck(:group_id)).to include(@group.id)
        end
      end

      context "when membership errors occur during bulk addition" do
        it "returns partial failure with membership_errors" do
          student = student_in_course(active_all: true).user

          # Create a real GroupMembership instance and add an error to it.
          error_membership = GroupMembership.new(group: @group, user: student)
          error_membership.errors.add(:base, "Error adding membership")

          # Stub bulk_add_users_to_differentiation_tag to return the real membership with errors.
          allow_any_instance_of(Group).to receive(:bulk_add_users_to_differentiation_tag).and_return([error_membership])

          post "/api/v1/groups/#{@group.id}/memberships", params: { group_id: @group.id, members: [student.id] }

          expect(response).to have_http_status :ok
          json = JSON.parse(response.body)
          expect(json["message"]).to eq "Partial failure encountered"
          expect(json["membership_errors"]).not_to be_empty
        end
      end
    end
  end

  context "users" do
    let(:api_url) { "/api/v1/groups/#{@community.id}/users.json" }
    let(:api_route) do
      {
        controller: "groups",
        action: "users",
        group_id: @community.to_param,
        format: "json"
      }
    end

    it "returns users in a group" do
      expected_keys = %w[id name sortable_name short_name]
      json = api_call(:get,
                      "/api/v1/groups/#{@community.id}/users",
                      { controller: "groups", action: "users", group_id: @community.to_param, format: "json" })
      expect(json.count).to eq 2
      json.each do |user|
        expect((user.keys & expected_keys).sort).to eq expected_keys.sort
        expect(@community.users.map(&:id)).to include(user["id"])
      end
    end

    it "returns 403 for users outside the group" do
      user_factory
      raw_api_call(:get,
                   "/api/v1/groups/#{@community.id}/users",
                   { controller: "groups", action: "users", group_id: @community.to_param, format: "json" })
      expect(response).to have_http_status :forbidden
    end

    it "returns an error when search_term is fewer than 2 characters" do
      json = api_call(:get, api_url, api_route, { search_term: "a" }, {}, expected_status: 400)
      error = json["errors"].first
      verify_json_error(error, "search_term", "invalid", "2 or more characters is required")
    end

    it "returns a list of users" do
      expected_keys = %w[id name sortable_name short_name]

      json = api_call(:get, api_url, api_route, { search_term: "value" })

      expect(json.count).to eq 1
      json.each do |user|
        expect((user.keys & expected_keys).sort).to eq expected_keys.sort
        expect(@community.users.map(&:id)).to include(user["id"])
      end
    end

    it "honors the include[avatar_url] query parameter flag" do
      account = @community.context
      account.set_service_availability(:avatars, true)
      account.save!

      user = @community.users.first
      user.avatar_image_url = "http://expected_avatar_url"
      user.save!

      json = api_call(:get, api_url + "?include[]=avatar_url", api_route.merge(include: ["avatar_url"]))
      expect(json.first["avatar_url"]).to eq user.avatar_image_url
    end

    it "honors the exclude_inactive query parameter" do
      course_with_teacher(active_all: true)
      @group = @course.groups.create!(name: "Inactive user group")

      inactive_user = user_factory
      enrollment = @course.enroll_student(inactive_user)
      enrollment.deactivate
      @group.add_user(inactive_user, "accepted")

      @course.enroll_student(user_factory).accept!
      @group.add_user(@user, "accepted")

      json = api_call(:get,
                      "/api/v1/groups/#{@group.id}/users?exclude_inactive=true",
                      api_route.merge({ exclude_inactive: true, group_id: @group.id }))

      expect(json.count).to eq 1
      expect(json.first["id"]).to eq @user.id

      enrollment.reactivate

      json = api_call(:get,
                      "/api/v1/groups/#{@group.id}/users?exclude_inactive=true",
                      api_route.merge({ exclude_inactive: true, group_id: @group.id }))

      expect(json.count).to eq 2
      expect(json.first["id"]).to eq inactive_user.id
    end
  end

  context "group files" do
    include_examples "file uploads api with folders"
    include_examples "file uploads api with quotas"

    before do
      @user = @member
    end

    def preflight(preflight_params, opts = {})
      api_call(:post,
               "/api/v1/groups/#{@community.id}/files",
               { controller: "groups", action: "create_file", format: "json", group_id: @community.to_param, },
               preflight_params,
               {},
               opts)
    end

    def has_query_exemption?
      false
    end

    def context
      @community
    end
  end

  it "returns the activity stream" do
    course_with_teacher(active_all: true, user: user_with_pseudonym)
    @group = @course.groups.create!(name: "Group 1")
    @group.users << @user
    @context = @group
    @topic1 = discussion_topic_model
    json = api_call(:get,
                    "/api/v1/groups/#{@group.id}/activity_stream.json",
                    { controller: "groups", group_id: @group.id.to_s, action: "activity_stream", format: "json" })
    expect(json.size).to eq 1
  end

  it "returns the activity stream summary" do
    course_with_teacher(active_all: true, user: user_with_pseudonym)
    @group = @course.groups.create!(name: "Group 1")
    @group.users << @user
    @context = @group
    @topic1 = discussion_topic_model
    json = api_call(:get,
                    "/api/v1/groups/#{@group.id}/activity_stream/summary.json",
                    { controller: "groups", group_id: @group.id.to_s, action: "activity_stream_summary", format: "json" })
    expect(json).to eq [{ "type" => "DiscussionTopic", "count" => 1, "unread_count" => 1, "notification_category" => nil }]
  end

  describe "/preview_html" do
    before :once do
      course_with_teacher(active_all: true)
      @group = @course.groups.create!(name: "Group 1")
    end

    before do
      user_session @teacher
    end

    context "with double testing verifiers with disable_adding_uuid_verifier_in_api ff" do
      before do
        attachment_model(context: @group)
      end

      double_testing_with_disable_adding_uuid_verifier_in_api_ff do
        it "sanitizes html and process links" do
          @user = @teacher
          html = %(<p><a href="/files/#{@attachment.id}/download?verifier=huehuehuehue">Click!</a><script></script></p>)
          json = api_call(:post,
                          "/api/v1/groups/#{@group.id}/preview_html",
                          { controller: "groups", action: "preview_html", group_id: @group.to_param, format: "json" },
                          { html: })

          returned_html = json["html"]
          expect(returned_html).not_to include("<script>")
          expect(returned_html).to include("/groups/#{@group.id}/files/#{@attachment.id}/download#{"?verifier=#{@attachment.uuid}" unless disable_adding_uuid_verifier_in_api}")
        end
      end
    end

    it "requires permission to preview" do
      @user = user_factory
      api_call(:post,
               "/api/v1/groups/#{@group.id}/preview_html",
               { controller: "groups", action: "preview_html", group_id: @group.to_param, format: "json" },
               { html: "" },
               {},
               { expected_status: 403 })
    end
  end

  context "permissions" do
    before :once do
      course_with_student(active_all: true)
      @group = @course.groups.create!
    end

    it "returns permissions" do
      @group.add_user(@student)
      json = api_call(:get,
                      "/api/v1/groups/#{@group.id}/permissions?permissions[]=send_messages&permissions[]=manage_blarghs",
                      controller: "groups",
                      action: "permissions",
                      group_id: @group.to_param,
                      format: "json",
                      permissions: %w[send_messages manage_blarghs])
      expect(json).to eq({ "send_messages" => true, "manage_blarghs" => false })
    end

    it "requires :read permission on the group" do
      api_call(:get,
               "/api/v1/groups/#{@group.id}/permissions?permissions[]=send_messages",
               { controller: "groups",
                 action: "permissions",
                 group_id: @group.to_param,
                 format: "json",
                 permissions: %w[send_messages] },
               {},
               {},
               { expected_status: 403 })
    end
  end
end
