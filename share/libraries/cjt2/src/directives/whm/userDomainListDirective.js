/*
# cjt/directives/whm/userDomainList.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false*/

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/templates",
        "ngSanitize",
        "uiBootstrap",
        "cjt/directives/searchDirective",
        "cjt/directives/quickFilterItemDirective",
        "cjt/directives/quickFiltersDirective",
        "cjt/services/whm/userDomainListService",
        "angular-ui-scroll"
    ],
    function(angular, LOCALE, CJT) {
        "use strict";

        var module = angular.module("cjt2.directives.whm.userDomainListDirective", [
            "ui.bootstrap",
            "ngSanitize",
            "cjt2.templates",
            "ui.scroll",
            "cjt2.services.whm.userDomainListService"
        ]);

        var RELATIVE_PATH = "libraries/cjt2/directives/whm/";
        var TEMPLATES_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH;

        module.directive("userDomainList", function() {

            var TEMPLATE = TEMPLATES_PATH + "userDomainListDirective.phtml";

            return {
                templateUrl: TEMPLATE,
                restrict: "E",
                replace: true,
                transclude: true,
                scope: {
                    "domains": "=",
                    "editLockedAccounts": "=",
                    "ngModel": "=",
                    "required": "=?selectionRequired",
                    "parentID": "@id",
                    "onSelect": "&?",
                    "hideAccountSummary": "=?"
                },
                controller: ["$scope", "userDomainListService", "$uibModal", "$filter", function($scope, $service, $uibModal, $filter) {

                    var INFINITY = "\u221e";

                    $scope.items = $scope.domains;
                    $scope.filteredDomains = $scope.domains;
                    $scope.quickFilterValue = "";
                    if (!$scope.editLockedAccounts) {
                        $scope.editLockedAccounts = {};
                    }

                    var stringDictionary = {
                        "Search By:": LOCALE.maketext("Search By:"),
                        "All": LOCALE.maketext("All"),
                        "Users": LOCALE.maketext("Users"),
                        "Domains": LOCALE.maketext("Domains"),
                        "Loading Account Summary …": LOCALE.maketext("Loading Account Summary …"),
                        "[asis,IP] Address": LOCALE.maketext("[asis,IP] Address"),
                        "Owner": LOCALE.maketext("Owner"),
                        "Email Addresses": LOCALE.maketext("Email Addresses"),
                        "Start Date": LOCALE.maketext("Start Date"),
                        "Theme": LOCALE.maketext("Theme"),
                        "Package": LOCALE.maketext("Package"),
                        "Disk Usage": LOCALE.maketext("Disk Usage"),
                        "unknown": LOCALE.maketext("unknown"),
                        "Bandwidth": LOCALE.maketext("Bandwidth"),
                        "CGI Access?": LOCALE.maketext("CGI Access?"),
                        "cPanel Theme": LOCALE.maketext("cPanel Theme"),
                        "Feature List": LOCALE.maketext("Feature List"),
                        "Shell access?": LOCALE.maketext("Shell access?"),
                        "Dedicated IP?": LOCALE.maketext("Dedicated IP?"),
                        "FTP Accounts": LOCALE.maketext("FTP Accounts"),
                        "Email Lists": LOCALE.maketext("Email Lists"),
                        "Email Accounts": LOCALE.maketext("Email Accounts"),
                        "Databases": LOCALE.maketext("Databases"),
                        "Subdomains": LOCALE.maketext("Subdomains"),
                        "Quota": LOCALE.maketext("Quota"),
                        "Search for a user or a domain.": LOCALE.maketext("Search for a user or a domain."),
                        "Search by both users and domains.": LOCALE.maketext("Search by both users and domains."),
                        "Search by users only.": LOCALE.maketext("Search by users only."),
                        "Search by domains only.": LOCALE.maketext("Search by domains only."),
                        "A list of users and domains from which to choose.": LOCALE.maketext("A list of users and domains from which to choose."),
                        "The system failed to load the account summary.": LOCALE.maketext("The system failed to load the account summary.")
                    };

                    $scope.items.forEach(function(domain) {
                        domain.requestingSummary = false;
                        domain.editLocked = $scope.editLockedAccounts[domain.user];
                        if (domain.editLocked) {
                            domain.editLockedMessage = LOCALE.maketext("User Editing Locked:");
                            domain.editLockedMessage += " " + domain.editLocked;
                        }
                        domain.summary = null;
                        domain.summaryTableSummary = LOCALE.maketext("Account Summary for the “[_1]” user.", domain.user);
                    });

                    $scope.meta = {
                        filterValue: ""
                    };

                    $scope.datasource = {
                        get: function(index, count, success) {

                            var result = [];
                            for (var i = index; i <= index + count - 1; i++) {
                                if ($scope.filteredDomains[i]) {
                                    result.push($scope.filteredDomains[i]);
                                }
                            }
                            success(result);

                        }
                    };

                    /**
                     * Get translated string. Wrapper for translation
                     *
                     * @method getString
                     * @param  {String} string string to translate through the locale system
                     * @return {String} translated string from dictionary above
                     */
                    $scope.getString = function(string) {
                        return stringDictionary[string];
                    };

                    /**
                     * Filter the domains based on the filter criteria
                     *
                     * @method _filterDomains
                     * @private
                     * @param  {Object[]} domains All the domains
                     * @return {Object[]} The domains that match the filter rules.
                     */
                    $scope._filterDomains = function(domains) {

                        var filteredDomains = domains;

                        if ($scope.quickFilterValue === "") {
                            var domain, user, email;
                            filteredDomains = $filter("filter")(filteredDomains, function(account) {
                                domain = account.domain || "";
                                user = account.user || "";
                                email = account.email || "";
                                if (domain.indexOf($scope.meta.filterValue) !== -1
                                    || user.indexOf($scope.meta.filterValue) !== -1
                                    || email.indexOf($scope.meta.filterValue) !== -1) {
                                    return true;
                                } else {
                                    return false;
                                }
                            });
                        } else {
                            var filterObj = {};
                            filterObj[$scope.quickFilterValue] = $scope.meta.filterValue;
                            filteredDomains = $filter("filter")(filteredDomains, filterObj);
                        }

                        return filteredDomains;
                    };

                    /**
                     * Attach the domains from $scope.domains to the directive UI
                     *
                     * @method fetch
                     */
                    $scope.fetch = function() {

                        $scope.filteredDomains = [];

                        var newDomains = $scope.domains;

                        // search
                        if ($scope.meta.filterValue) {
                            newDomains = $scope._filterDomains($scope.domains);
                        }

                        newDomains.forEach(function(domain) {
                            domain.decoratedTitle = $scope.getDecoratedTitle(domain);
                        });

                        $scope.filteredDomains = newDomains;

                        if ($scope.uiScrollAdapter && angular.isFunction($scope.uiScrollAdapter.reload)) {
                            $scope.uiScrollAdapter.reload(0);
                        }
                    };

                    /**
                     * Returns the calculated message that new results were found
                     *
                     * @method noResultsMessage
                     * @return {String} returns string when no domains are found, if filterValues or quickFilterValues are set, it generates a descriptive message
                     */
                    $scope.noResultsMessage = function() {
                        if ($scope.meta.filterValue) {
                            if ($scope.quickFilterValue === "user") {
                                return LOCALE.maketext("No results found with a username that match “[_1]”…", $scope.meta.filterValue);
                            } else if ($scope.quickFilterValue === "domain") {
                                return LOCALE.maketext("No results found with a domain that match “[_1]”…", $scope.meta.filterValue);
                            }
                            return LOCALE.maketext("No results found that match “[_1]”…", $scope.meta.filterValue);
                        }
                        return LOCALE.maketext("No results found…");
                    };

                    /**
                     * Function called by view when user is selected
                     *
                     * @method userSelected
                     * @param  {Object} domain domain object of user selected
                     */
                    $scope.userSelected = function(domain) {
                        if (domain.editLocked) {
                            return false;
                        }
                        if (domain && !domain.selected) {
                            $scope.domains.forEach(function(domain) {
                                domain.selected = false;
                            });
                            domain.selected = true;
                            $scope.selectedUser = domain.user;
                            $scope.selectedUserObj = domain;
                            $scope.ngModel = domain;
                            if (!$scope.hideAccountSummary) {
                                $scope.getAccountSummary(domain);
                            }
                        }
                        if (angular.isDefined($scope.onSelect)) {
                            $scope.onSelect({ user: domain.user, domain: domain.domain });
                        }
                    };


                    /**
                     * Wrapper function for $service.getAccountSummary
                     *
                     * @method getAccountSummary
                     * @param  {Object} domain domain object of user to fetch summary for
                     */
                    $scope.getAccountSummary = function(domain) {
                        if (domain.domain) {
                            domain.requestingSummary = true;
                            $service.getAccountSummary(domain.user).then(function(summary) {
                                domain.summary = summary;
                                domain.diskInfo = $scope.getDiskUsage(domain.summary);
                            }).finally( function() {
                                domain.requestingSummary = false;
                            });
                        }
                        else {
                            domain.without_domain = true;
                        }
                    };

                    var LOADING_USER_PACKAGE = {};
                    $scope.loadingUserPackage = LOADING_USER_PACKAGE;

                    /**
                     * Launched Package Details Modal for User
                     *
                     * @method viewPackageDetails
                     * @param  {Object} domain domain object of user to fetch package details for
                     */
                    $scope.viewPackageDetails = function(domain) {

                        LOADING_USER_PACKAGE[domain.user] = true;

                        var domainTitle = $scope.getTitle(domain);

                        var _getString = $scope.getString.bind($scope);

                        $uibModal.open({
                            templateUrl: "package-details.ptt",
                            size: "sm",
                            resolve: {
                                details: $service.getPackageDetails(domain.summary.plan).then(function(pkg) {
                                    domain.packageDetails = pkg;
                                })
                            },
                            controller: ["$scope", function($scope) {
                                $scope.domain = domainTitle;
                                $scope.plan = domain.summary.plan;
                                $scope.packageDetails = domain.packageDetails;
                                $scope.getString = _getString;

                                delete LOADING_USER_PACKAGE[domain.user];

                                $scope.getPackageValue = function(pkg, key) {
                                    if (pkg[key] === "yes" || pkg[key] === 1) {
                                        return LOCALE.maketext("Yes");
                                    } else if (pkg[key] === "no" || pkg[key] === 0) {
                                        return LOCALE.maketext("No");
                                    } else if (pkg[key] === null) {
                                        return INFINITY;
                                    } else {
                                        return pkg[key];
                                    }
                                };
                                $scope.getTitle = function() {
                                    return LOCALE.maketext("Package “[_1]” for user “[_2]”", $scope.plan, $scope.domain);
                                };
                            }]
                        });

                    };

                    /**
                     * Get Calculated title for a user
                     *
                     * @method getTitle
                     *
                     * @param  {Object} domain domain object of user to calculate title for
                     * @return {String} calculated title from domain object
                     */
                    $scope.getTitle = function(domain) {
                        if (!domain) {
                            return "";
                        }
                        if (domain.domain && domain.domain.length > 0) {
                            return domain.user + " (" + domain.domain + ")";
                        }
                        return domain.user;
                    };

                    /**
                     * Decorates the title against the matching filter values
                     *
                     * @method getDecoratedTitle
                     * @param  {Object} domain domain object of user to decorate title for
                     * @return {String} html string of decorated title
                     */
                    $scope.getDecoratedTitle = function(domain) {

                        if (!$scope.meta.filterValue) {
                            return $scope.getTitle(domain);
                        }

                        function _makeStrong(str) {
                            return str.replace($scope.meta.filterValue, "<strong>" + $scope.meta.filterValue + "</strong>");
                        }

                        var decoratedTitle = "";
                        if ($scope.quickFilterValue === "user") {
                            decoratedTitle += decoratedTitle += _makeStrong(domain.user);
                            if (domain.domain && domain.domain.length > 0) {
                                decoratedTitle += " (";
                                decoratedTitle += _makeStrong(domain.domain);
                                decoratedTitle += ")";
                            }
                        } else if ($scope.quickFilterValue === "domain") {
                            decoratedTitle += domain.user;
                            if (domain.domain && domain.domain.length > 0) {
                                decoratedTitle += " (";
                                decoratedTitle += _makeStrong(domain.domain);
                                decoratedTitle += ")";
                            }
                        } else {
                            decoratedTitle += _makeStrong($scope.getTitle(domain));
                        }
                        return decoratedTitle;

                    };

                    /**
                     * Get disk usage based on summary
                     *
                     * @method getDiskUsage
                     * @param  {Object} summary Summary object to calculate disk used string from
                     * @return {String} calculated disk used string "1000 / 1000"
                     */
                    $scope.getDiskUsage = function(summary) {
                        if (summary.disklimit === "unlimited") {
                            return summary.diskused + " / " + INFINITY;
                        }
                        return summary.diskused + " / " + summary.disklimit;
                    };

                    /**
                     * Build a useful aria label for radio buttons
                     *
                     * @method getRadioAriaLabel
                     * @param  {String} user username to build string against
                     * @param  {String} domain domain to build string against
                     * @return {String} Translated string for radio button  "Select user “[_1]” and domain ”[_2]”.
                     */
                    $scope.getRadioAriaLabel = function(user, domain) {
                        if (!user && !domain) {
                            return LOCALE.maketext("Select this user.");
                        }
                        if (user && !domain) {
                            return LOCALE.maketext("Select the “[_1]” user.", user);
                        }
                        return LOCALE.maketext("Select the “[_1]” user and the ”[_2]” domain.", user, domain);
                    };

                    $scope.fetch();

                }],
            };
        });

    }
);
