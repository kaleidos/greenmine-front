# Copyright 2013 Andrey Antukh <niwi@niwi.be>
#
# Licensed under the Apache License, Version 2.0 (the "License")
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

class KanbanController extends TaigaBaseController
    @.$inject = ['$scope', '$rootScope', '$routeParams', '$q', 'resource',
               '$data','$modal', "$model", "$i18next", "$favico"]

    constructor: (@scope, @rootScope, @routeParams, @q, @rs, @data, @modal, @model, @i18next, @favico) ->
        super(scope)

    initialize: ->
        @favico.reset()
        # Global Scope Variables
        @rootScope.pageTitle = @i18next.t('common.kanban')
        @rootScope.pageSection = 'kanban'
        @rootScope.pageBreadcrumb = [
            ["", ""],
            [@i18next.t('common.kanban'), null]
        ]

        @rs.resolve(pslug: @routeParams.pslug).then (data) =>
            @rootScope.projectSlug = @routeParams.pslug
            @rootScope.projectId = data.project

            @data.loadProject(@scope).then =>
                @data.loadUsersAndRoles(@scope).then =>
                    @data.loadUserStories(@scope).then =>
                        @formatUserStories()


    formatUserStories: ->
        @scope.uss = {}
        for status in @scope.constants.usStatusesList
            @scope.uss[status.id] = []

        for us in @scope.userstories
            @scope.uss[us.status].push(us)

        return

    saveUsPoints: (us, role, ref) ->
        points = _.clone(us.points)
        points[role.id] = ref

        us.points = points

        us._moving = true
        promise = us.save()
        promise.then ->
            us._moving = false
            calculateStats()
            @scope.$broadcast("points:changed")

        promise.then null, (data, status) ->
            us._moving = false
            us.revert()

    saveUsStatus: (us, id) ->
        us.status = id
        us._moving = true
        us.save().then (data) ->
            data._moving = false

    initializeUsForm: (us, status) ->
        if us?
            return us

        result = {}
        result['project'] = @scope.projectId
        result['status'] = status or @scope.project.default_us_status
        points = {}
        for role in @scope.constants.computableRolesList
            points[role.id] = @scope.project.default_points
        result['points'] = points
        return result

    openCreateUsForm: (statusId) ->
        promise = @modal.open("us-form", {'us': @initializeUsForm(null, statusId), 'type': 'create'})
        promise.then (us) =>
            newUs = @model.make_model("userstories", us)
            @scope.userstories.push(newUs)
            @formatUserStories()

    openEditUsForm: (us) ->
        promise = @modal.open("us-form", {'us': us, 'type': 'edit'})
        promise.then =>
            @formatUserStories()

    resortUserStories: (statusId)->
        for item, index in @scope.uss[statusId]
            item.order = index

        modifiedUs = _.filter(@scope.uss[statusId], (x) -> x.isModified())
        bulkData = _.map(@scope.uss[statusId], (value, index) -> [value.id, index])

        for item in modifiedUs
            item._moving = true

        promise = @rs.updateBulkUserStoriesOrder(@scope.projectId, bulkData)
        promise = promise.then ->
            for us in modifiedUs
                us.markSaved()
                us._moving = false

        return promise

    sortableOnAdd: (us, index, sortableScope) =>
        us.status = sortableScope.status.id

        us._moving = true
        us.save().then =>
            if @scope.project.is_backlog_activated
                @scope.uss[sortableScope.status.id].splice(us.order, 0, us)
            else
                @scope.uss[sortableScope.status.id].splice(index, 0, us)
                @resortUserStories(sortableScope.status.id)
            us._moving = false

    sortableOnUpdate: (uss, sortableScope, us) =>
        if @scope.project.is_backlog_activated
            @data.loadUserStories(@scope).then =>
                @formatUserStories()
        else
            @scope.uss[sortableScope.status.id] = uss
            @resortUserStories(sortableScope.status.id)

    sortableOnRemove: (us, sortableScope) =>
        _.remove(@scope.uss[sortableScope.status.id], us)


class KanbanUsModalController extends ModalBaseController
    @.$inject = ['$scope', '$rootScope', '$gmOverlay', '$gmFlash', 'resource', "$i18next"]

    constructor: (@scope, @rootScope, @gmOverlay, @gmFlash, @rs, @i18next) ->
        super(scope)

    initialize: ->
        @scope.type = "create"
        @scope.formOpened = false

        # Load data
        @scope.defered = null
        @scope.context = null

        @scope.$on "select2:changed", (ctx, value) =>
            @scope.form.tags = value

        @scope.assignedToSelectOptions = {
            formatResult: @assignedToSelectOptionsShowMember
            formatSelection: @assignedToSelectOptionsShowMember
        }

    loadProjectTags: ->
        @rs.getProjectTags(@scope.projectId).then (data) =>
            @scope.projectTags = data

    openModal: ->
        @loadProjectTags()
        @scope.form = @scope.context.us
        @scope.formOpened = true

        @scope.$broadcast("checksley:reset")
        @scope.$broadcast("wiki:clean-previews")

        @gmOverlay.open().then =>
            @scope.formOpened = false

    closeModal: ->
        @scope.formOpened = false

    start: (dfr, ctx) ->
        @scope.defered = dfr
        @scope.context = ctx
        @openModal()

    delete: ->
        @closeModal()
        @scope.form = form
        @scope.formOpened = true

    submit: ->
        if @scope.form.id?
            promise = @scope.form.save(false)
        else
            promise = @rs.createUs(@scope.form)
        @scope.$emit("spinner:start")

        promise.then (data) =>
            @scope.$emit("spinner:stop")
            @closeModal()
            @gmOverlay.close()
            @scope.form.id = data.id
            @scope.form.ref = data.ref
            @scope.defered.resolve(@scope.form)
            @gmFlash.info(@i18next.t('kanban.user-story-saved'))

        promise.then null, (data) =>
            @scope.checksleyErrors = data

    close: ->
        @scope.formOpened = false
        @gmOverlay.close()

        if @scope.form.id?
            @scope.form.revert()
        else
            @scope.form = {}

    assignedToSelectOptionsShowMember: (option, container) =>
        if option.id
            member = _.find(@rootScope.constants.users, {id: parseInt(option.id, 10)})
            # TODO: make me more beautiful and elegant
            return "<span style=\"padding: 0px 5px;
                                  border-left: 15px solid #{member.color}\">#{member.full_name}</span>"
         return "<span\">#{option.text}</span>"


class KanbanUsController extends TaigaBaseController
    @.$inject = ['$scope', '$rootScope', '$q', "$location"]

    constructor: (@scope, @rootScope, @q, @location) ->
        super(scope)

    updateUsAssignation: (us, id) ->
        us.assigned_to = id || null
        us._moving = true
        us.save().then((us) ->
            us._moving = false
        , ->
            us.revert()
            us._moving = false
        )

    openUs: (projectSlug, usRef) ->
        @location.url("/project/#{projectSlug}/user-story/#{usRef}")


module = angular.module("taiga.controllers.kanban", [])
module.controller("KanbanController", KanbanController)
module.controller("KanbanUsController", KanbanUsController)
module.controller("KanbanUsModalController", KanbanUsModalController)
