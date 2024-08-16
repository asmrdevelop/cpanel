/*
# templates/update_config/services/updateConfigService.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "cjt/io/api",
        "cjt/services/APIService",
    ],
    function(angular, APIREQUEST) {

        "use strict";

        var app = angular.module("whm.updateConfig.updateConfigurationService", []);

        app.factory(
            "updateConfigService",
            ["$q", "APIService", function($q, APIService) {

                var UpdateConfigService = function() {
                    APIService.call(this);
                };
                UpdateConfigService.prototype = Object.create(APIService.prototype);

                angular.extend(UpdateConfigService.prototype, {

                    /**
                     * Enables automatic daily updates for cPanel, RPMs, and SpamAssassin.
                     *
                     * @method - enableAutomaticUpdates
                     * @returns {Promise} - When resolved, the config settings have been saved. When rejected, returns a descriptive error message if available.
                     */
                    enableAutomaticUpdates: function enableAutomaticUpdates() {
                        var apiCall = new APIREQUEST.Class();
                        var apiArgs = {
                            "UPDATES": "daily",
                            "RPMUP": "daily",
                            "SARULESUP": "daily"
                        };

                        apiCall.initialize("", "update_updateconf", apiArgs);

                        return this.deferred(apiCall).promise;
                    }
                });

                return new UpdateConfigService();
            }
            ]);
    }
);
