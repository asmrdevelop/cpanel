define(
    [
        "angular",
        "cjt/core",
        "lodash",
        "ngSanitize",
        "ngRoute",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, CJT, _) {
        "use strict";

        var module = angular.module("cjt2.directives.breadcrumbs", [
            "cjt2.templates",
            "ngRoute",
            "ngSanitize"
        ]);

        module.directive("breadcrumbs", function() {
            var RELATIVE_PATH = "libraries/cjt2/directives/breadcrumbs.phtml";

            var breadcrumbController = [ "$scope", "$location", "$rootScope", "$route", function($scope, $location, $rootScope, $route) {

                var breadcrumbs = [];

                $scope.crumbs = [];

                function updateBreadcrumbInfo(routeData) {
                    $scope.crumbs = [];

                    while (routeData) {
                        $scope.crumbs.unshift(routeData);
                        routeData = _.find(breadcrumbs, function(breadcrumb) {
                            return breadcrumb.id === routeData.parentID;
                        });
                    }
                }

                function buildCrumbs() {
                    var routes = $route.routes;

                    angular.forEach(routes, function(config) {
                        if (config.hasOwnProperty("breadcrumb")) {
                            var breadcrumb = config.breadcrumb;
                            breadcrumbs.push(breadcrumb);
                        }
                    });
                }

                function init() {

                    buildCrumbs();

                    // Validating based on the path whether the initial load is an existing breadcrumb
                    var pathElements = $location.path().split("/");
                    var routePath = pathElements.slice(0, 2).join("/");

                    var routeData = _.find(breadcrumbs, function(breadcrumb) {
                        var breadcrumbPath = breadcrumb.path;

                        // If the breadcrumb.path was specified with a trailing forward slash
                        // strip it for matching purposes
                        // but not if it is a root level /
                        if (breadcrumbPath.length > 1 && breadcrumbPath.charAt(breadcrumbPath.length - 1) === "/") {
                            breadcrumbPath = breadcrumbPath.substr(0, breadcrumbPath.length - 1);
                        }
                        return breadcrumbPath === routePath;
                    });

                    updateBreadcrumbInfo(routeData);
                }

                init();

                $rootScope.$on("$routeChangeSuccess", function(event, current) {
                    buildCrumbs();
                    updateBreadcrumbInfo(current.breadcrumb);
                });

                // update route parameter
                $scope.changeRoute = function(path) {
                    $location.path(path);
                };
            }];

            return {
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                replace: true,
                restrict: "EA",
                scope: true,
                controller: breadcrumbController
            };
        });

    }
);
