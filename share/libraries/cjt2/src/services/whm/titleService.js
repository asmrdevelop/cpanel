/*
# cjt/services/whm/titleService.js               Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [

        // Libraries
        "angular",
        "jquery",
        "ngRoute"
    ],
    function(angular, $) {

        var module = angular.module("cjt2.services.whm.title", [
            "ngRoute"
        ]);

        /**
         * Synchronize the page title for WHM based on route changes. The breadcrumb
         * information is stored in the route object setup for the application.  To
         * start the service, call titleService.initialize() when your app starts.
         */
        module.factory("titleService", ["$rootScope", function($rootScope) {

            var removeEvent;

            return {

                /**
                 * Start the service
                 * @method initialize
                 */
                initialize: function() {

                    // register listener to watch route changes
                    removeEvent = $rootScope.$on( "$routeChangeStart", function(event, next, current) {
                        if (!next) {
                            return;
                        }

                        var $subTitle = $("#applicationSubTitle");
                        if (next.$$route && next.$$route.title) {

                            // Update the title
                            $subTitle.text(next.$$route.title);
                        } else {

                            // Clear the title
                            $subTitle.text("");
                        }
                    });
                },

                /**
                 * Stop the service
                 * @method stop
                 */
                stop: function() {
                    if (removeEvent) {
                        removeEvent();
                    }
                }
            };
        }]);
    }
);
