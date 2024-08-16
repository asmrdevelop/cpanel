/*
# cjt/views/applicationController.js.example              Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

/**
 * DEVELOPER NOTES: This module is used to contain common methods used by child views.
 *
 * Usage:
 *
 *  <div ng-controller="applicationController">
 *      <div ng-controller="childController">
 *          <a ng-click="loadView('child1')">
 *              Load a view using the loadView method inherited from applicationController
 *          </a>
 *      </div>
 *  </div>
 */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/httpStatus",
        "ngRoute",
        "cjt/services/alertService",
        "cjt/services/viewNavigationApi"
    ],
    function(angular, CJT, LOCALE, HTTP_STATUS) {

        var module = angular.module("cjt2.views.applicationController", [
            "ngRoute",
            "cjt2.services.alert",
            "cjt2.services.viewNavigationApi",
        ]);

        /**
         * Parent controller for applications. Provides a common API for controllers and handles some
         * other common scenarios such as routeChange errors.
         */
        module.controller("applicationController", [
            "$scope",
            "$location",
            "$anchorScroll",
            "$route",
            "$rootScope",
            "alertService",
            "viewNavigationApi",
            function($scope, $location, $anchorScroll, $route, $rootScope, alertService, viewNavigationApi) {

                if (angular.module("ngRoute")) {

                    // Add a handler for route change failures, such as session expiring or template failing to load.
                    $rootScope.$on("$routeChangeError", function(e, next, last, error) {
                        if (error && error.status !== 200) {
                            var message = LOCALE.maketext("The system failed to change the route with the following error: [_1] - [_2]", error.status, HTTP_STATUS.convertHttpStatusToReadable(error.status));
                            if (error.status === 401 || error.status === 403) {
                                message += " " + LOCALE.maketext("Your session may have expired or you logged out of the system. [output,url,_1,Log in] again to continue.", CJT.getLoginPath());
                            }
                            alertService.add({
                                message: message,
                                type: "danger"
                            });
                        } else {
                            alertService.add({
                                message: LOCALE.maketext("The system failed to change the route, but there is no information about the error."),
                                type: "danger"
                            });
                        }
                    });
                }

                /**
                 * Get the current route
                 *
                 * @method getCurrentRoute
                 * @return {RouteObject}
                 */
                $scope.getCurrentRoute = function() {
                    return $route.current;
                };

                /**
                 * Loads the specified view using the location service
                 *
                 * @method loadView
                 * @param {String} view         The name of the view to load
                 * @param {Object} query        Optional query string properties passed as an hash.
                 * @param {Object} [options]   Optional. A hash of additional options.
                 *     @param {Boolean} [options.clearAlerts]    If true, the default alert group in the alertService will be cleared.
                 *     @param {Boolean} [options.replaceState]   If true, the current history state will be replaced by the new view.
                 * @return {$location}         The Angular $location service used to perform the view changes.
                 * @see cjt2/services/viewNavigationApi.js
                 */
                $scope.loadView = viewNavigationApi.loadView;

                /**
                 * Scrolls to the specified id using the location hash
                 *
                 * @method scrollTo
                 * @param {String} id The id of the anchor to scroll the view to
                 * @param {Boolean} [cancel] If provided and true, will cancel the routing, otherwise, triggers routing
                 * @reference To prevent actual routing: http://stackoverflow.com/questions/17711232/scroll-to-in-angularjs
                 */
                $scope.scrollTo = function(id, cancel) {
                    var oldId;
                    if (cancel) {
                        oldId = $location.hash();
                    }
                    $location.hash(id);
                    $anchorScroll();
                    if (cancel) {
                        $location.hash(oldId);
                    }
                };

                $scope.viewDoneLoading = false;

                /**
                 * Hide any view loading panels that are showing.
                 */
                $scope.hideViewLoadingPanel = function() {
                    $scope.viewDoneLoading = true;
                };

                /**
                 * Show any view loading panels that are showing.
                 */
                $scope.showViewLoadingPanel = function() {
                    $scope.viewDoneLoading = false;
                };

                /**
                 * Marks the phrase in the template as translatable for the harvester.                     // ## no extract maketext
                 * This is a convenience function for use in templates and partials.
                 *
                 * @method translatable                                                                     // ## no extract maketext
                 * @param  {String} str Translatable string
                 * @return {String}     Same string, this is just a marker function for the harvester
                 * @example
                 * In your template:
                 *
                 * <directive param="translatable('Some string to translate with parameters [_1]')">        // ## no extract maketext
                 * </directive>
                 *
                 * In your JavaScript:
                 *
                 * var localized = LOCALE.makevar(template)
                 *
                 */
                $scope.translatable = function(str) {                                                       // ## no extract maketext
                    return str;
                };
            }
        ]);
    }
);
