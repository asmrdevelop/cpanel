/*
# account_preferences/index.js                     Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require, define */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "app/services/apiTokens",
        "app/views/list",
        "app/views/create",
        "app/views/manage",
        "app/filters/htmlSafeString",
        "cjt/modules",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/services/APICatcher",
        "cjt/directives/loadingPanel",
        "cjt/directives/breadcrumbs",
        "ngRoute",
    ],
    function(angular, CJT, LOCALE, ApiTokensService, ListView, CreateView, ManageView, HTMLSafeStringFilter) {

        "use strict";

        var MODULE_NAME = "cpanel.apiTokens";

        return function() {

            var ROUTES = [];
            var MODULE_INJECTABLES = [
                "ngRoute",
                "cjt2." + CJT.applicationName,
                ApiTokensService.namespace,
                HTMLSafeStringFilter.namespace
            ];

            [ListView, CreateView, ManageView].forEach(function(routeView) {
                routeView.breadcrumb = routeView.breadcrumb ? routeView.breadcrumb : {
                    id: routeView.id,
                    name: routeView.title,
                    path: routeView.route,
                    parentID: routeView.parentID
                };
                ROUTES.push(routeView);
                MODULE_INJECTABLES.push(routeView.namespace);
            });

            // First create the application
            var appModule = angular.module(MODULE_NAME, MODULE_INJECTABLES);

            appModule.value("ITEM_LISTER_CONSTANTS", {
                TABLE_ITEM_BUTTON_EVENT: "TableItemActionButtonEmitted",
                TABLE_ITEM_SELECTED: "TableItemSelectedEmitted",
                TABLE_ITEM_DESELECTED: "TableItemDeselectedEmitted",
                ITEM_LISTER_UPDATED_EVENT: "ItemListerUpdatedEvent",
                ITEM_LISTER_SELECT_ALL: "ItemListerSelectAllEvent",
                ITEM_LISTER_DESELECT_ALL: "ItemListerDeselectAllEvent"
            });

            appModule.value("CAN_CREATE_LIMITED", PAGE.canCreateLimited);

            appModule.controller("MainController", ["$scope", "$rootScope", "alertService", function MainController($scope, $rootScope, $alertService) {

                $scope.showResourcePanel = true;
                $scope.mainPanelClasses = "";
                $scope.sidePanelClasses = "";

                $scope.updatePanelClasses = function updatePanelClasses() {

                    $scope.sidePanelClasses = "col-sm-4 col-md-4 hidden-xs";
                    $scope.sidePanelClasses += " ";
                    $scope.sidePanelClasses += LOCALE.is_rtl() ? "pull-left" : "pull-right";

                    $scope.mainPanelClasses = $scope.showResourcePanel ? "col-xs-12 col-sm-8 col-md-8" : "col-xs-12";
                };

                /**
                 * Find a Route by the Path
                 *
                 * @private
                 *
                 * @method _getRouteByPath
                 * @param  {String} path route to match against the .route property of the existing routes
                 *
                 * @returns {Object} route that matches the provided path
                 *
                 */

                function _getRouteByPath(path) {
                    var foundRoute;
                    ROUTES.forEach(function(route, key) {
                        if (route.route === path) {
                            foundRoute = key;
                        }
                    });
                    return foundRoute;
                }

                $rootScope.$on("$routeChangeStart", function() {
                    $scope.loading = true;
                    $alertService.clear("danger");
                });

                $rootScope.$on("$routeChangeSuccess", function(event, current) {
                    $scope.loading = false;

                    if (current) {
                        var currentRouteKey = _getRouteByPath(current.$$route.originalPath);
                        if (ROUTES[currentRouteKey]) {
                            $scope.currentTab = ROUTES[currentRouteKey];
                            $scope.showResourcePanel = $scope.currentTab.showResourcePanel;
                            $scope.activeTab = currentRouteKey;
                            $scope.updatePanelClasses();
                        }
                    }

                });

                $rootScope.$on("$routeChangeError", function() {
                    $scope.loading = false;
                });
            }]);

            // Then load the application dependencies
            require(["cjt/bootstrap"], function(BOOTSTRAP) {

                appModule.config([
                    "$routeProvider",
                    "$animateProvider",
                    function($routeProvider, $animateProvider) {

                        $animateProvider.classNameFilter(/^((?!no-animate).)*$/);

                        ROUTES.forEach(function(route, key) {
                            $routeProvider.when(route.route, route);
                        });

                        $routeProvider.otherwise({
                            "redirectTo": "/"
                        });
                    }
                ]);

                BOOTSTRAP("#content", MODULE_NAME);
            });

            return appModule;
        };
    }
);
