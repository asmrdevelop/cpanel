/*
# cjt/services/whm/nvDataService.js                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides nvDataService for whm. Used to get and set
 * name value pairs of personalization data for a user.
 *
 * @module   cjt/services/whm/nvDataService
 * @ngmodule cjt2.services.whm.nvDataService
 */


define([

    // Libraries
    "angular",

    // CJT
    "cjt/io/api",
    "cjt/io/whm-v1-request",
    "cjt/services/nvDataServiceFactory",
    "cjt/io/whm-v1",

    // Angular components
    "cjt/services/APIService"
],
function(angular, API, APIREQUEST, NVDATASERVICEFACTORY) {
    "use strict";

    var module = angular.module("cjt2.services.whm.nvdata", ["cjt2.services.api"]);

    module.factory("nvDataService", [ "APIService", function(APIService) {
        return NVDATASERVICEFACTORY(APIREQUEST, APIService);
    }]);
});
