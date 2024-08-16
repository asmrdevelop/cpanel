/*
# cjt/services/autoTopService.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [

        // Libraries
        "angular",
        "jquery"
    ],
    function(angular, $) {

        var module = angular.module("cjt2.services.autoTop", []);

        /**
         * The autoTopService will automatically scroll to the top of the view port on
         * each view change. To start the service, call autoTopService.initialize() when
         * your app starts.
         */
        module.factory("autoTopService", ["$rootScope", "$location", "$anchorScroll", function($rootScope, $location, $anchorScroll) {

            var removeEvent;

            return {

                /**
                 * Start the service
                 * @method initialize
                 */
                initialize: function() {

                    // register listener to watch route changes
                    removeEvent = $rootScope.$on( "$routeChangeStart", function(event, next, current) {
                        if (!current) {
                            return;
                        }

                        // ensure new views are scrolled to the top on load
                        $location.hash("top").replace();
                        $anchorScroll();
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
