/*
 * tools/services/statisticsService.js           Copyright(c) 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global define: false */

define(
    [

        // Libraries
        "lodash",
        "angular",
        "cjt/io/uapi-request",
        "cjt/services/APICatcher",
    ],
    function(_, angular, APIREQUEST) {
        "use strict";

        // Fetch the current application
        var app = angular.module("App");

        /**
         * Setup the account list model's API service
         */
        app.factory("statisticsService", ["APICatcher",
            function(api) {

                var idsToShowWarningsInGlass = ["disk_usage", "cachedmysqldiskusage", "bandwidth"];

                function _mungeData(data) {
                    for (var i = 0; i < data.length; i++) {
                        var item = data[i];

                        item.maximum = item.maximum && parseInt( item.maximum, 10 );

                        var isLimited = (item.maximum !== null);
                        var percent = isLimited ? parseFloat((100 * item.usage / item.maximum).toFixed(2)) : 0;

                        var isWarningShown = false;
                        var isActionButtonShown = false;

                        if (percent >= 80) {
                            isActionButtonShown = true;
                            if (idsToShowWarningsInGlass.includes(item.id)) {
                                isWarningShown = true;
                            }
                        }

                        _.assign(
                            item,
                            {
                                isLimited: isLimited,
                                percent: percent,
                                needFix: percent >= 60,
                                showWarning: isWarningShown,
                                showActionButton: isActionButtonShown,
                            }
                        );
                    }

                    return data;
                }

                // return the factory interface
                return {

                    /**
                     * Get extended stats.
                     * @return {Promise} - Promise that will fulfill the request.
                     */
                    fetchExtendedStats: function() {
                        var apicall = new APIREQUEST.Class().initialize("ResourceUsage", "get_usages");
                        return api.promise(apicall).then( function(resp) {
                            _mungeData(resp.data);
                            return resp.data;
                        } );
                    },
                };
            },
        ]);
    }
);
