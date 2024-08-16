/*
# email_deliverability/directives/itemLister.js                        Copyright 2022 cPanel, L.L.C.
#                                                                                All rights reserved.
# copyright@cpanel.net                                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "shared/js/email_deliverability/directives/tableShowingDirective",
        "ngSanitize",
        "ngRoute",
        "cjt/modules",
        "cjt/directives/pageSizeButtonDirective",
        "cjt/services/cpanel/componentSettingSaverService",
        "cjt/directives/toggleSortDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/pageSizeDirective",
        "cjt/filters/startFromFilter",
        "cjt/decorators/paginationDecorator"
    ],
    function(angular, _, CJT, TableShowingDirective) {

        "use strict";

        /**
         * Item Lister combines the typical table functions, pageSize,
         * showing, paginator, search, and allows you to plug in multiple
         * views.
         *
         * @module item-lister
         * @memberof cpanel.emailDeliverability
         * @restrict EA
         *
         * @param  {String} id disseminated to other objects
         * @param  {Array} items Items that will be paginated, array of objs
         * @param  {Array} header-items represents the columns of the table
         *
         * @example
         * <item-lister
         *      id="MyItemLister"
         *      items="[a,b,c,d,e]"
         *      header-items="[{field:"blah",label:"Blah",sortable:false}]">
         *   <my-item-lister-view></my-item-lister-view>
         * </item-lister>
         *
         */

        var MODULE_REQUIREMENTS = [
            TableShowingDirective.namespace,
            "ngRoute",
            "ngSanitize",
            "cjt2.filters.startFrom"
        ];
        var MODULE_NAMESPACE = "shared.emailDeliverability.itemLister.directive";
        var CSSS_COMPONENT_NAME = "domainsItemLister";

        var CONTROLLER_INJECTABLES = ["$routeParams", "$scope", "$filter", "$log", "$window", "componentSettingSaverService", "ITEM_LISTER_CONSTANTS"];
        var CONTROLLER = function itemListerController($routeParams, $scope, $filter, $log, $window, $CSSS, ITEM_LISTER_CONSTANTS) {

            $scope.viewCallbacks = [];

            var filters = {
                filter: $filter("filter"),
                orderBy: $filter("orderBy"),
                startFrom: $filter("startFrom"),
                limitTo: $filter("limitTo")
            };

            /**
             *
             * Filter items based on filterValue
             *
             * @private
             *
             * @param {Array} filteredItems items to filter
             * @returns {Array} filtered items
             */
            $scope._filter = function _filter(filteredItems) {

                // filter list based on search text
                if ($scope.filterValue !== "") {
                    return filters.filter(filteredItems, { domain: $scope.filterValue }, false);
                }

                return filteredItems;
            };

            /**
             *
             * Sort items based on sort.sortDirection and sort.sortBy
             *
             * @private
             *
             * @param {Array} filteredItems items to sort
             * @returns {Array} sorted items
             */
            $scope._sort = function _sort(filteredItems) {

                // sort the filtered list
                if ($scope.sort.sortDirection !== "" && $scope.sort.sortBy !== "") {
                    return filters.orderBy(filteredItems, $scope.sort.sortBy, $scope.sort.sortDirection !== "asc");
                }

                return filteredItems;
            };

            /**
             *
             * Paginate the items based on pageSize and currentPage
             *
             * @private
             *
             * @param {Array} filteredItems items to paginate
             * @returns {Array} paginated items
             */
            $scope._paginate = function _paginate(filteredItems) {

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
            };

            /**
             *
             * Update the NVData stored settings for the directive
             *
             * @private
             *
             * @param {String} lastInteractedItem last item interacted with
             */
            $scope._updatedListerState = function _updatedListerState(lastInteractedItem) {

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

                $CSSS.set(CSSS_COMPONENT_NAME, storedSettings);
            };

            /**
             *
             * Event function called on interaction with an item
             *
             * @private
             *
             * @param {Object} event event object
             * @param {Object} parameters event parameters {interactionID:...}
             */
            $scope._itemInteracted = function _itemInteracted(event, parameters) {
                if (parameters.interactionID) {
                    $scope._updatedListerState(parameters.interactionID);
                }
            };

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
             * @return {Array} filtered items
             */
            $scope.fetch = function fetch() {

                var filteredItems = [];

                filteredItems = $scope._filter($scope.items) || [];

                // update the total items after search
                $scope.totalItems = filteredItems.length;

                filteredItems = $scope._sort(filteredItems);
                filteredItems = $scope._paginate(filteredItems);

                $scope.filteredItems = filteredItems;

                $scope._updatedListerState();

                angular.forEach($scope.viewCallbacks, function updateCallback(viewCallback) {
                    viewCallback($scope.filteredItems);
                });

                $scope.$emit(ITEM_LISTER_CONSTANTS.ITEM_LISTER_UPDATED_EVENT, { meta: { filterValue: $scope.filterValue }, items: filteredItems });

                return filteredItems;

            };

            /**
             * Return the focus of the page to the search at the top and scroll to it
             *
             */
            $scope.focusSearch = function focusSearch() {
                angular.element(document).find("#" + $scope.parentID + "_search_input").focus();
                $window.scrollTop = 0;
            };

            /**
             *
             * Event function for a table configuration being clicked
             *
             * @param {Object} config which config was clicked
             */
            $scope.tableConfigurationClicked = function tableConfigurationClicked(config) {
                $scope.$emit(ITEM_LISTER_CONSTANTS.TABLE_ITEM_BUTTON_EVENT, { actionType: "tableConfigurationClicked", config: config });
            };

            $scope.$on(ITEM_LISTER_CONSTANTS.TABLE_ITEM_BUTTON_EVENT, $scope._itemInteracted);

            angular.extend($scope, {
                maxPages: 5,
                totalItems: ( $scope.items || [] ).length,
                filteredItems: [],
                currentPage: 1,
                pageSize: 20,
                pageSizes: [10, 20, 50],

                start: 0,
                limit: 20,

                filterValue: "",
                sort: {
                    sortDirection: "asc",
                    sortBy: ( $scope.headerItems || [] ).length ? $scope.headerItems[0].field : ""
                }
            }, {
                filterValue: $routeParams["q"]
            });

            /**
             *
             * Initiate CSSS saved state is loaded
             *
             * @private
             *
             * @param {Object} initialState saved state for directive
             */
            $scope._savedStateLoaded = function _savedStateLoaded(initialState) {
                angular.extend($scope, initialState, {
                    filterValue: $routeParams["q"]
                });
            };

            var registerSuccess = $CSSS.register(CSSS_COMPONENT_NAME);
            if ( registerSuccess ) {
                $scope.loadingInitialState = true;
                registerSuccess.then($scope._savedStateLoaded, $log.error).finally(function() {
                    $scope.loadingInitialState = false;
                    $scope.fetch();
                });
            }

            $scope.$on("$destroy", function() {
                $CSSS.unregister(CSSS_COMPONENT_NAME);
            });

            $scope.fetch();
            $scope.$watch("items", $scope.fetch);

        };

        var RELATIVE_PATH = "shared/js/email_deliverability/directives/itemLister.ptt";
        var TEMPLATE_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : CJT.buildPath(RELATIVE_PATH);
        var DIRECTIVE_INJECTABLES = ["$window", "$log", "componentSettingSaverService"];
        var DIRECTIVE_LINK = function(scope, element) {

            scope.controlsBlock = null;
            scope.contentBlock = null;

            /**
             *
             * Attach controls to the view
             *
             * @private
             *
             * @param {HTMLElement} elem html element to transclude as controls
             */
            scope._attachControls = function _attachControls(elem) {
                scope.controlsBlock.append(elem);
            };

            /**
             *
             * Attach Other items to view
             *
             * @private
             *
             * @param {HTMLElement} elem element to treat as the table body
             */
            scope._attachOthers = function _attachOthers(elem) {
                elem.setAttribute("id", scope.parentID + "_transcludePoint");
                elem.setAttribute("ng-if", "filteredItems.length");
                scope.contentBlock.replaceWith(elem);
            };

            /**
             *
             * Attach a transclude item
             *
             * @private
             *
             * @param {HTMLElement} elem html element to determine attachment point for
             */
            scope._attachTransclude = function _attachTransclude(elem) {
                if (angular.element(elem).hasClass("lister-controls")) {
                    scope._attachControls(elem);
                } else {
                    scope._attachOthers(elem);
                }
            };

            /**
             *
             * Find transclude items to attach to the view
             *
             */
            scope._findTranscludes = function _findTranscludes() {

                // *cackles maniacally*
                // *does a multi-transclude anyways*
                scope.controlsBlock = element.find("#" + scope.parentID + "_transcludedControls");
                scope.contentBlock = element.find("#" + scope.parentID + "_transcludePoint");
                var transcludedBlock = element.find("div.transcluded");
                var transcludedItems = transcludedBlock.children();
                angular.forEach(transcludedItems, scope._attachTransclude, scope);
                transcludedBlock.remove();
            };

            /* There is a dumb race condition here */
            /* So we have to delay to get the content transcluded */
            setTimeout(scope._findTranscludes, 2);
        };
        var DIRECTIVE = function itemLister($window, $log, $CSSS) {

            return {
                templateUrl: TEMPLATE_PATH,
                restrict: "EA",
                scope: {
                    parentID: "@id",
                    items: "=",
                    headerItems: "=",
                    tableConfigurations: "="
                },
                transclude: true,
                replace: true,
                link: DIRECTIVE_LINK,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER)
            };

        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        module.directive("itemLister", DIRECTIVE_INJECTABLES.concat(DIRECTIVE));

        return {
            "class": CONTROLLER,
            "namespace": MODULE_NAMESPACE,
            "link": DIRECTIVE_LINK,
            "template": TEMPLATE_PATH
        };
    }
);
