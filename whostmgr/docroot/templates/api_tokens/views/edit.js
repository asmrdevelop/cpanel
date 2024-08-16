/*
# cpanel - whostmgr/docroot/templates/api_tokens/views/edit.js
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
