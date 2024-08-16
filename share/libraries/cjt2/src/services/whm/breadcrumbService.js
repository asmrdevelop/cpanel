/*
# cjt/services/whm/breadcrumbService.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, PAGE: false, CPANEL: false */

define(
    [

        // Libraries
        "angular",
        "jquery",
        "cjt/util/url",
        "ngRoute"
    ],
    function(angular, $, url) {

        var module = angular.module("cjt2.services.whm.breadcrumb", [
            "ngRoute"
        ]);

        /**
         * Synchronize the breadcrumb for WHM based on route changes. The breadcrumb
         * information is stored in the route object setup for the application.  To
         * start the service, call breadcrumbService.initialize() when your app starts.
         */
        module.factory("breadcrumbService", ["$rootScope", function($rootScope) {
            var _unsubscribe;
            var _mainTitle;

            return {

                /**
                 * Start listening for routeChange events.
                 *
                 * @static
                 * @method initialize
                 */
                initialize: function() {

                    // Support both older YUI namespace based initialization and
                    // newer pages that dont setup that namespace in the template.
                    var title = PAGE.MAIN_TITLE || CPANEL.PAGE.MAIN_TITLE;
                    if (!title) {
                        throw "DEV. ERROR: You must set the CPANEL.PAGE.MAIN_TITLE to the untranslated name of this page from command2 in your template to use this service.";
                    } else {
                        _mainTitle = title;
                    }

                    // register listener to watch route changes
                    _unsubscribe = $rootScope.$on( "$routeChangeStart", function(event, next, current) {

                        // Update the breadcrumbs
                        var breadcrumbManager = window.breadcrumb;
                        if (breadcrumbManager && _mainTitle && next.$$route) {
                            var leafIsView = breadcrumbManager.leafHasTag("view");
                            var leafName = breadcrumbManager.getLeafName();
                            while (leafName && leafName !== _mainTitle) {
                                breadcrumbManager.pop();
                                leafName = breadcrumbManager.getLeafName();
                                leafIsView = breadcrumbManager.leafHasTag("view");
                            }

                            var leafHref = breadcrumbManager.getLeafHref();
                            var breadCrumbText = next.$$route.breadcrumb;
                            breadcrumbManager.push(breadCrumbText, url.join(leafHref, next.$$route.originalPath), "view");
                        }
                    });
                },

                /**
                 * Stop listening for routeChange events.
                 *
                 * @static
                 * @method unsubscribe
                 */
                unsubscribe: function() {
                    if (_unsubscribe) {
                        _unsubscribe();
                    }
                    _unsubscribe = null;
                },

                /**
                 * Retrieve the breadcrumb manager to manually call api calls.
                 *
                 * @static
                 * @method getManager
                 * @return {BreadcrumbManager}
                 */
                getManager: function() {
                    return window.breadcrumb;
                }
            };
        }]);
    }
);
