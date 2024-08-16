/*
# templates/mod_security/views/hitlistController.js Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "uiBootstrap",
        "cjt/directives/responsiveSortDirective",
        "cjt/decorators/paginationDecorator",
        "cjt/directives/autoFocus",
        "cjt/filters/wrapFilter",
        "cjt/directives/spinnerDirective",
        "cjt/services/alertService",
        "app/services/hitlistService",
        "app/services/reportService"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller("hitListController", [
            "$scope",
            "$location",
            "$anchorScroll",
            "$routeParams",
            "$timeout",
            "hitListService",
            "alertService",
            "reportService",
            "spinnerAPI",
            "PAGE",
            function(
                $scope,
                $location,
                $anchorScroll,
                $routeParams,
                $timeout,
                hitListService,
                alertService,
                reportService,
                spinnerAPI,
                PAGE
            ) {

                $scope.loadingPageData = true;
                $scope.activeSearch = false;
                $scope.filteredData = false;
                $scope.selectedRow = -1;
                $scope.showAddSuccess = false;

                /**
                 * Extracts the vendor id from a config file path.
                 *
                 * @method _getVendorFromFile
                 * @private
                 * @param  {String} file   The full file path to the config file.
                 * @return {String}        The vendor id if it's a vendor config or undefined if we
                 *                         can't parse the file path properly.
                 */
                function _getVendorFromFile(file) {
                    var VENDOR_REGEX = /\/modsec_vendor_configs\/+([^/]+)/; /* TODO: EA-4700 */
                    var match = file && file.match(VENDOR_REGEX);
                    return match ? match[1] : void 0;
                }

                /**
                 * Checks to see if the given config file is the user config file.
                 *
                 * @method _isUserConfigFile
                 * @private
                 * @param  {String}  file   The full file path to the config file.
                 * @return {Boolean}        True if it is the user config file.
                 */
                function _isUserConfigFile(file) {
                    var USER_CONF_REGEX = /\/modsec2\.user\.conf$/; /* TODO: EA-4700 */
                    return USER_CONF_REGEX.test( file );
                }

                /**
                 * Passes the hit object to the report service to save a fetch and loads the view.
                 *
                 * @method loadReportview
                 * @param  {Object} hit   A hit object that corresponds to a single row from the modsec.hits table.
                 */
                $scope.loadReportView = function(hit) {
                    reportService.fetchByHit(hit);
                    $scope.loadView("report/hit/" + hit.id);
                };

                /**
                 * Load the edit rule view with the  requested rule.
                 *
                 * @method loadEditRuleView
                 * @param  {Number} ruleId
                 */
                $scope.loadEditRuleView = function(ruleId, file) {
                    var viewParams = {
                        ruleId: ruleId,
                        back: "hitList"
                    };
                    var vendorId;

                    if (_isUserConfigFile(file)) {
                        $scope.loadView("editCustomRule", viewParams);
                    } else if ( (vendorId = _getVendorFromFile(file)) ) { // Extra parens needed for jshint: http://www.jshint.com/docs/options/#boss
                        viewParams.vendorId = vendorId;
                        $scope.loadView("editCustomRule", viewParams);
                    } else {
                        alertService.add({
                            type: "danger",
                            message: LOCALE.maketext("An unknown error occurred in the attempt to retrieve the rule."),
                            id: "errorFetchRule"
                        });
                    }
                };

                /**
                 * Clear the search query
                 */
                $scope.clearFilter = function() {
                    $scope.meta.filterValue = "";
                    $scope.activeSearch = false;
                    $scope.filteredData = false;

                    // Leave history so refresh works
                    $location.search("api.filter.enable", 0);
                    $location.search("api.filter.verbose", null);
                    $location.search("api.filter.a.field", null);
                    $location.search("api.filter.a.type", null);
                    $location.search("api.filter.a.arg0", null);

                    // select the first page of search results
                    return $scope.selectPage(1);
                };

                /**
                 * Start a search query
                 */
                $scope.startFilter = function() {
                    $scope.activeSearch = true;
                    $scope.filteredData = false;

                    // Leave history so refresh works
                    $location.search("api.filter.enable", 1);
                    $location.search("api.filter.verbose", 1);
                    $location.search("api.filter.a.field", "*");
                    $location.search("api.filter.a.type", "contains");
                    $location.search("api.filter.a.arg0", $scope.meta.filterValue);

                    // Select the first page of search results
                    $scope.selectPage(1);
                    $scope.filteredData = true;
                };

                /**
                 * Selects a table row
                 * @param  {Number} index The index of selected row
                 */
                $scope.toggleRow = function(index) {
                    if ( index === $scope.selectedRow ) {

                        // collapse the row
                        $scope.selectedRow = -1;

                    } else {

                        // expand the selected row
                        $scope.selectedRow = index;
                    }

                };

                /**
                 * Select a specific page
                 * @param  {Number} [page] Optional page number, if not provided will use the current
                 * page provided by the scope.meta.pageNumber.
                 * @return {Promise}
                */
                $scope.selectPage = function(page) {

                    // clear the selected row
                    $scope.selectedRow = -1;

                    // set the page if requested
                    if (page && angular.isNumber(page)) {
                        $scope.meta.pageNumber = page;
                    }

                    // Leave history so refresh works
                    $location.search("api.chunk.enable", 1);
                    $location.search("api.chunk.verbose", 1);
                    $location.search("api.chunk.size", $scope.meta.pageSize);
                    $location.search("api.chunk.start", ( ($scope.meta.pageNumber - 1) * $scope.meta.pageSize) + 1);

                    return $scope.fetch();
                };

                /**
                 * Sort the list of hits
                 * @param {String} sortBy Field name to sort by.
                 * @param {String} sortDirection Direction to sort by: asc or decs
                 * @param {String} [sortType] Optional sort type applied to the field. Sort type is lexical by default.
                 */
                $scope.sortList = function(meta, defaultSort) {

                    // clear the selected row
                    $scope.selectedRow = -1;

                    // Leave history so refresh works
                    $location.search("api.sort.enable", 1);
                    $location.search("api.sort.a.field", meta.sortBy);
                    $location.search("api.sort.a.method", meta.sortType || "");
                    $location.search("api.sort.a.reverse", meta.sortDirection === "asc" ? 0 : 1);

                    if (!defaultSort) {
                        $scope.fetch();
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
                 * @param {Boolean} isClick Toggle button clicked.
                 */
                $scope.toggleSearch = function(isClick) {
                    var filter = $scope.meta.filterValue;

                    if ( !filter && ($scope.activeSearch  || $scope.filteredData)) {

                        // no query in box, but we prevously filtered or there is an active search
                        $scope.clearFilter();
                    } else if (isClick && $scope.activeSearch ) {

                        // User clicks clear
                        $scope.clearFilter();
                    } else if (filter) {
                        $scope.startFilter();
                    }
                };

                /**
                 * Fetch the list of hits from the server
                 * @return {Promise} Promise that when fulfilled will result in the list being loaded with the new criteria.
                 */
                $scope.fetch = function() {
                    spinnerAPI.start("hitlistSpinner");
                    return hitListService
                        .fetchList($scope.meta)
                        .then(function(results) {
                            $scope.hitList = results.items;
                            $scope.totalItems = results.totalItems;
                            $scope.totalPages = results.totalPages;
                        }, function(error) {

                            // failure
                            alertService.add({
                                type: "danger",
                                message: error,
                                id: "errorFetchHitList"
                            });
                        })
                        .then(function() {
                            $scope.loadingPageData = false;
                            spinnerAPI.stop("hitlistSpinner");
                        });
                };

                // setup data structures for the view
                $scope.hitList = [];
                $scope.totalPages = 0;
                $scope.totalItems = 0;

                var routeHasPaging = $routeParams["api.chunk.enable"] === "1";
                var pageSize = 10;
                var page = 1;
                if (routeHasPaging) {
                    pageSize = parseInt($routeParams["api.chunk.size"], 10);
                    page = Math.floor(parseInt($routeParams["api.chunk.start"], 10) / pageSize) + 1;
                }

                var routeHasSorting = $routeParams["api.sort.enable"] === "1";

                $scope.meta = {
                    filterBy: $routeParams["api.filter.a.field"] || "*",
                    filterCompare: "contains",
                    filterValue: $routeParams["api.filter.a.arg0"] || "",
                    pageSize: routeHasPaging ?  pageSize : 10,
                    pageNumber: routeHasPaging ? page : 1,
                    sortDirection: routeHasSorting ? ( $routeParams["api.sort.a.reverse"] === "1" ? "desc" : "asc" ) : "desc",
                    sortBy: routeHasSorting ? $routeParams["api.sort.a.field"] : "timestamp",
                    sortType: routeHasSorting ? $routeParams["api.sort.a.type"] : "numeric",
                    pageSizes: [10, 20, 50, 100]
                };

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

                $scope.activeSearch = $scope.filteredData = $scope.meta.filterValue ? true : false;

                // Setup the installed bit...
                $scope.isInstalled = PAGE.installed;

                // Expose any backend exceptions, ie missing database, missing table,
                $scope.dbException = PAGE.hitList.metadata.result === 0 ? PAGE.hitList.metadata.reason : "";

                $scope.$on("$viewContentLoaded", function() {

                    // check for page data in the template if this is a first load
                    if (app.firstLoad.hitList && PAGE.hitList) {
                        app.firstLoad.hitList = false;
                        $scope.loadingPageData = false;
                        var results = hitListService.prepareList(PAGE.hitList);
                        $scope.hitList = results.items;
                        $scope.totalItems = results.totalItems;
                        $scope.totalPages = results.totalPages;
                    } else {

                        // Otherwise, retrieve it via ajax
                        $timeout(function() {

                            // NOTE: Without this delay the spinners are not created on inter-view navigation.
                            $scope.selectPage(1);
                        });
                    }
                });

                if ($routeParams["addSuccess"]) {
                    $scope.showAddSuccess = true;
                }
            }
        ]);

        return controller;
    }
);
