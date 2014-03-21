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


class AuthService extends TaigaBaseService
    @.$inject = ["$rootScope", "$gmStorage", "$model"]

    constructor: (@rootScope, @gmStorage, @model) ->
        super()

    getUser: ->
        userData = @gmStorage.get('userInfo')
        if userData
            return @model.make_model("users", userData)
        return null

    setUser: (user) ->
        @rootScope.auth = user
        @rootScope.$broadcast('i18n:change', user.default_language)
        @gmStorage.set("userInfo", user.getAttrs())

    setToken: (token) ->
        @gmStorage.set("token", token)

    getToken: ->
        @gmStorage.get("token")

    isAuthenticated: ->
        if @.getUser() != null
            return true
        return false

module = angular.module('taiga.services.auth', ['taiga.services.model', 'gmStorage'])
module.service("$gmAuth", AuthService)