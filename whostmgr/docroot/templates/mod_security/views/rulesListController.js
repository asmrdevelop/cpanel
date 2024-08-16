/*
# mod_security/views/rulelistController.js        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/logic",
        "uiBootstrap",
        "cjt/directives/responsiveSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/filters/splitFilter",
        "cjt/filters/htmlFilter",
        "cjt/directives/spinnerDirective",
        "cjt/directives/actionButtonDirective",
        "cjt/services/alertService",
        "app/services/ruleService",
        "app/services/vendorService",
        "cjt/io/whm-v1-querystring-service",
    ],
    function(angular, _, LOCALE, LOGIC) {
        "use strict";

        var USER_CONFIG = "modsec2.user.conf"; /* TODO: EA-4700 */

        var STATUS_ENUM = {
            ENABLED: "enabled",
            DISABLED: "disabled",
            BOTH: "both",
        };

        var PUBLISHED_ENUM = {
            DEPLOYED: "deployed",
            STAGED: "staged",
            BOTH: "both",
        };

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "rulesListController", [
                "$scope",
                "$location",
                "$anchorScroll",
                "$timeout",
                "ruleService",
                "vendorService",
                "alertService",
                "spinnerAPI",
                "queryService",
                "PAGE",
                function(
                    $scope,
                    $location,
                    $anchorScroll,
                    $timeout,
                    ruleService,
                    vendorService,
                    alertService,
                    spinnerAPI,
                    queryService,
                    PAGE) {

                    $scope.loadingPageData = true;
                    $scope.activeSearch = false;
                    $scope.filteredData = false;
                    $scope.advancedSearchApplied = false;

                    /**
                         * Update the advanced search applied flag by checking if the advanced search flags are
                         * in their default state or not.
                         *
                         * @private
                         * @method _updateAdvancedSearchApplied
                         * @return {Boolean} true if there is an advanced search, false otherwise
                         */
                    function _updateAdvancedSearchApplied() {

                        // See if we have an advanced search different from the default
                        if ($scope.meta.advanced.includeUserRules !== true ||
                                $scope.meta.advanced.showEnabledDisabled !== STATUS_ENUM.BOTH ||
                                $scope.meta.advanced.showStagedDeployed !== PUBLISHED_ENUM.BOTH) {
                            $scope.advancedSearchApplied = true;
                        } else {
                            $scope.advancedSearchApplied = false;
                        }

                        // Also update the indicator at this point.
                        $scope.appliedIncludeUserRules = $scope.meta.advanced.includeUserRules;
                    }

                    /**
                         * Update the previous state information for rollback should the fetch fail.
                         * @private
                         * @method _updatePreviousState
                         */
                    function _updatePreviousState() {
                        $scope.previouslySelected = $scope.selectedVendors;
                        $scope.meta.advanced.previousShowStagedDeployed = $scope.meta.advanced.showStagedDeployed;
                        $scope.meta.advanced.previousShowEnabledDisabled = $scope.meta.advanced.showEnabledDisabled;
                        $scope.meta.advanced.previousIncludeUserRules = $scope.meta.advanced.includeUserRules;
                    }

                    /**
                         * Revert to the previous advanced filter setting.
                         * @private
                         * @method _revertToPreviousState
                         */
                    function _revertToPreviousState() {
                        $scope.selectedVendors = $scope.previouslySelected;
                        $scope.meta.advanced.showStagedDeployed = $scope.meta.advanced.previousShowStagedDeployed;
                        $scope.meta.advanced.showEnabledDisabled = $scope.meta.advanced.previousShowEnabledDisabled;
                        $scope.meta.advanced.includeUserRules = $scope.meta.advanced.previousIncludeUserRules;
                        $scope.meta.advanced.changed = false;
                    }

                    /**
                         * Apply the advanced search filters to the query-string.
                         *
                         * @method _addAdvancedSearchToQuery
                         * @private
                         */
                    function _addAdvancedSearchToQuery() {
                        if ($scope.meta.advanced.showStagedDeployed === PUBLISHED_ENUM.STAGED) {
                            queryService.query.addSearchField("c", "staged", "eq", "1");
                        } else {
                            queryService.query.clearSearchField("staged", "eq", "1");
                        }

                        if ($scope.meta.advanced.showStagedDeployed === PUBLISHED_ENUM.DEPLOYED) {
                            queryService.query.addSearchField("b", "staged", "eq", "0");
                        } else {
                            queryService.query.clearSearchField("staged", "eq", "0");
                        }

                        if ($scope.meta.advanced.showEnabledDisabled === STATUS_ENUM.ENABLED) {
                            queryService.query.addSearchField("d", "disabled", "eq", "0");
                        } else {
                            queryService.query.clearSearchField("disabled", "eq", "0");
                        }

                        if ($scope.meta.advanced.showEnabledDisabled === STATUS_ENUM.DISABLED) {
                            queryService.query.addSearchField("e", "disabled", "eq", "1");
                        } else {
                            queryService.query.clearSearchField("disabled", "eq", "1");
                        }

                        if (!$scope.meta.advanced.includeUserRules) {
                            queryService.query.removeParameter("config");
                        } else {
                            queryService.query.addParameter("config", USER_CONFIG);
                        }

                        var vendors = _getSelectedVendorIDs();
                        if (vendors.length === 0) {
                            queryService.query.removeParameter("vendor_id");
                        } else {
                            queryService.query.addParameter("vendor_id", vendors.join(","));
                        }
                    }

                    /**
                         * Event handler triggered when one of the advanced filter options is changed.
                         *
                         * @method onAdvancedChanged
                         * @param  {String} type
                         */
                    $scope.onAdvancedChanged = function(type) {
                        switch (type) {
                            case "vendor":
                                if ( $scope.previouslySelected !== $scope.selectedVendors ) {
                                    $scope.meta.advanced.changed = true;
                                }
                                break;
                            case "userDefined":
                                if ($scope.meta.advanced.previousIncludeUserRules !== $scope.meta.advanced.includeUserRules) {
                                    $scope.meta.advanced.changed = true;
                                }
                                break;
                            default:
                                $scope.meta.advanced.changed = true;
                        }
                    };

                    /**
                         * Check if there are any search criteria applied.  This includes various advanced search
                         * criteria different then their defaults or any unselected vendors.
                         *
                         * @method hasSearchFilter
                         * @return {Boolean} true if the is an active search, false otherwise.
                         */
                    $scope.hasSearchFilter = function() {
                        return $scope.filteredData === true ||
                                   $scope.advancedSearchApplied === true ||
                                   $scope.appliedVendors.length < $scope.vendors.length;
                    };

                    /**
                         * Clear the search query
                         *
                         * @method clearFilter
                         * @returns Promise
                         */
                    $scope.clearFilter = function() {
                        $scope.meta.filterValue = "";
                        $scope.activeSearch = false;
                        $scope.filteredData = false;

                        queryService.query.clearSearchField("*", "contains");
                        _addAdvancedSearchToQuery();

                        // select the first page of search results
                        return $scope.selectPage(1);
                    };

                    /**
                         * Start a search query
                         *
                         * @method startFilter
                         * @returns Promise
                         */
                    $scope.startFilter = function() {
                        $scope.activeSearch = ($scope.meta.filterValue !== "");
                        $scope.filteredData = false;

                        // Leave history so refresh works
                        if ($scope.meta.filterValue) {
                            queryService.query.addSearchField("a", "*", "contains", $scope.meta.filterValue);
                        } else {
                            queryService.query.clearSearchField("*", "contains");
                        }

                        return $scope.selectPage(1)
                            .then(function() {
                                _addAdvancedSearchToQuery();
                                if ($scope.meta.filterValue) {
                                    $scope.filteredData = true;
                                }
                                _updatePreviousState();
                                $scope.meta.advanced.changed = false;
                            }, function() {

                                // Revert to the previous state
                                _revertToPreviousState();
                            }).finally(function() {
                                _updateAdvancedSearchApplied();
                            });
                    };

                    /**
                         * Open the advanced search menu from another button.
                         *
                         * @method openAdvancedSearch
                         * @param  {Event} $event The jQlite event
                         */
                    $scope.openAdvancedSearch = function($event) {
                        $event.preventDefault();
                        $event.stopPropagation();
                        $event.currentTarget.blur();
                        $scope.advancedSearchOpen = !$scope.advancedSearchOpen;
                    };

                    /**
                         * Apply the advanced filter and close the dropdown
                         *
                         * @method applyAdvancedFilter
                         * @param  {Event} $event
                         */
                    $scope.applyAdvancedFilter = function($event) {
                        $event.preventDefault();
                        $event.stopPropagation();
                        $scope.advancedSearchOpen = false;
                        $scope.toggleSearch();
                    };

                    /**
                         * Reset the advanced filter and close the dropdown
                         *
                         * @method resetAdvancedFilter
                         * @param  {Event} $event
                         */
                    $scope.resetAdvancedFilter = function($event) {
                        $event.preventDefault();
                        $event.stopPropagation();
                        $scope.advancedSearchOpen = false;
                        $scope.resetFilter();
                    };

                    /**
                         * Update the applied vendor field.
                         *
                         * @private
                         * @method _updateAppliedVendor
                         */
                    function _updateAppliedVendor() {
                        $scope.appliedVendors = $scope.selectedVendors.slice();
                    }

                    /**
                         * Reset the advanced filter and apply
                         */
                    $scope.resetFilter = function() {
                        $scope.meta.advanced.changed = false;
                        if ($scope.meta.advanced.showStagedDeployed !== PUBLISHED_ENUM.BOTH) {
                            $scope.meta.advanced.showStagedDeployed = PUBLISHED_ENUM.BOTH;
                            $scope.meta.advanced.changed = true;
                        }

                        if ($scope.meta.advanced.showEnabledDisabled !== STATUS_ENUM.BOTH) {
                            $scope.meta.advanced.showEnabledDisabled = STATUS_ENUM.BOTH;
                            $scope.meta.advanced.changed = true;
                        }

                        if (!$scope.meta.advanced.includeUserRules) {
                            $scope.meta.advanced.includeUserRules = true;
                            $scope.meta.advanced.changed = true;
                        }

                        if ($scope.selectedVendors.length < $scope.vendors.length) {
                            $scope.selectedVendors = $scope.vendors;
                            $scope.meta.advanced.changed = true;
                        }

                        if ($scope.meta.advanced.changed) {
                            $scope.startFilter().then(_updateAppliedVendor);
                        }
                    };

                    /**
                         * Handles the keybinding for the clearing and searching.
                         * Esc clears the search field.
                         * Enter performs a search.
                         *
                         * @method triggerToggleSearch
                         * @param {Event} event - The event object
                         */
                    $scope.triggerToggleSearch = function(event) {

                        // clear on Esc
                        if (event.keyCode === 27) {
                            $scope.toggleSearch(true);
                        }

                        // filter on Enter
                        if (event.keyCode === 13) {
                            $scope.toggleSearch();
                        }
                    };

                    /**
                         * Toggles the clear button and conditionally performs a search.
                         * The expected behavior is if the user clicks the button or focuses the button and hits enter the button state rules.
                         *
                         * @method toggleSearch
                         * @scope
                         * @param {Boolean} isClick Toggle button clicked.
                         */
                    $scope.toggleSearch = function(isClick) {
                        var filter = $scope.meta.filterValue;
                        var advancedChanged = $scope.meta.advanced.changed;

                        if ( (!filter && !advancedChanged && ($scope.activeSearch  || $scope.filteredData)))  {

                            // no query in box, but we previously filtered or there is an active search
                            $scope.clearFilter().then(_updateAppliedVendor);
                        } else if (isClick && $scope.activeSearch ) {

                            // User clicks clear
                            $scope.clearFilter().then(_updateAppliedVendor);
                        } else if (filter || advancedChanged) {
                            $scope.startFilter().then(_updateAppliedVendor);
                        }
                    };

                    /**
                         * Select a specific page of rules
                         *
                         * @method selectPage
                         * @param  {Number} [page] Optional page number, if not provided will use the current
                         *                         page provided by the scope.meta.pageNumber.
                         * @return {Promise}
                         */
                    $scope.selectPage = function(page) {

                        // set the page if requested
                        if (page && angular.isNumber(page)) {
                            $scope.meta.pageNumber = page;
                        }

                        queryService.query.updatePagination($scope.meta.pageNumber, $scope.meta.pageSize);
                        return $scope.fetch();
                    };

                    /**
                         * Sort the list of rules
                         *
                         * @param {Object}  meta         The sort model.
                         * @param {Boolean} defaultSort  If true, the sort was not not initiated by the user
                         */
                    $scope.sortList = function(meta, defaultSort) {
                        queryService.query.clearSort();
                        queryService.query.addSortField(meta.sortBy, meta.sortType, meta.sortDirection);
                        if (!defaultSort) {
                            $scope.fetch();
                        }
                    };

                    /**
                         * Disables a rule from the list using the rule service
                         *
                         * @method disable
                         * @param  {Object} rule The rule to disable
                         * @return {Promise}
                         */
                    $scope.disable = function(rule) {
                        var ruleIndentifier = rule.id || "rule";

                        // if message is defined append it to the rule identifier
                        if ( rule.hasOwnProperty("meta_msg") && rule.meta_msg !== "" ) {
                            ruleIndentifier += ": " + rule.meta_msg;
                        }

                        return ruleService
                            .disableRule(rule.config, rule.id, false)
                            .then(function() {

                                // success
                                rule.disabled = true;
                                rule.staged = true;
                                $scope.stagedChanges = true;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully disabled “[_1]” in the list of [asis,ModSecurity™] rules.", _.escape(ruleIndentifier)),
                                    id: "alertDisableSuccess",
                                });

                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDisablingRule",
                                });
                            });
                    };

                    /**
                         * Enables a rule from the list using the rule service
                         *
                         * @method enable
                         * @param  {Object} rule The rule to enable
                         * @return {Promise}
                         */
                    $scope.enable = function(rule) {
                        var ruleIndentifier = rule.id || "rule";

                        // if message is defined append it to the rule identifier
                        if ( rule.hasOwnProperty("meta_msg") && rule.meta_msg !== "" ) {
                            ruleIndentifier += ": " + rule.meta_msg;
                        }

                        return ruleService
                            .enableRule(rule.config, rule.id, false)
                            .then(function() {

                                // success
                                rule.disabled = false;
                                rule.staged = true;
                                $scope.stagedChanges = true;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully enabled “[_1]” in the list of [asis,ModSecurity™] rules.", _.escape(ruleIndentifier)),
                                    id: "alertEnableSuccess",
                                });

                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorEnablingRule",
                                });
                            });
                    };

                    /**
                         * Deletes a rule from the list using the rule service
                         *
                         * @method delete
                         * @param  {Object} rule The rule to delete
                         * @return {Promise}
                         */
                    $scope.delete = function(rule) {
                        var ruleIndentifier = rule.id || "rule";

                        // if message is defined append it to the rule identifier
                        if ( rule.hasOwnProperty("meta_msg") && rule.meta_msg !== "" ) {
                            ruleIndentifier += ": " + rule.meta_msg;
                        }

                        rule.deleting = true;
                        return ruleService
                            .deleteRule(rule.id)
                            .then(function() {

                                // success
                                $scope.fetch();
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully deleted “[_1]” from the list of [asis,ModSecurity™] rules.", _.escape(ruleIndentifier)),
                                    id: "alertDeleteSuccess",
                                });

                            }, function(error) {
                                rule.deleting = false;

                                // reset delete confirmation
                                rule.showDeleteConfirm = false;

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDeletingRule",
                                });
                            });
                    };

                    /**
                         * Deploys staged rules using the rule service
                         *
                         * @method deployChanges
                         * @return {Promise}
                         */
                    $scope.deployChanges = function() {
                        $scope.pendingChanges = true;
                        return ruleService
                            .deployQueuedRules()
                            .then(function() {

                                // success
                                $scope.stagedChanges = false;
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("You successfully deployed the staged changes and [asis,Apache] received a graceful restart request."),
                                    id: "successDeployChanges",
                                });
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDeployChanges",
                                });
                            }).finally(function() {
                                $scope.pendingChanges = false;
                                $scope.fetch();
                            });
                    };

                    /**
                         * Discards staged rule changes using the rule service
                         *
                         * @method discardChanges
                         * @return {Promise}
                         */
                    $scope.discardChanges = function() {
                        $scope.pendingChanges = true;
                        return ruleService
                            .discardQueuedRules()
                            .then(function() {
                                var replace = false;

                                // discard changes success
                                $scope.stagedChanges = false;
                                return $scope.fetch().then(function() {

                                    // fetch success
                                    replace = true;
                                }, function() {

                                    // fetch failure
                                    replace = false;
                                }).finally(function() {

                                    // display discard changes success
                                    $scope.discardConfirm = false;
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("You successfully discarded the staged changes."),
                                        id: "successDiscardingChanges",
                                        replace: replace,
                                    });
                                });
                            }, function(error) {
                                $scope.fetch(); // To update the list to match the new state.
                                // discard changes failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorDiscardingChanges",
                                });
                            }).finally(function() {
                                $scope.pendingChanges = false;
                            });
                    };

                    /**
                         * Initialize the selected vendors
                         *
                         * @private
                         * @method initializeSelectedVendors
                         */
                    var _initializeSelectedVendors = function() {
                        var vendorIds = [];
                        var vendor_id_param = queryService.route.getParameter("vendor_id");
                        if (vendor_id_param) {
                            vendorIds = vendor_id_param.split(",");
                        }

                        var config_param = queryService.route.getParameter("config");

                        var vendors = [];
                        if (!angular.isDefined(vendor_id_param) && !angular.isDefined(config_param)) {

                            // This is a default load, so select all vendors
                            vendors = $scope.vendors;
                        } else if (vendorIds.length > 0) {

                            // Some vendors were passed on the querystring, so use those
                            vendors = _.filter($scope.vendors, function(vendor) {

                                // find the vendors by ids from the list of vendorIds
                                var id = _.find(vendorIds, function(id) {
                                    return vendor.vendor_id === id;
                                });
                                return !!id;
                            });
                        }

                        $scope.previouslySelected = $scope.selectedVendors = vendors;

                        // Also update the applied vendors so the ui is updated on load.
                        $scope.appliedVendors = vendors.slice();
                    };

                    /**
                         * Determines if a rule is from a custom set
                         *
                         * @method isCustomVendor
                         * @param {Object} rule The rule to read vendor id from
                         * @return {Boolean} Returns true if the rule is from a custom set
                         */
                    $scope.isCustomVendor = function(rule) {
                        return rule.hasOwnProperty("vendor_id") && rule.vendor_id === "";
                    };

                    /**
                         * Returns the full vendor name for the supplied rule
                         *
                         * @method getVendorName
                         * @param {Object} rule The rule to read vendor id from
                         * @return {String} The full vendor name
                         */
                    $scope.getVendorName = function(rule) {
                        var currentVendor;
                        if ( rule.vendor_id !== "" ) {
                            for ( var i = 0, length = $scope.vendors.length; i < length; i++ ) {
                                currentVendor = $scope.vendors[i];
                                if ( rule.vendor_id === currentVendor.vendor_id ) {
                                    return currentVendor.name;
                                }
                            }
                        }
                        return LOCALE.maketext("Custom");
                    };

                    /**
                         * Get a list of the enabled vendors
                         *
                         * @method _onlyEnabledVendors
                         * @private
                         * @param  {Array} vendor   A list of vendors
                         * @return {Array}          A list of the vendors that were enabled
                         */
                    function _onlyEnabledVendors(vendors) {
                        if (vendors && angular.isArray(vendors)) {
                            return  vendors.filter( function(vendor) {
                                return vendor.enabled;
                            });
                        } else {
                            return [];
                        }
                    }

                    /**
                         * Retrieve the list of vendors
                         *
                         * @method getVendors
                         * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                         */
                    $scope.getVendors = function() {
                        spinnerAPI.start("ruleListSpinner");
                        return vendorService
                            .fetchList()
                            .then(function(results) {
                                if (angular.isArray(results.items)) {
                                    $scope.vendors = _onlyEnabledVendors(results.items);
                                    _initializeSelectedVendors();
                                } else {
                                    alertService.add({
                                        message: "The system was unable to retrieve the list of available vendors.",
                                        type: "danger",
                                    });
                                }
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorLoadingVendorList",
                                });
                            }).finally(function() {
                                spinnerAPI.stop("ruleListSpinner");
                            });
                    };

                    /**
                         * Performs final prep work on the selectedVendors list.
                         * Extracts the vendor ids into an array.
                         *
                         * @method _getSelectedVendorIDs
                         * @return {Array}  A list of vendor ids that is ready for consumption by the ruleService
                         */
                    function _getSelectedVendorIDs() {
                        return $scope.selectedVendors && $scope.selectedVendors.map(function(vendor) {
                            return vendor.vendor_id;
                        });
                    }

                    /**
                         * Fetch the list of rules from the server
                         * @method fetch
                         * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                         */
                    $scope.fetch = function() {
                        $scope.loadingPageData = true;
                        spinnerAPI.start("ruleListSpinner");
                        alertService.removeById("errorFetchRulesList");

                        return ruleService
                            .fetchRulesList(_getSelectedVendorIDs(), $scope.meta)
                            .then(function(results) {
                                $scope.rules = results.items;
                                $scope.stagedChanges = results.stagedChanges;
                                $scope.totalItems = results.totalItems;
                                $scope.totalPages = results.totalPages;
                            }, function(error) {

                                // failure
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    id: "errorFetchRulesList",
                                });

                                // throw an error for chained promises
                                throw error;
                            }).finally(function() {
                                $scope.loadingPageData = false;
                                spinnerAPI.stop("ruleListSpinner");
                            });
                    };

                    /**
                         * Generates the text for the vendor/user-defined indicator button.
                         * This is needed because we need to dynamically determine plurality of phrases.
                         *
                         * @method generateIndicatorText
                         * @param  {String} type The type of vendor count to generate (e.g. "short" or "long")
                         * @return {String}      The formatted vendor count string
                         */
                    $scope.generateIndicatorText = function(type) {
                        switch (type) {
                            case "vendor-short":
                                return $scope.appliedVendors.length;
                            case "vendor-long":
                                return LOCALE.maketext("[quant,_1,Vendor,Vendors]", $scope.appliedVendors.length);
                            case "vendor-title":
                                return $scope.generateVendorTitle();
                            case "user-title":
                                return $scope.meta.advanced.previousIncludeUserRules ?
                                    LOCALE.maketext("Your user-defined rules are included below.") :
                                    LOCALE.maketext("Your user-defined rules are not included below.");
                            default:
                                return LOCALE.maketext("Loading …");
                        }
                    };

                    /**
                         * Generates the text for the title/tooltip that displays when a user hovers over the rule set count.
                         *
                         * @method generateVendorTitle
                         * @return {String} The text for the tooltip
                         */
                    $scope.generateVendorTitle = function() {
                        var vendors = $scope.appliedVendors;

                        if (vendors.length === 0) {
                            return LOCALE.maketext("You have not selected any vendor rule sets.");
                        }

                        var vendorNames = vendors.map(function(vendor) {
                            return vendor.name;
                        });

                        return LOCALE.maketext("The displayed rules are from the following vendor rule [numerate,_1,set,sets]: [list_and,_2]", vendors.length, vendorNames);
                    };

                    /**
                         * Sets the left property so that the dropdown lines up with the input group
                         *
                         * @method _setMenuLeft
                         * @private
                         * @param {Element} menu         The dropdown menu element
                         * @param {Number}  groupWidth   The width of the input group in pixels
                         */
                    function _setMenuLeft(menu, groupWidth) {
                        menu.css("left", -1 * groupWidth);
                        menu.css("right", "auto");
                    }

                    /**
                         * Unsets the left and right properties so that they reset back to the CSS defaults
                         *
                         * @method _setMenuRight
                         * @private
                         * @param {Element} menu   The dropdown menu element
                         */
                    function _setMenuRight(menu) {
                        menu.css("left", "");
                        menu.css("right", "");
                    }

                    /**
                         * Adjusts the position of the dropdown menu depending on whether or not it is being
                         * clipped by the edge of the viewport.
                         *
                         * @method fixMenuClipping
                         * @param  {Event} event   The associated event object
                         */
                    $scope.fixMenuClipping = function(event) {
                        var menu       = this.find(".advanced-filter-menu");
                        var inputGroup = this.siblings("input");
                        var groupWidth = inputGroup.outerWidth();

                        // This keeps the menu from flying around while still allowing offset to work
                        if (event.type === "open") {
                            menu.css("opacity", 0);
                        }

                        $timeout(function() { // We need to queue this up after $digest or the dropdown won't be visible yet and the offset will be incorrect
                            if (menu) {
                                switch (event.type) {

                                    case "resize":
                                        if (menu.offset().left < 0) {
                                            _setMenuLeft(menu, groupWidth);
                                        } else if (groupWidth > menu.outerWidth()) { // If the menu isn't clipping, it could be because we fixed it already or because it fits on the page
                                            _setMenuRight(menu);
                                        }
                                        break;

                                    case "open":
                                        if (menu.offset().left < 0) {
                                            _setMenuLeft(menu, groupWidth);
                                        }
                                        break;

                                    case "close":
                                        _setMenuRight(menu);
                                        break;
                                }

                                menu.css("opacity", 1);
                            }
                        }, 0, false);
                    };

                    // setup data structures for the view
                    $scope.rules = [];
                    $scope.vendors = [];
                    $scope.appliedVendors = []; // Differs from the selectedVendors in that this is only populated once the settings have been applied
                    $scope.totalPages = 0;
                    $scope.totalItems = 0;

                    var pageSize = queryService.route.getPageSize(queryService.DEFAULT_PAGE_SIZE);
                    var page = queryService.route.getPage(pageSize, 1);
                    var sorting = queryService.route.getSortProperties("disabled", "", "asc");


                    /**
                         * Determin if we should check the includeUserRules advanced search option.
                         * @note if neither the config or vendor_id is set in the querystring, then default to
                         * showing the custom config to match the default prefetch rules.
                         * @return {Boolean}
                         */
                    function _includeUserRules() {
                        var config = queryService.route.getParameter("config");
                        var vendor_id = queryService.route.getParameter("vendor_id");
                        if (config !== USER_CONFIG && !vendor_id) {
                            return true; // We default to showing custom rules
                        }
                        return config === USER_CONFIG;
                    }

                    var staged = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("staged"), "1", true);
                    var deployed = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("staged"), "0", true);
                    var disabled = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("disabled"), "1", true);
                    var enabled = LOGIC.compareOrDefault(queryService.route.getSearchFieldValue("disabled"), "0", true);

                    $scope.meta = {
                        filterBy: "*",
                        filterCompare: "contains",
                        filterValue: "",
                        pageSize: pageSize,
                        pageNumber: page,
                        sortBy: sorting.field,
                        sortType: sorting.type,
                        sortDirection: sorting.direction,
                        pageSizes: [10, 20, 50, 100],
                        advanced: {
                            showStagedDeployed: LOGIC.translateBinaryAndToState(staged, deployed, PUBLISHED_ENUM.BOTH, PUBLISHED_ENUM.STAGED, PUBLISHED_ENUM.DEPLOYED, PUBLISHED_ENUM.BOTH),
                            showEnabledDisabled: LOGIC.translateBinaryAndToState(enabled, disabled, STATUS_ENUM.BOTH, STATUS_ENUM.ENABLED, STATUS_ENUM.DISABLED, STATUS_ENUM.BOTH),
                            includeUserRules: _includeUserRules(),
                            changed: false,
                        },
                    };

                    $scope.appliedIncludeUserRules = $scope.meta.advanced.includeUserRules;

                    _updatePreviousState();

                    $scope.activeSearch = $scope.filteredData = $scope.meta.filterValue ? true : false;

                    // if the user types something else in the search box, we change the button icon so they can search again.
                    $scope.$watch("meta.filterValue", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.activeSearch = false;
                    });

                    // watch the page size and and load the first page if it changes
                    $scope.$watch("meta.pageSize", function(oldValue, newValue) {
                        if (oldValue === newValue) {
                            return;
                        }
                        $scope.selectPage(1);
                    });

                    // Setup the installed bit...
                    $scope.isInstalled = PAGE.installed;

                    if (!$scope.isInstalled) {

                        // redirect to the historic view of the hit list if mod_security is not installed
                        $scope.loadView("hitList");
                    }

                    $scope.$on("$viewContentLoaded", function() {

                        // check for page data in the template if this is a first load
                        if (app.firstLoad.rules && PAGE.rules) {
                            app.firstLoad.rules = false;
                            $scope.loadingPageData = false;
                            $scope.advancedSearchOpen = false;

                            var vendors = vendorService.prepareList(PAGE.vendors);

                            // In the rules list page, we only care about
                            // searching for rules from enabled vendors.
                            $scope.vendors =  _onlyEnabledVendors(vendors.items);

                            _initializeSelectedVendors();

                            var rules = ruleService.prepareList(PAGE.rules);

                            $scope.rules = rules.items;
                            $scope.stagedChanges = rules.stagedChanges;
                            $scope.totalItems = rules.totalItems;
                            $scope.totalPages = rules.totalPages;

                            if ( !rules.status ) {

                                // on view load in an error state give the user a chance to discard staged changes
                                $scope.stagedChanges = true;
                                $scope.loadingPageData = "error";
                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("There was a problem loading the page. The system is reporting the following error: [_1].", _.escape(PAGE.rules.metadata.reason)),
                                    id: "errorFetchRulesList",
                                });
                            }
                        } else {

                            // Otherwise, retrieve it via ajax
                            $timeout(function() {

                                // NOTE: Without this delay the spinners are not created on inter-view navigation.
                                $scope.getVendors().then(function() {
                                    $scope.selectPage(1);
                                });
                            });
                        }
                    });
                },
            ]);

        return controller;
    }
);
