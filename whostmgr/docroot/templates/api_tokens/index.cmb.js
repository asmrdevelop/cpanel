/*
# cpanel - whostmgr/docroot/templates/api_tokens/services/api_tokens.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/services/api_tokens',[
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

// Copyright 2022 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

function ipv6short(input) {
    "use strict";

    // remove all zeros to the right
    input = input.replace(/^(0{4}:)+/g, "::");

    // remove all zeros to the left
    input = input.replace(/(?::?0{4})+(\/\d+)?$/g, "::$1");

    // remove all leading zeros
    input = input.replace(/(:|^)(0{1,3})(?=[^0])/g, "$1");

    // find the longest group of continuous empty 16-bit hexets if string doesn't alreay contain ::
    if (input.match("::") === null) {
        var matches = input.match(/(:0{4})+/g);
        if (!matches) {
            return input;
        }
        var match = matches.reduce((a, b) => a.length > b.length ? a : b);
        input = input.replace(match, ":");
    }

    // replace remaning empty 16-bit hexets with a single 0
    return input.replace(/(?!:)(0{4})/g, "0");
}

define(
    'app/filters',[
        "angular",
    ],
    function(angular) {
        "use strict";
        var module = angular.module("whm.apiTokens.filters", []);
        module.filter("ipv6short", function() {
            return ipv6short;
        });

        return module;
    });

/*
# cpanel - whostmgr/docroot/templates/api_tokens/views/home.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/


define(
    'app/views/home',[
        "angular",
        "cjt/util/locale",
        "cjt/util/table",
        "uiBootstrap",
        "cjt/decorators/growlDecorator",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/directives/alertList",
        "cjt/directives/toggleSortDirective",
        "cjt/services/viewNavigationApi",
        "cjt/directives/autoFocus",
    ],
    function(angular, LOCALE, Table) {
        "use strict";
        var app = angular.module("whm.apiTokens");

        var controller = app.controller(
            "homeController",
            ["$q", "growl", "Tokens", "$uibModal", "viewNavigationApi", "PAGE",
                function($q, growl, Tokens, $uibModal, viewNavigationApi, PAGE) {
                    var home = this;

                    home.loading = false;
                    home.showFormToggleBtn = true;
                    home.tokenAdded = false;
                    home.loadingError = false;
                    home.loadingErrorMessage = "";
                    home.allChecked = false;
                    home.checkedCount = 0;
                    home.paginationMessage = "";
                    home.showChildAccountsExistWarning = PAGE.childAccountsExist;
                    home.childAccountsExistWarning = "";
                    home.childAccountsExistWarning += LOCALE.maketext("There are accounts on this server controlled by a parent node.");
                    home.childAccountsExistWarning += " ";
                    home.childAccountsExistWarning += LOCALE.maketext("Do not delete [asis,API] tokens a parent node uses to communicate with this server.");

                    function searchByName(item, searchText) {
                        return item.name.toLowerCase().indexOf(searchText.toLowerCase()) !== -1;
                    }

                    var table = new Table();
                    table.setSearchFunction(searchByName);
                    table.setSort("create_time,name", "desc");
                    home.meta = table.getMetadata();
                    home.filteredList = table.getList();
                    home.allTokens = [];
                    home.render = function() {
                        home.resetCheckAll();
                        home.filteredList = table.update();
                        home.paginationMessage = table.paginationMessage();
                    };
                    home.sortList = function() {
                        home.render();
                    };
                    home.selectPage = function() {
                        home.render();
                    };
                    home.selectPageSize = function() {
                        home.render();
                    };
                    home.searchList = function() {
                        home.render();
                    };

                    home.resetCheckAll = function() {
                        home.allChecked = false;
                        home.toggleCheckAll();
                        home.checkedCount = 0;
                    };

                    home.getIndeterminateState = function() {
                        return home.checkedCount > 0 && !home.allChecked;
                    };

                    home.toggleCheckAll = function() {
                        if (home.filteredList.length === 0) {
                            return;
                        }
                        var i = 0, listLength = home.filteredList.length;
                        for (i; i < listLength; i++) {
                            home.filteredList[i].checked = home.allChecked;
                        }
                        if (home.allChecked) {
                            home.checkedCount = listLength;
                        } else {
                            home.checkedCount = 0;
                        }
                    };

                    home.syncCheckAll = function(listItem) {
                        if (listItem.checked) {
                            home.checkedCount++;
                        } else {
                            home.checkedCount--;
                        }
                        home.allChecked = home.checkedCount === home.filteredList.length;
                    };

                    home.checkAll = function() {
                        home.allChecked = true;
                        home.toggleCheckAll();
                    };

                    home.editToken = function(token) {
                        if (token === void 0) {
                            viewNavigationApi.loadView("/edit");
                        } else {
                            viewNavigationApi.loadView("/edit/" + token.name);
                        }
                    };

                    home.getSelectedTokens = function() {
                        var selectedTokens = [];
                        for (var i = 0; i < home.filteredList.length; i++) {
                            if (home.filteredList[i].checked) {
                                selectedTokens.push(home.filteredList[i]);
                            }
                        }

                        return selectedTokens;
                    };

                    home.getHumanReadableTime = function(epochTime) {
                        return LOCALE.local_datetime(epochTime, "datetime_format_medium");
                    };

                    function RevokeTokenModalController($uibModalInstance, token) {
                        var ctrl = this;
                        var tokenCount = 0;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };

                        ctrl.buildTokenNameList = function() {
                            tokenCount = token.length;
                            var i = 0, tokensToDelete = [];

                            for (i = 0; i < tokenCount; i++) {
                                tokensToDelete.push(token[i].name);
                            }

                            return tokensToDelete;
                        };

                        var revokeParam;

                        if (Array.isArray(token) && token.length === home.allTokens.length) {
                            ctrl.prompt = LOCALE.maketext("Are you certain that you want to revoke all of your [asis,API] tokens?" );
                            revokeParam = ctrl.buildTokenNameList();
                        } else if (Array.isArray(token)) {
                            ctrl.prompt = LOCALE.maketext("Are you certain that you want to revoke [numf,_1] [asis,API] [numerate,_1,token,tokens]?", token.length);
                            revokeParam = ctrl.buildTokenNameList();
                        } else {
                            ctrl.prompt = LOCALE.maketext("Are you certain that you want to revoke the [asis,API] token, “[_1]”?", token.name);
                            revokeParam = token.name;
                        }

                        ctrl.confirm = function() {
                            return Tokens.revokeToken(revokeParam)
                                .then(function() {
                                    if (Array.isArray(token)) {
                                        if (token.length === home.allTokens.length) {
                                            growl.success(LOCALE.maketext("You successfully revoked all of your [asis,API] tokens."));
                                            table.clear();
                                            home.allTokens = [];
                                        } else {
                                            growl.success(LOCALE.maketext("You successfully revoked [numf,_1] [asis,API] [numerate,_1,token,tokens].", token.length));
                                            for (var i = 0; i < tokenCount; i++) {
                                                table.remove(token[i]);
                                            }
                                        }
                                    } else {
                                        growl.success(LOCALE.maketext("You successfully revoked the [asis,API] token “[_1]”.", token.name));
                                        table.remove(token);
                                    }

                                    home.render();
                                })
                                .catch(function(error) {
                                    growl.error(error);
                                })
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                    }

                    RevokeTokenModalController.$inject = ["$uibModalInstance", "token"];

                    home.confirmRevokeToken = function(token) {
                        $uibModal.open({
                            templateUrl: "confirm_token_revocation.html",
                            controller: RevokeTokenModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                token: function() {
                                    return token;
                                },
                            },
                        });
                    };

                    home.refreshList = function() {
                        home.filteredList = [];
                        home.allTokens = [];
                        return load();
                    };

                    function load() {
                        home.loading = true;

                        var _currentDateTime = new Date();
                        _currentDateTime = _currentDateTime.getTime() / 1000;

                        var _twentyFourHours = 24 * 60 * 60;

                        // In addition to getting the list of api tokens, we want to fetch the
                        // privileges for the user now to cache them for when the user will
                        // need to create a token. This helps avoid showing a spinner on the
                        // create view.
                        return $q.all([
                            Tokens.getTokens(true),
                            Tokens.getPrivileges(true)])
                            .then(function(data) {
                                var tableData = [];
                                var tokenData = data[0];
                                if (tokenData !== null && typeof tokenData !== "undefined") {
                                    for (var tokenName in tokenData) {
                                        if (tokenData.hasOwnProperty(tokenName)) {
                                            tokenData[tokenName].checked = false;
                                            tokenData[tokenName].create_time_friendly = LOCALE.local_datetime(tokenData[tokenName].create_time, "datetime_format_medium");
                                            tokenData[tokenName].expiresAtFriendly = "";
                                            if (tokenData[tokenName].expires_at) {

                                                var expiresAt = parseInt(tokenData[tokenName].expires_at, 10);

                                                if (expiresAt <= _currentDateTime) {
                                                    tokenData[tokenName].expired = true;
                                                } else if (expiresAt - _currentDateTime < _twentyFourHours) {
                                                    tokenData[tokenName].expiresSoon = true;
                                                }

                                                tokenData[tokenName].expiresAtFriendly = LOCALE.local_datetime(tokenData[tokenName].expires_at, "datetime_format_medium");
                                            }
                                            tableData.push(tokenData[tokenName]);
                                        }
                                    }
                                    table.load(tableData);
                                    home.allTokens = tableData;
                                    home.render();
                                }
                            })
                            .catch(function(error) {
                                home.loadingError = true;
                                home.loadingErrorMessage = error;
                            })
                            .finally(function() {
                                home.loading = false;
                            });
                    }

                    function init() {
                        load();
                    }

                    init();
                },
            ]);

        return controller;
    }
);

/*
# cpanel - whostmgr/docroot/templates/api_tokens/views/edit.js
#                                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/views/edit',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/validator/ip-validators",
        "cjt/validator/validator-utils",
        "cjt/util/table",
        "uiBootstrap",
        "cjt/decorators/growlDecorator",
        "cjt/directives/alertList",
        "cjt/directives/autoFocus",
        "cjt/directives/triStateCheckbox",
        "cjt/directives/timePicker",
        "cjt/directives/datePicker",
        "cjt/services/viewNavigationApi",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
    ],
    function(angular, _, LOCALE, PARSE, VALIDATORS, UTILS) {
        "use strict";

        /**
         * Parse the text block into a list of IPv4 and CIDR items. These can
         * be separated by a \n, \r\n, a comma, or a sequence of 1 or more
         * whitespaces. Excess leading and trailing whitespace is removed from
         * each item and blank entries are removed from the list.
         *
         * @param {string} txtIps
         * @returns {string[]}
         */
        function parseIps(txtIps) {
            if (!txtIps) {
                return [];
            }
            var ips = txtIps.split(/\r?\n|,|\s+/);
            return ips.map(function(ip) {
                return _.trim(ip);
            }).filter(function(ip) {
                return !!ip;
            });
        }

        /**
         * Try to guess the IP version based on group separator
         * defaults to ipv4 if ipv6 checks fail
         *
         * @param {string} ip - any string.
         * @returns {string} - ip version.
         */
        function guessIpVersion(ip) {

            if (/:/.test(ip)) {
                return "ipv6";
            }

            return "ipv4";
        }

        /**
         * Validate ipv6 address and the prefix length of ipv6 range
         *
         * @param {string} ipOrCidr - ipv6 range specified in CIDR notation.
         * @returns {ValidationResult}
         */
        function cidr6(str) {
            var cidr = str.split("/");
            var range = cidr[1], address = cidr[0];

            var result = VALIDATORS.methods.ipv6(address);

            if (!range) {
                result.isValid = false;
                result.add("cidr", LOCALE.maketext("The [asis,IP] address prefix must include a ‘/’ followed by the prefix length."));
            }

            if (range < 1 || range > 128 || !range) {
                result.isValid = false;
                result.add("cidr", LOCALE.maketext("You must specify a valid prefix length between 1 and 128."));
            }

            return result;
        }

        /**
         * Validate the string is either a valid IPv4 address or
         * that it is a valid CIDR address range.
         *
         * @param {string} ipOrCidr - an unvalidated string from the ui.
         * @returns {ValidationResult}
         */
        function validateIp(ipOrCidr) {
            var result;
            var ipversion = guessIpVersion(ipOrCidr);
            if (/[/]/.test(ipOrCidr)) {
                result = ipversion === "ipv4" ? VALIDATORS.methods.cidr4(ipOrCidr) : cidr6(ipOrCidr);
                if (!result.isValid) {
                    if (result.lookup["cidr"]) {
                        result.lookup["cidr"].message = ipOrCidr + " - " + result.lookup["cidr"].message;
                    } else {
                        if (result.lookup["cidr-details"]) {
                            result.lookup["cidr-details"].message = ipOrCidr + " - " + result.lookup["cidr-details"].message;
                        }
                    }

                    // Handle cases where an invalid ipv4 address is used along with a CIDR range
                    if (result.lookup[ipversion]) {
                        result.lookup[ipversion].message = ipOrCidr + " - " + result.lookup[ipversion].message;
                    }
                }
            } else {
                result = ipversion === "ipv4" ? VALIDATORS.methods.ipv4(ipOrCidr) : VALIDATORS.methods.ipv6(ipOrCidr);
                if (!result.isValid) {
                    result.lookup[ipversion].message = ipOrCidr + " - " + result.lookup[ipversion].message;
                }
            }
            return result;
        }

        var app = angular.module("whm.apiTokens");

        /**
         * Add a custom parser and validator for a list of IPv4 addresses
         * or CIDR ranges.
         */
        app.directive("ipv4OrCidr4List", function() {
            return {
                restrict: "A",
                require: "ngModel",
                link: function(scope, elem, attr, ctrl) {
                    var form = elem.controller("form");
                    UTILS.initializeExtendedReporting(ctrl, form);

                    ctrl.$parsers.push(function(value) {
                        return parseIps(value);
                    });

                    ctrl.$formatters.push(function(value) {
                        return value.join("\r\n");
                    });

                    ctrl.$isEmpty = function(value) {
                        return angular.isUndefined(value) || value === "" || value === null || value !== value || value.length && value.length === 0;
                    };

                    ctrl.$validators.ipv4OrCidr4 = function(modelValue, viewValue) {

                        // Adapter to support multiple flags in a validator
                        ["ipv6", "ipv4", "cidr", "cidr-details", "size-exceeded"].forEach(function(key) {
                            delete ctrl.$error[key];
                        });
                        ctrl.$error_details.clear();

                        if (ctrl.$isEmpty(modelValue)) {

                            // consider empty models to be valid
                            return true;
                        }

                        if (modelValue.length > 100) {
                            var sizeResult = UTILS.initializeValidationResult();
                            sizeResult.isValid = false;
                            sizeResult.add("size-exceeded", LOCALE.maketext("You have exceeded the limit of 100 whitelisted [asis,IP] addresses per token."));
                            ctrl.$error["size-exceeded"] = true;
                            UTILS.updateExtendedReportingList(ctrl, form, ["size-exceeded"], sizeResult);
                            return false;
                        }

                        // Perform progressive validation, rather the all at the same time
                        for (var i = 0, l = modelValue.length; i < l; i++) {
                            var ipOrCidr = modelValue[i];
                            var result = validateIp(ipOrCidr);
                            if (!result.isValid) {

                                var possibleErrors = ["ipv6", "ipv4", "cidr", "cidr-details"];

                                // Package the additional error messages into the collections
                                possibleErrors.forEach(function(key) {
                                    var isError = result.lookup[key] ? true : false;
                                    if (isError) {
                                        ctrl.$error[key] = true;
                                    } else {
                                        delete ctrl.$error[key];
                                    }
                                });
                                UTILS.updateExtendedReportingList(ctrl, form, possibleErrors, result);
                                return false;
                            }
                        }

                        // it is valid if all the individual items are valid
                        return true;
                    };

                    scope.$watch(attr.ngModel,
                        function(newVal) {
                            ctrl.$validate();
                        }
                    );
                },
            };
        });

        var controller = app.controller(
            "editController",
            ["$routeParams", "growl", "Tokens", "viewNavigationApi", "PAGE", "growlMessages",
                function($routeParams, growl, Tokens, viewNavigationApi, PAGE, growlMessages) {
                    var edit = this;

                    var minDate = new Date();
                    minDate.setHours(0);
                    minDate.setMinutes(0);
                    minDate.setSeconds(0, 0);

                    edit.datePickerOptions = {
                        minDate: minDate,
                    };

                    edit.timePickerOptions = {
                        min: minDate,
                    };
                    edit.stringify = function(obj) {
                        return JSON.stringify(obj, undefined, 2);
                    };
                    var defaultExpiresDate = new Date(minDate.getTime());
                    defaultExpiresDate.setHours(23);
                    defaultExpiresDate.setMinutes(59);
                    defaultExpiresDate.setSeconds(59, 999);
                    defaultExpiresDate.setFullYear(defaultExpiresDate.getFullYear() + 1);

                    edit.loading = false;
                    edit.loadingError = false;
                    edit.loadingErrorMessage = "";

                    edit.showExtraHelp = false;
                    edit.onToggleHelp = function() {
                        edit.showExtraHelp = !edit.showExtraHelp;
                    };

                    edit.tokenAdded = false;
                    edit.editingToken = false;
                    edit.hasPrivs = false;
                    edit.availableAcls = {};
                    edit.aclsToEdit = [];
                    edit.aclsToSend = {};

                    edit.newToken = {
                        name: "",
                        originalName: "",
                        token: "",
                        acls: [],
                        tokenExpires: false,
                        expiresAt: defaultExpiresDate,
                        whitelistIps: [],
                    };

                    var isDnsOnly = PARSE.parsePerlBoolean(PAGE.is_dns_only);

                    edit.aclWarningVisible = function(acl) {
                        if (acl.name === "all") {
                            return true;
                        }
                        if (!Object.prototype.hasOwnProperty.call(acl, "is_warning_visible")) {
                            acl.is_warning_visible = false;
                        }
                        return acl.is_warning_visible;
                    };

                    edit.toggleAclWarning = function(acl) {
                        if (!Object.prototype.hasOwnProperty.call(acl, "is_warning_visible")) {
                            acl.is_warning_visible = true;
                        } else {
                            acl.is_warning_visible = !acl.is_warning_visible;
                        }
                    };

                    edit.handleWarningIconKey = function(acl, event) {
                        if (event.type !== "keypress") {
                            return;
                        }
                        if (event.charCode === 32 || event.charCode === 13) {
                            edit.toggleAclWarning(acl);
                            event.preventDefault();
                        }
                    };

                    edit.toggleAcl = function(acl) {

                        var isRootSelected = edit.aclsToSend["all"] && acl.name !== "all";
                        var areWeSelectingRoot = acl.name === "all" && acl.selected;

                        if (acl.selected) {
                            edit.aclsToSend[acl.name] = true;
                        } else {
                            delete edit.aclsToSend[acl.name];
                        }

                        if (isRootSelected && !acl.selected) {
                            edit.removeAllToken();
                        }

                        if (areWeSelectingRoot) {

                            // select all the subcatgories except for the root subcategory
                            edit.selectAllSubcategories("Everything");
                        }
                    };

                    edit.updateAclsToSend = function(subcategory) {
                        for (var i = 0, len = subcategory.acls.length; i < len; i++) {
                            edit.toggleAcl(subcategory.acls[i]);
                        }
                    };

                    /**
                     * Select all Privileges on the interface and update the data storage we
                     * use to send privileges when we trigger the "save" call.
                     *
                     * @param except {String} - a subcategory that we do not want to select
                     */
                    edit.selectAllSubcategories = function(except) {
                        var subcategories = edit.aclsToEdit;
                        for (var i = 0, len = subcategories.length; i < len; i++) {
                            if (subcategories[i].title === except) {
                                continue;
                            }
                            for (var j = 0, aclLen = subcategories[i].acls.length; j < aclLen; j++) {
                                subcategories[i].acls[j].selected = true;
                                edit.aclsToSend[subcategories[i].acls[j].name] = true;
                            }
                        }
                    };

                    edit.hasSelectedPrivs = function() {
                        return edit.hasPrivs && Object.keys(edit.aclsToSend).length > 0;
                    };

                    edit.disableSave = function(form) {
                        return (edit.newToken.tokenExpires && edit.datePickerOptions.minDate > edit.newToken.expiresAt) || (form.$pristine || form.$invalid || !edit.hasSelectedPrivs());
                    };

                    edit.dateValidator = function(input) {
                        if (edit.newToken.tokenExpires && edit.newToken.expiresAt) {
                            edit.newToken.expiresAt.setHours(23);
                            edit.newToken.expiresAt.setMinutes(59);
                            edit.newToken.expiresAt.setSeconds(59, 999);
                        }

                        if (edit.newToken.tokenExpires && edit.datePickerOptions.minDate > edit.newToken.expiresAt) {
                            input.$invalid = true;
                            input.$valid = false;
                        }
                    };

                    edit.resetDate = function() {
                        if (edit.newToken.tokenExpires) {
                            edit.newToken.expiresAt = defaultExpiresDate;
                        }
                    };

                    edit.goHome = function() {
                        viewNavigationApi.loadView("/home");
                    };

                    edit.newTokenExpiresMessage = function newTokenExpiresMessage(token) {
                        var expirationDate = LOCALE.local_datetime(token.expiresAt, "datetime_format_medium");
                        return LOCALE.maketext("This [asis,API] token will expire on [_1][comment,Bareword is a date].", expirationDate);
                    };

                    edit.minimumIpRows = function() {
                        return this.newToken.whitelistIps.length ? this.newToken.whitelistIps.length : 4;
                    };

                    edit.saveToken = function(form) {
                        if (form.$invalid) {
                            return;
                        }

                        edit.newToken.acls = Object.keys(edit.aclsToSend);

                        if ( edit.newToken.tokenExpires ) {
                            edit.newToken.expiresAt.setHours(23);
                            edit.newToken.expiresAt.setMinutes(59);
                            edit.newToken.expiresAt.setSeconds(59, 999);
                        }

                        var expiresAt = edit.newToken.tokenExpires ? Math.floor(edit.newToken.expiresAt / 1000) : "0";

                        growlMessages.destroyAllMessages();
                        if (edit.editingToken) {
                            return Tokens.updateToken(edit.newToken.originalName, edit.newToken.name, edit.newToken.acls, expiresAt, edit.newToken.whitelistIps)
                                .then(function success(results) {
                                    growl.success(LOCALE.maketext("You successfully updated the [asis,API] token, “[_1]”.", results.data.name));
                                    viewNavigationApi.loadView("/home");
                                })
                                .catch(function error(data) {
                                    growl.error(_.escape(data));
                                });

                        } else {
                            return Tokens.createToken(edit.newToken.name, edit.newToken.acls, expiresAt, edit.newToken.whitelistIps)
                                .then(function success(results) {

                                    // notify the user of the new token
                                    edit.newToken.token = results.data.token;
                                    edit.tokenAdded = true;
                                })
                                .catch(function error(data) {
                                    growl.error(_.escape(data));
                                });
                        }
                    };

                    edit.getAvailableAcls = function() {
                        return Tokens.getPrivileges(false)
                            .then(function success(results) {
                                if (results !== null && typeof results !== "undefined" ) {
                                    edit.availableAcls = results;
                                }
                            })
                            .catch(function error(data) {
                                growl.error(_.escape(data));
                            });
                    };

                    edit.removeAllToken = function() {
                        var allSubcategory = edit.aclsToEdit[edit.aclsToEdit.length - 1];
                        allSubcategory.acls[0].selected = false;
                        delete edit.aclsToSend.all;
                        growl.info(LOCALE.maketext("The system deselected the “all” privilege."));
                    };

                    /**
                     * Create a data structure that is easy to deal with from the interface
                     * Should create the following data structure
                     * [
                     *   {
                     *     "categoryName": "standardprivileges",
                     *     "categoryTitle": "Standard Privileges",
                     *     "name": "accountinformation",
                     *     "title": "Account Information",
                     *     "selected": true,
                     *     "acls": [
                     *       {
                     *         "name": "list-accts",
                     *         "title": "List Accounts",
                     *         "selected": true
                     *       }
                     *     ]
                     *   }
                     * ]
                     * @param {Object} selectedPrivs - contains the privileges
                     * should appear in the interface and be selected.
                     * @return {Array} the data structure mapped out above
                     */
                    function prepareAclsForEdit(selectedPrivs) {
                        var formattedAcls = [];
                        var category = {};
                        var subcategory = {};
                        var acl = {};
                        var availabeAclsInSubcategory = 0;

                        selectedPrivs = (typeof selectedPrivs === "undefined") ? {} : selectedPrivs;

                        for (var i = 0, len = PAGE.ordered_categories.length; i < len; i++) {

                            // the additional software group may not have any entries, so check for definedness first
                            if (typeof PAGE.categories_metadata[PAGE.ordered_categories[i]].ordered_subcategories !== "undefined") {
                                category = {
                                    orderedSubcategories: PAGE.categories_metadata[PAGE.ordered_categories[i]].ordered_subcategories,
                                    name: PAGE.ordered_categories[i],
                                    title: PAGE.categories_metadata[PAGE.ordered_categories[i]].title,
                                };

                                for (var j = 0, jlen = category.orderedSubcategories.length; j < jlen; j++) {
                                    subcategory = {
                                        title: PAGE.subcategories_metadata[category.orderedSubcategories[j]].title,
                                        orderedAcls: PAGE.subcategories_metadata[category.orderedSubcategories[j]].ordered_acls,
                                        categoryTitle: category.title,
                                        categoryName: category.name,
                                        name: category.orderedSubcategories[j],
                                        acls: [],
                                    };
                                    availabeAclsInSubcategory = 0;

                                    for (var k = 0, klen = subcategory.orderedAcls.length, enabledCount = 0; k < klen; k++) {
                                        if (!Object.prototype.hasOwnProperty.call(selectedPrivs, subcategory.orderedAcls[k])) {
                                            continue;
                                        }
                                        if (isDnsOnly && (!PAGE.acl_metadata[subcategory.orderedAcls[k]] || !PAGE.acl_metadata[subcategory.orderedAcls[k]].dnsonly)) {
                                            continue;
                                        }
                                        availabeAclsInSubcategory++;

                                        acl = {
                                            name: subcategory.orderedAcls[k],
                                            title: PAGE.acl_metadata[subcategory.orderedAcls[k]].title,
                                        };

                                        if (PAGE.acl_metadata[subcategory.orderedAcls[k]].description) {
                                            acl.description = PAGE.acl_metadata[subcategory.orderedAcls[k]].description;
                                            acl.description_is_warning = PAGE.acl_metadata[subcategory.orderedAcls[k]].description_is_warning ? true : false;
                                        }

                                        if (selectedPrivs[acl.name]) {
                                            acl.selected = true;
                                            enabledCount++;
                                        } else {
                                            acl.selected = false;
                                        }
                                        subcategory.acls.push(acl);
                                    }

                                    subcategory.orderedAcls = void 0;
                                    subcategory.selected = (enabledCount === availabeAclsInSubcategory) ? true : false;
                                    if (availabeAclsInSubcategory > 0) {
                                        formattedAcls.push(subcategory);
                                    }
                                }
                            }
                        }
                        return formattedAcls;
                    }

                    function init() {
                        edit.loading = true;

                        var _currentDateTime = new Date();
                        _currentDateTime = _currentDateTime.getTime() / 1000;

                        var _twentyFourHours = 24 * 60 * 60;

                        if (Object.prototype.hasOwnProperty.call($routeParams, "name")) {
                            return Tokens.getDetailsFor($routeParams.name)
                                .then(function(results) {
                                    edit.newToken.name = $routeParams.name;
                                    edit.newToken.originalName = $routeParams.name;
                                    edit.editingToken = true;

                                    edit.newToken.expiresAtFriendly = "";
                                    if (results.expires_at) {
                                        edit.newToken.expiresAt = new Date(results.expires_at * 1000);
                                        edit.newToken.tokenExpires = true;

                                        var expiresAt = parseInt(results.expires_at, 10);

                                        if (expiresAt <= _currentDateTime) {
                                            edit.newToken.expired = true;
                                        } else if (expiresAt - _currentDateTime < _twentyFourHours) {
                                            edit.newToken.expiresSoon = true;
                                        }

                                        edit.newToken.expiresAtFriendly = LOCALE.local_datetime(expiresAt, "datetime_format_medium");
                                    }

                                    edit.newToken.whitelistIps = results.whitelist_ips || [];

                                    for (var acl in results.acls) {
                                        if (results.acls[acl]) {
                                            if (isDnsOnly && (!PAGE.acl_metadata[acl] || !PAGE.acl_metadata[acl].dnsonly)) {
                                                continue;
                                            }
                                            edit.aclsToSend[acl] = true;
                                        }
                                    }
                                    edit.aclsToEdit = prepareAclsForEdit(results.acls);
                                    edit.hasPrivs = edit.aclsToEdit.length > 0;
                                })
                                .catch(function(error) {
                                    edit.loadingError = true;
                                    edit.loadingErrorMessage = error;
                                })
                                .finally(function() {
                                    edit.loading = false;
                                });

                        } else {
                            return Tokens.getPrivileges(false)
                                .then(function(results) {
                                    if (results !== null && typeof results !== "undefined" ) {
                                        for (var acl in results) {
                                            if (results[acl]) {
                                                if (isDnsOnly && !PAGE.acl_metadata[acl].dnsonly) {
                                                    continue;
                                                }
                                                edit.aclsToSend[acl] = true;
                                            }
                                        }

                                        edit.aclsToEdit = prepareAclsForEdit(results);
                                        edit.hasPrivs = edit.aclsToEdit.length > 0;
                                    }
                                })
                                .catch(function(error) {
                                    edit.loadingError = true;
                                    edit.loadingErrorMessage = error;
                                })
                                .finally(function() {
                                    edit.loading = false;
                                });
                        }
                    }

                    init();
                },
            ]);

        return controller;
    }
);

/*
# cpanel - whostmgr/docroot/templates/api_tokens/index.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require: false, define: false */

define(
    'app/index',[
        "angular",
        "jquery",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "ngAnimate",
        "ngAria",
        "uiBootstrap",
        "app/services/api_tokens",
        "app/filters",
    ],
    function(angular) {
        "use strict";

        return function() {
            angular.module("whm.apiTokens", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ngAnimate",
                "ngAria",
                "ui.bootstrap",
                "angular-growl",
                "cjt2.whm",
                "whm.apiTokens.apiCallService",
                "whm.apiTokens.filters",
            ]);
            var app = require(
                [
                    "cjt/bootstrap",
                    "app/views/home",
                    "app/views/edit",
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.apiTokens");
                    app.value("PAGE", PAGE);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {
                            $routeProvider.when("/home", {
                                controller: "homeController",
                                controllerAs: "home",
                                templateUrl: "api_tokens/views/home.ptt",
                            });

                            $routeProvider.when("/edit/:name?", {
                                controller: "editController",
                                controllerAs: "edit",
                                templateUrl: "api_tokens/views/edit.ptt",
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/home",
                            });
                        },
                    ]);

                    BOOTSTRAP(document, "whm.apiTokens");

                });

            return app;
        };
    }
);

