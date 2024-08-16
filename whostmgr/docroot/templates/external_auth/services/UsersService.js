/*
# templates/external_auth/services/UsersService.js       Copyright 2022 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

// Then load the application dependencies
define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/modules",
    ],
    function(angular, _, CJT, PARSE, API, APIREQUEST) {
        "use strict";

        var app = angular.module("App");

        function UsersServiceFactory($q) {
            var users = [];
            var UsersService = {};

            UsersService.get_users = function() {
                return users;
            };

            UsersService.fetch_users = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "get_users_authn_linked_accounts");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                deferred.promise.then(function(result) {
                    users = [];
                    angular.forEach(result.data, function(row) {
                        var user = UsersService.get_user_by_username(row.username);
                        if (!user) {
                            user = {
                                username: row.username,
                                links: {}
                            };
                            users.push(user);
                        }
                        if (!user.links[row.provider_protocol]) {
                            user.links[row.provider_protocol] = {};
                        }
                        if (!user.links[row.provider_protocol][row.provider_id]) {
                            user.links[row.provider_protocol][row.provider_id] = {};
                        }
                        user.links[row.provider_protocol][row.provider_id][row.subject_unique_identifier] = {
                            link_type: row.link_type,
                            preferred_username: row.preferred_username
                        };

                    });
                });

                return deferred.promise;
            };
            UsersService.get_user_by_username = function(username) {
                for (var i = 0; i < users.length; i++) {
                    if (users[i].username === username) {
                        return users[i];
                    }
                }
            };
            UsersService.unlink_provider = function(username, subject_unique_identifier, provider) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "unlink_user_authn_provider");
                apiCall.addArgument("username", username);
                apiCall.addArgument("subject_unique_identifier", subject_unique_identifier);
                apiCall.addArgument("provider_id", provider);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            return UsersService;
        }
        UsersServiceFactory.$inject = ["$q", "growl"];
        return app.factory("UsersService", UsersServiceFactory);
    });
