/*
# templates/twofactorauth/services/tfaData.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it's ready
        "cjt/decorators/growlDecorator"
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST) {
        "use strict";

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", []);
        }

        var twoFactorAuth = app.factory("TwoFactorData", ["$q", "PAGE", function($q, PAGE) {

            var twoFactorData = {};

            twoFactorData.enabled = false;

            twoFactorData.currentUser = {
                "user_name": PAGE.user,
                "is_enabled": PARSE.parsePerlBoolean(PAGE.current_user_tfa_status)
            };

            twoFactorData.userData = {};

            twoFactorData.issuer = PAGE.issuer;
            twoFactorData.systemWideIssuer = PAGE.system_wide_issuer;

            function convertUserObjectResponseToList(data) {
                var list = [];
                if (data === void 0 || data === null) {
                    return list;
                }

                var keys = Object.keys(data);
                var len = keys.length;
                for (var i = 0; i < len; i++) {
                    var obj = data[keys[i]];
                    obj.user_name = keys[i];
                    obj.is_enabled = PARSE.parsePerlBoolean(obj.is_enabled);

                    // We only care about entries that have 2FA enabled (is_enabled is true) atm,
                    if (obj.is_enabled) {
                        list.push(obj);
                    }
                }
                return list;
            }

            twoFactorData.getStatus = function() {
                var deferred = $q.defer();

                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_policy_status");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            twoFactorData.enabled = PARSE.parsePerlBoolean(response.data.is_enabled);
                            deferred.resolve(twoFactorData.enabled);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };


            twoFactorData.enable = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_enable_policy");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            twoFactorData.enabled = true;
                            deferred.resolve(twoFactorData.enabled);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            twoFactorData.disable = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_disable_policy");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.status);
                            twoFactorData.enabled = false;
                            deferred.resolve(twoFactorData.enabled);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            twoFactorData.getUsers = function(user) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_get_user_configs");

                if (user !== void 0) {
                    apiCall.addArgument("user", user);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            twoFactorData.userData = response.data;

                            if (response.data) {

                                // remove current user (root or reseller) from the user list
                                // to avoid problems with mass operations
                                delete response.data[twoFactorData.currentUser.user_name];
                            }
                            deferred.resolve(convertUserObjectResponseToList(response.data));
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            twoFactorData.saveIssuer = function(issuer) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_set_issuer");
                apiCall.addArgument("issuer", issuer);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            twoFactorData.issuer = issuer;
                            if (twoFactorData.currentUser.user_name === "root") {
                                twoFactorData.systemWideIssuer = issuer;
                            }
                            deferred.resolve(issuer);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            twoFactorData.getIssuer = function(issuer) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_get_issuer");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            twoFactorData.issuer = response.data.issuer;
                            twoFactorData.systemWideIssuer = response.data.system_wide_issuer;
                            deferred.resolve();
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            twoFactorData.disableFor = function(users) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_remove_user_config");

                if (typeof (users) === "string") {
                    apiCall.addArgument("user-0", users.user_name);
                } else if (typeof (users) === "object") {
                    var paramIndex = 0, userCount = users.length;

                    for (; paramIndex < userCount; paramIndex++) {
                        apiCall.addArgument("user-" + paramIndex, users[paramIndex].user_name);
                    }
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            twoFactorData.userData = _.omit(twoFactorData.userData, response.data.users_modified);

                            // update the currentUser stash in case we removed 2FA for the current user
                            var hasCurrentUser = response.data.users_modified.filter(function(item) {
                                return item === twoFactorData.currentUser.user_name;
                            });
                            if (hasCurrentUser.length > 0) {
                                twoFactorData.currentUser.is_enabled = false;
                            }

                            response.data.list = [];
                            response.data.list = convertUserObjectResponseToList(twoFactorData.userData);
                            deferred.resolve(response.data);
                        } else {
                            deferred.reject(response.error);
                        }
                    });

                return deferred.promise;
            };

            twoFactorData.generateSetupData = function() {
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_generate_tfa_config");

                return $q.when(API.promise(apiCall.getRunArguments()))
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            return response.data;
                        } else {
                            return $q.reject(response.error);
                        }
                    });
            };

            twoFactorData.saveSetupData = function(security_token, secret) {
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "twofactorauth_set_tfa_config");
                apiCall.addArgument("secret", secret);
                apiCall.addArgument("tfa_token", security_token);

                return $q.when(API.promise(apiCall.getRunArguments()))
                    .then(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            twoFactorData.currentUser.is_enabled = PARSE.parsePerlBoolean(response.data.success);
                            return twoFactorData.currentUser.is_enabled;
                        } else {
                            return $q.reject(response.error);
                        }
                    });
            };

            return twoFactorData;
        }]);

        return twoFactorAuth;
    }
);
