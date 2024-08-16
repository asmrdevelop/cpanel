/* global define, PAGE */

define(
    [
        "angular",
        "lodash",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it’s ready
    ],
    function(angular, _, API, APIREQUEST) {

        var app = angular.module("App");

        function AutoSSLConfigureServiceFactory($q, PAGE) {
            var AutoSSLConfigureService = {};

            var users = [];
            var usermap = {};
            var NO_MODULE = null;

            function _call_api(module, call, params, filters) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize(module, call);

                angular.forEach(params, function(param, key) {
                    apiCall.addArgument(key, param);
                });

                if (filters) {
                    angular.forEach(filters, function(filter) {
                        apiCall.addFilter(filter.key, filter.operator, filter.value);
                    });
                }

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

            }

            function _build_batch_command(call, params) {
                var command_str = call;

                if (params) {
                    var command_params = [];
                    angular.forEach(params, function(value, key) {
                        command_params.push(key + "=" + encodeURIComponent(value));
                    });

                    command_str += "?" + command_params.join("&");
                }

                return command_str;
            }

            AutoSSLConfigureService._set_auto_ssl_for_users = function(items, enable) {

                /* enable the feature means disable the override */
                var features = JSON.stringify({
                    autossl: enable ? "1" : "0"
                });

                // This gets added to in the foreach loop. Format is necessary for batching.
                var params = {
                    command: []
                };

                angular.forEach(items, function(item) {
                    item.updating = true;
                    params.command.push(_build_batch_command("add_override_features_for_user", {
                        user: item.user,
                        features: features
                    }));
                });

                return _call_api(NO_MODULE, "batch", params).then(function() {
                    angular.forEach(items, function(item) {
                        item.auto_ssl_enabled = enable ? "enabled" : "disabled";
                    });
                }).finally(function() {
                    angular.forEach(items, function(item) {
                        item.updating = false;
                    });
                });
            };

            AutoSSLConfigureService.enable_auto_ssl_for_users = function(items) {
                return AutoSSLConfigureService._set_auto_ssl_for_users(items, true);
            };

            AutoSSLConfigureService.disable_auto_ssl_for_users = function(items) {
                return AutoSSLConfigureService._set_auto_ssl_for_users(items, false);
            };

            AutoSSLConfigureService.reset_auto_ssl_for_users = function(items) {

                /* enable the feature means disable the override */
                var features = JSON.stringify(["autossl"]);

                // This gets added to in the foreach loop. Format is necessary for batching.
                var params = {
                    command: []
                };

                angular.forEach(items, function(item) {

                    item.updating = true;
                    params.command.push(_build_batch_command("remove_override_features_for_user", {
                        user: item.user,
                        features: features
                    }));
                });

                return _call_api(NO_MODULE, "batch", params).then(function() {
                    angular.forEach(items, function(item) {
                        item.auto_ssl_enabled = "inherit";
                    });
                }).finally(function() {
                    angular.forEach(items, function(item) {
                        item.updating = false;
                    });
                });

            };

            AutoSSLConfigureService.get_user_by_username = function(username) {
                var user_i = usermap[username];
                return users[user_i];
            };

            AutoSSLConfigureService.get_users = function() {
                return users;
            };

            AutoSSLConfigureService.fetch_users = function() {

                function _update(data) {
                    users = [];
                    usermap = {};
                    angular.forEach(data, function(user) {
                        usermap[user.user] = users.length;
                        users.push({
                            "user": user.user,
                            "rowSelected": 0,
                            "updating": true,
                            "auto_ssl_settings": {}
                        });

                        /* set to true (has ssl) if not set to false by fetch_disabled */
                    });
                    return AutoSSLConfigureService.get_users();
                }

                if (PAGE.users) {
                    return _update(PAGE.users);
                } else {
                    PAGE.users = [];
                }

            };

            AutoSSLConfigureService.fetch_users_features_settings = function(users) {

                function _update(data) {
                    angular.forEach(data, function(setting) {
                        var user = AutoSSLConfigureService.get_user_by_username(setting.user);
                        user.feature_list = setting.feature_list;
                        user.auto_ssl_settings = setting;
                        user.auto_ssl_enabled = "inherit";
                        if (setting.cpuser_setting === "0" || setting.cpuser_setting === "1") {
                            user.auto_ssl_enabled = setting.cpuser_setting === "1" ? "enabled" : "disabled";
                        }
                    });
                    return AutoSSLConfigureService.get_users();
                }

                /* The API call will fail if no users are provided. */
                if (!users.length) {
                    return $q.reject();
                }

                return _call_api(NO_MODULE, "get_users_features_settings", {
                    "user": users.map(function(user) {
                        return user.user;
                    }),
                    "feature": "autossl"
                }).then(function(result) {
                    _update(result.data);
                }).finally(function() {
                    angular.forEach(users, function(user) {
                        user.updating = false;
                    });
                });

            };

            AutoSSLConfigureService.start_autossl_for_user = function(username) {
                return _call_api(
                    NO_MODULE,
                    "start_autossl_check_for_one_user", {
                        username: username
                    }
                );
            };

            return AutoSSLConfigureService;
        }

        AutoSSLConfigureServiceFactory.$inject = ["$q", "PAGE"];
        return app.factory("AutoSSLConfigureService", AutoSSLConfigureServiceFactory);
    });
