/*
 * templates/tomcat/services/configService.js           Copyright(c) 2020 cPanel, L.L.C.
 *                                                                 All rights reserved.
 * copyright@cpanel.net                                               http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/io/whm-v1-request",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1",
        "cjt/services/APIService"
    ],
    function(angular, _, LOCALE, APIREQUEST, PARSE) {

        "use strict";

        var app = angular.module("whm.tomcat.configService", []);
        app.factory(
            "TomcatApi",
            ["$q", "APIService", function($q, APIService) {

                var TomcatApiService = function() { };
                TomcatApiService.prototype = new APIService();

                var isEmptyObject = function(obj) {
                    for (var key in obj) {
                        if (obj.hasOwnProperty(key)) {
                            return false;
                        }
                    }
                    return true;
                };

                var userList = {};
                angular.extend(TomcatApiService.prototype, {

                    /**
                     * Returns a list of cPanel & WHM users.
                     *
                     * @method - getUsers
                     * @param {Boolean} force - If true, will force load the data into the cached object.
                     * @returns {Promise} - When fulfilled, will return list of users.
                     */
                    getUsers: function getUsers(force) {
                        if (force || isEmptyObject(userList)) {
                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("", "list_users");

                            return this.deferred(apiCall).promise
                                .then(function(response) {
                                    userList = response.data;
                                    return userList;
                                })
                                .catch(function(error) {
                                    return $q.reject(error);
                                });
                        } else {
                            return $q.when(userList);
                        }
                    },

                    /**
                     * Returns a list of users for whom Tomcat is enabled.
                     *
                     * @method getTomcatList
                     * @returns {Promise} When fulfilled, will return the list of Tomcat enabled users.
                     */
                    getTomcatList: function getTomcatList() {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("", "ea4_tomcat85_list");

                        return this.deferred(apiCall).promise
                            .then(function(response) {
                                userList = response.data;
                                return userList;
                            })
                            .catch(function(error) {
                                return $q.reject(error);
                            });
                    },

                    /**
                     * The service used to enable or disable Tomcat for selected user.
                     *
                     * @method enableDisableTomcat
                     * @param {Array} userList - List of selected users.
                     * @param {boolean} enable - Toggle flag ? true to enable : false to disable.
                     */
                    enableDisableTomcat: function enableDisableTomcat(userList, enable) {
                        var apiCall = new APIREQUEST.Class();
                        if (enable) {
                            apiCall.initialize("", "ea4_tomcat85_add");
                        } else {
                            apiCall.initialize("", "ea4_tomcat85_rem");
                        }

                        _.each(userList, function(user, index) {
                            apiCall.addArgument("user-" + index, user);
                        });

                        return this.deferred(apiCall).promise
                            .then(function(response) {
                                return response.data;
                            })
                            .catch(function(error) {
                                return $q.reject(error);
                            });
                    },
                });

                return new TomcatApiService();
            }
            ]);
    });
