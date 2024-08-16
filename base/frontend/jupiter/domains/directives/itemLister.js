/*
# domains/directives/itemLister.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/** @namespace cpanel.domains.directive.itemLister */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "ngRoute",
        "ngSanitize",
        "cjt/modules",
        "app/directives/tableShowingDirective",
        "cjt/services/cpanel/componentSettingSaverService",
        "app/services/domains",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator"
    ],
    function(angular, LOCALE, CJT) {

        "use strict";

        var module = angular.module("cpanel.domains.itemLister.directive", [
            "cpanel.domains.tableShowing.directive",
            "ngRoute",
            "ngSanitize",
            "cjt2.filters.startFrom"
        ]);

        module.value("PAGE", PAGE);

        module.directive("itemLister", ["$window", "$log", "componentSettingSaverService", "PAGE", function itemLister($window, $log, $CSSS, PAGE) {

            /**
             * Item Lister combines the typical table functions, pageSize,
             * showing, paginator, search, and allows you to plug in multiple
             * views.
             *
             * @module item-lister
             * @restrict EA
             *
             * @param  {String} id disseminated to other objects
             * @param  {Array} items Items that will be paginated, array of objs
             * @param  {Array} configuration-options Items that will be in the configuration cog
             * @param  {Array} header-items represents the columns of the table
             *
             * @example
             * <item-lister
             *      id="MyItemLister"
             *      items="[a,b,c,d,e]"
             *      configuration-options="configurationOptions"
             *      header-items="[{field:"blah",label:"Blah",sortable:false}]">
             *   <my-item-lister-view></my-item-lister-view>
             * </item-lister>
             *
             */

            var COMPONENT_NAME = "domainsItemLister";
            var TEMPLATE_PATH = "directives/itemLister.ptt";
            var RELATIVE_PATH = "domains/" + TEMPLATE_PATH;

            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : TEMPLATE_PATH,
                restrict: "EA",
                scope: {
                    parentID: "@id",
                    items: "=",
                    headerItems: "=",
                    configurationOptions: "="
                },
                transclude: true,
                replace: true,
                link: function(scope, element, attrs, transclude) {

                    var controlsBlock;
                    var contentBlock;

                    function _attachControls(elem) {
                        controlsBlock.append(elem);
                    }

                    function _attachOthers(elem) {
                        elem.setAttribute("id", scope.parentID + "_transcludePoint");
                        elem.setAttribute("ng-if", "filteredItems.length");
                        contentBlock.replaceWith(elem);
                    }

                    function _attachTransclude(elem) {
                        if (angular.element(elem).hasClass("lister-controls")) {
                            _attachControls(elem);
                        } else {
                            _attachOthers(elem);
                        }
                    }

                    function _findTranscludes() {

                        // *cackles maniacally*
                        // *does a multi-transclude anyways*
                        controlsBlock = element.find("#" + scope.parentID + "_transcludedControls");
                        contentBlock = element.find("#" + scope.parentID + "_transcludePoint");
                        var transcludedBlock = element.find("div.transcluded");
                        var transcludedItems = transcludedBlock.children();
                        angular.forEach(transcludedItems, _attachTransclude);
                        transcludedBlock.remove();
                    }

                    /* There is a dumb race condition here */
                    /* So we have to delay to get the content transcluded */
                    setTimeout(_findTranscludes, 2);
                },
                controller: ["$routeParams", "$scope", "$filter", "ITEM_LISTER_CONSTANTS", "domains", "alertService", function itemListerController($routeParams, $scope, $filter, ITEM_LISTER_CONSTANTS, $domainServices, $alertService) {

                    $scope.redirectSelection = 1;
                    $scope.viewCallbacks = [];
                    $scope.webserverRoleAvailable = PAGE.hasWebServerRole;

                    var filters = {
                        filter: $filter("filter"),
                        orderBy: $filter("orderBy"),
                        startFrom: $filter("startFrom"),
                        limitTo: $filter("limitTo")
                    };

                    function _filter(filteredItems) {

                        // filter list based on search text
                        if ($scope.filterValue !== "") {
                            return filters.filter(filteredItems, $scope.filterValue, false);
                        }

                        return filteredItems;
                    }

                    function _sort(filteredItems) {

                        // sort the filtered list
                        if ($scope.sort.sortDirection !== "" && $scope.sort.sortBy !== "") {

                            // Normally we would sort by the 'domains' field by virtue it was first.  It's not anymore, so correct that.
                            if ($scope.sort.sortBy === "batchSelect") {
                                $scope.sort.sortBy = "domain";
                            }
                            return filters.orderBy(filteredItems, $scope.sort.sortBy, $scope.sort.sortDirection !== "asc");
                        }

                        return filteredItems;
                    }

                    function _paginate(filteredItems) {

                        // filter list based on page size and pagination
                        if ($scope.totalItems > _.min($scope.pageSizes)) {
                            var start = ($scope.currentPage - 1) * $scope.pageSize;
                            var limit = $scope.pageSize;

                            filteredItems = filters.startFrom(filteredItems, start);
                            filteredItems = filters.limitTo(filteredItems, limit);
                            $scope.showPager = true;

                            // table statistics
                            $scope.start = start + 1;
                            $scope.limit = start + filteredItems.length;

                        } else {

                            // hide pager and pagination
                            $scope.showPager = false;

                            if (filteredItems.length === 0) {
                                $scope.start = 0;
                            } else {

                                // table statistics
                                $scope.start = 1;
                            }

                            $scope.limit = filteredItems.length;
                        }

                        return filteredItems;
                    }

                    function _updatedListerState(lastInteractedItem) {

                        if ($scope.loadingInitialState) {
                            return;
                        }

                        var storedSettings = {
                            totalItems: $scope.totalItems,
                            currentPage: $scope.currentPage,
                            pageSize: $scope.pageSize,
                            start: $scope.start,
                            limit: $scope.limit,
                            lastInteractedItem: lastInteractedItem,
                            filterValue: $scope.filterValue,
                            sort: {
                                sortDirection: $scope.sort.sortDirection,
                                sortBy: $scope.sort.sortBy
                            }
                        };

                        $CSSS.set(COMPONENT_NAME, storedSettings);
                    }

                    function _itemInteracted(event, parameters) {
                        if (parameters.interactionID) {
                            _updatedListerState(parameters.interactionID);
                        }
                    }

                    function _itemSelected(event, parameters) {

                        // Go over all domains to see if all are selected
                        var allSelected = true,
                            currentDomainList = $domainServices.getCurrentDomains();
                        for (var i = 0; i < currentDomainList.length; i++) {
                            if (!currentDomainList[i].selected) {
                                allSelected = false;
                                break;
                            }
                        }

                        // Update Select All checkbox
                        $scope.selectAll = allSelected;
                    }

                    /**
                     * Register a callback to call on the update of the lister
                     *
                     * @method registerViewCallback
                     *
                     * @param  {Function} callback function to callback to
                     *
                     */

                    this.registerViewCallback = function registerViewCallback(callback) {
                        $scope.viewCallbacks.push(callback);
                        callback($scope.filteredItems);
                    };

                    /**
                     * Get the header items
                     *
                     * @method getHeaderItems
                     *
                     * @return {Array} returns array of objects containing labels
                     *
                     */
                    this.getHeaderItems = function getHeaderItems() {
                        return $scope.headerItems;
                    };

                    /**
                     * Deregister a callback (useful for view changes)
                     *
                     * @method deregisterViewCallback
                     *
                     * @param  {Function} callback callback to deregister
                     *
                     */

                    this.deregisterViewCallback = function deregisterViewCallback(callback) {
                        for (var i = $scope.viewCallbacks.length - 1; i >= 0; i--) {
                            if ($scope.viewCallbacks[i] === callback) {
                                $scope.viewCallbacks.splice(i, 1);
                            }
                        }
                    };

                    /**
                     * Function called to rebuild the view from internal components
                     *
                     * @method fetch
                     *
                     */

                    $scope.fetch = function fetch() {

                        var filteredItems = [];

                        filteredItems = _filter($scope.items);

                        // update the total items after search
                        $scope.totalItems = filteredItems.length;

                        filteredItems = _sort(filteredItems);
                        filteredItems = _paginate(filteredItems);

                        $scope.filteredItems = filteredItems;

                        _updatedListerState();

                        angular.forEach($scope.viewCallbacks, function updateCallback(viewCallback) {
                            viewCallback($scope.filteredItems);
                        });

                        $scope.$emit(ITEM_LISTER_CONSTANTS.ITEM_LISTER_UPDATED_EVENT, { meta: { filterValue: $scope.filterValue } });

                        return filteredItems;

                    };

                    /**
                     * Return the focus of the page to the search at the top and scroll to it
                     *
                     * @method focusSearch
                     *
                     */

                    $scope.focusSearch = function focusSearch() {
                        angular.element(document).find("#" + $scope.parentID + "_search_input").focus();
                        $window.scrollTop = 0;
                    };

                    $scope.configurationClicked = function(configEvent) {
                        $scope.$emit(configEvent);
                    };

                    $scope.$on(ITEM_LISTER_CONSTANTS.TABLE_ITEM_BUTTON_EVENT, _itemInteracted);
                    $scope.$on(ITEM_LISTER_CONSTANTS.ITEM_SELECT_EVENT, _itemSelected);

                    angular.extend($scope, {
                        maxPages: 5,
                        totalItems: $scope.items.length,
                        filteredItems: [],
                        currentPage: 1,
                        pageSize: 20,
                        pageSizes: [20, 50, 100, 500],

                        start: 0,
                        limit: 20,

                        filterValue: "",
                        sort: {
                            sortDirection: "asc",
                            sortBy: $scope.headerItems.length ? $scope.headerItems[0].field : ""
                        }
                    }, {
                        filterValue: $routeParams["q"]
                    });

                    function _savedStateLoaded(initialState) {
                        angular.extend($scope, initialState, {
                            filterValue: $routeParams["q"]
                        });
                    }

                    var registerSuccess = $CSSS.register(COMPONENT_NAME);
                    if ( registerSuccess ) {
                        $scope.loadingInitialState = true;
                        registerSuccess.then(_savedStateLoaded, $log.error).finally(function() {
                            $scope.loadingInitialState = false;
                            $scope.fetch();
                        });
                    }

                    this.showConfigColumn = $scope.showConfigColumn = $scope.configurationOptions && $scope.configurationOptions.length;

                    $scope.$on("$destroy", function() {
                        $CSSS.unregister(COMPONENT_NAME);
                    });

                    $scope.fetch();
                    $scope.canRedirectHTTPS = $domainServices.canRedirectHTTPS();
                    $scope.$watch("items", $scope.fetch);

                    /**
                     * Toggles the selection state of all domains in the form.
                     *
                     * @method toggleSelectAll
                     *
                     */

                    $scope.toggleSelectAll = function() {
                        var domains = $domainServices.getCurrentDomains();
                        for (var i = 0; i < domains.length; i++) {
                            if (!$scope.canRedirectHTTPS ) {
                                if (domains[i].isHttpsRedirecting) {
                                    domains[i].selected = $scope.selectAll;
                                }
                            } else {
                                if (!domains[i].nonHTTPS || domains[i].isHttpsRedirecting) {
                                    domains[i].selected = $scope.selectAll;
                                }
                            }
                        }
                    };

                    /**
                     * Checks to see if any domains are currently selected
                     *
                     * @method  hasSelected
                     *
                     * @returns {boolean} TRUE if one or more options are selected
                     *
                     */

                    $scope.hasSelected = function() {
                        var domains = $domainServices.getCurrentDomains();
                        for (var i = 0; i < domains.length; i++) {
                            if (domains[i].selected) {
                                return true;
                            }
                        }
                        return false;
                    };

                    $scope.applyMultiSecureRedirects = function(state) {
                        var domains = $domainServices.getCurrentDomains();
                        var successMessage, failureMessage;
                        if (state) { // true apparently means enabling
                            successMessage = LOCALE.maketext("Force [asis,HTTPS] Redirect is enabled for the selected domains.");
                            failureMessage = LOCALE.maketext("The system failed to enable Force [asis,HTTPS] Redirect.");
                        } else {
                            successMessage = LOCALE.maketext("Force [asis,HTTPS] Redirect is disabled for the selected domains.");
                            failureMessage = LOCALE.maketext("The system failed to disable Force [asis,HTTPS] Redirect.");
                        }
                        if (!$scope.hasSelected()) {
                            return;
                        }

                        $domainServices.toggleHTTPSRedirect(state)
                            .then(function(data) {
                                if (data.status) {

                                    // Deselect each selected domains and properly toggle the HTTPS Redirect option
                                    for (var i = 0; i < domains.length; i++) {
                                        if (domains[i].selected) {
                                            domains[i].selected = false;
                                            domains[i].isHttpsRedirecting = state;

                                            // Change state of the link to the domain to properly reflect https status
                                            var theLink = document.getElementById(domains[i].domain + "_domain_link");
                                            if (typeof (theLink) !== "undefined") {
                                                var protocol = domains[i].isHttpsRedirecting ? "https" : "http";
                                                theLink.href = protocol + "://" + domains[i].domain;
                                            }
                                        }
                                    }

                                    // Empty the domain list from Domain service
                                    $scope.selectAll = false;
                                    $scope.toggleSelectAll();
                                    $alertService.add({
                                        message: successMessage,
                                        type: "success",
                                        autoClose: 10000
                                    });
                                } else {
                                    $alertService.add({
                                        message: failureMessage,
                                        type: "danger"
                                    });
                                }
                            });
                    };
                }]
            };

        }]);
    }
);
