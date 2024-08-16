/*
# cpanel - whostmgr/docroot/templates/api_tokens/services/api_tokens.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

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

        var app = angular.module("whm.apiTokens.apiCallService", []);
        app.factory(
            "Tokens",
            ["$q", "APIService", function($q, APIService) {

                var TokensService = function() {};
                TokensService.prototype = new APIService();

                var isEmptyObject = function(obj) {
                    for (var key in obj) {
                        if (Object.prototype.hasOwnProperty.call(obj, key)) {
                            return false;
                        }
                    }
                    return true;
                };

                var addAclsTo = function addAclsTo(apiCall, acls) {
                    if (typeof acls !== "undefined") {
                        var i = 0, apiCount = acls.length;
                        for (; i < apiCount; i++) {
                            apiCall.addArgument("acl-" + i, acls[i]);
                        }
                    }
                };

                var tokensData = {};
                var userPrivileges = {};

                angular.extend(TokensService.prototype, {
                    getTokens: function getTokens(force) {
                        if (force || isEmptyObject(tokensData)) {
                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("", "api_token_list");

                            return this.deferred(apiCall).promise
                                .then(function(response) {
                                    tokensData = response.data.tokens;
                                    return tokensData;
                                })
                                .catch(function(error) {
                                    return $q.reject(error);
                                });
                        } else {
                            return $q.when(tokensData);
                        }
                    },

                    createToken: function createToken(name, acls, expiresAt, whitelistIps) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("", "api_token_create");
                        apiCall.addArgument("token_name", name);

                        if (expiresAt) {
                            apiCall.addArgument("expires_at", expiresAt);
                        }

                        if (whitelistIps && whitelistIps.length) {
                            whitelistIps.forEach(function(ip, index) {
                                apiCall.addArgument("whitelist_ip-" + index, ip);
                            });
                        }

                        addAclsTo(apiCall, acls);

                        return this.deferred(apiCall).promise
                            .then(function(data) {
                                return data;
                            })
                            .catch(function(error) {
                                return $q.reject(error);
                            });
                    },

                    updateToken: function updateToken(name, newName, acls, expiresAt, whitelistIps) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("", "api_token_update");
                        apiCall.addArgument("token_name", name);
                        if (expiresAt) {
                            apiCall.addArgument("expires_at", expiresAt);
                        }

                        if (whitelistIps && whitelistIps.length) {
                            whitelistIps.forEach(function(ip, index) {
                                apiCall.addArgument("whitelist_ip-" + index, ip);
                            });
                        }

                        if (whitelistIps && !whitelistIps.length) {
                            apiCall.addArgument("whitelist_ip", "any");
                        }

                        if (newName !== name) {
                            apiCall.addArgument("new_name", newName);
                        }

                        addAclsTo(apiCall, acls);

                        return this.deferred(apiCall).promise
                            .then(function(data) {
                                return data;
                            })
                            .catch(function(error) {
                                return $q.reject(error);
                            });
                    },

                    revokeToken: function revokeToken(name) {
                        var apiCall = new APIREQUEST.Class();
                        apiCall.initialize("", "api_token_revoke");
                        if (typeof (name) === "string") {
                            apiCall.addArgument("token_name", name);
                        } else if (Array.isArray(name)) {
                            var i = 0, nameCount = name.length;
                            for (; i < nameCount; i++) {
                                apiCall.addArgument("token_name-" + i, name[i]);
                            }
                        }

                        return this.deferred(apiCall).promise
                            .then(function(data) {
                                return data;
                            })
                            .catch(function(error) {
                                return $q.reject(error);
                            });
                    },

                    getPrivileges: function getPrivileges(force) {
                        if (force || isEmptyObject(userPrivileges)) {

                            var apiCall = new APIREQUEST.Class();
                            apiCall.initialize("", "myprivs");

                            return this.deferred(apiCall).promise
                                .then(function(result) {
                                    var obj = {};
                                    var hasAll = false;

                                    if (result.data) {
                                        obj = result.data[0];

                                        if (obj !== null && typeof obj !== "undefined") {
                                            hasAll = Object.prototype.hasOwnProperty.call(obj, "all") && obj.all === 1;

                                            // Remove the "demo" acl since it is not a real acl
                                            delete obj.demo;

                                            var keys = Object.keys(obj);
                                            for (var i = 0, len = keys.length; i < len; i++) {
                                                if (keys[i] !== "all" && (hasAll || obj[keys[i]] === 1)) {
                                                    userPrivileges[keys[i]] = true;
                                                }
                                            }
                                            if (hasAll) {
                                                userPrivileges["all"] = false;
                                            }
                                        }
                                    }

                                    return userPrivileges;
                                })
                                .catch(function(error) {
                                    return $q.reject(error);
                                });
                        } else {
                            return $q.when(userPrivileges);
                        }
                    },

                    getDetailsFor: function getDetailsFor(tokenName) {
                        return this.getTokens(false)
                            .then(function(data) {
                                if (data !== null &&
                                    typeof data !== "undefined" &&
                                    Object.prototype.hasOwnProperty.call(data, tokenName)) {
                                    if (data[tokenName] && Object.prototype.hasOwnProperty.call(data[tokenName], "acls")) {
                                        var acls = data[tokenName].acls;

                                        // Remove the "demo" acl since it is not a real acl
                                        delete acls.demo;

                                        for (var acl in acls) {
                                            if (Object.prototype.hasOwnProperty.call(acls, acl)) {
                                                acls[acl] = PARSE.parsePerlBoolean(acls[acl]);
                                            }
                                        }
                                    }
                                    return data[tokenName];
                                }

                                return $q.reject(LOCALE.maketext("The [asis,API] token “[_1]” does not exist.", _.escape(tokenName)));
                            });
                    }
                });


                return new TokensService();
            }
            ]);
    });
