/*
 * share/libraries/cjt2/src/services/viewApi.js
 *                                                 Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [
        "angular",
        "cjt/services/alertService"
    ],
    function(angular) {

        var module = angular.module("cjt2.services.viewNavigationApi", [ "cjt2.services.alert" ]);

        module.factory("viewNavigationApi", [
            "$location",
            "alertService",
            function(
                $location,
                alertService
            ) {
                return {

                    /**
                     * Loads the specified view using the location service. Note that the current query
                     * string will be discarded aside from the debug and cache_bust flags unless. If you
                     * wish to include additional query parameters, you must include them in the query
                     * object argument.
                     *
                     * @method loadView
                     * @param {String} view        The path of the view to load, relative to the docroot.
                     * @param {Object} [query]     Optional. These keys/values will be used to create the new view's query string.
                     * @param {Object} [options]   Optional. A hash of additional options.
                     *     @param {Boolean} [options.clearAlerts]    If true, the default alert group in the alertService will be cleared.
                     *     @param {Boolean} [options.replaceState]   If true, the current history state will be replaced by the new view.
                     * @return {$location}         The Angular $location service used to perform the view changes.
                     */
                    loadView: function(view, query, options) {

                        // Grab the old dev flag values
                        var debugVal = $location.search().debug;
                        var cacheVal = $location.search().cache_bust;

                        options = options || {};

                        // Change the path
                        $location.path(view);

                        // Update the search
                        $location.search({}); // Clear the search for the new view
                        angular.forEach(query, function(val, key) {
                            $location.search(key, val);
                        });

                        // Bring over the debug-related flags
                        if (angular.isDefined(debugVal)) {
                            $location.search("debug", debugVal);
                        }
                        if (angular.isDefined(cacheVal)) {
                            $location.search("cache_bust", cacheVal);
                        }

                        // Clear any alerts, if desired
                        if (options.clearAlerts) {
                            alertService.clear();
                        }

                        // Set the replaceState, if desired
                        if (options.replaceState) {
                            $location.replace();
                        }

                        return $location;
                    }
                };
            }
        ]);
    }
);
