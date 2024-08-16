/*
# cjt/services/cpanel/nvDataService.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/**
 * Provides nvDataService for cpanel. Used to get and set
 * name value pairs of personalization data for a user.
 *
 * @module   cjt/services/cpanel/nvDataService
 * @ngmodule cjt2.services.cpanel.nvDataService
 */

define([

    // Libraries
    "angular",

    // CJT
    "cjt/io/api",
    "cjt/io/uapi-request",
    "cjt/services/nvDataServiceFactory",
    "cjt/io/uapi",

    // Angular components
    "cjt/services/APIService"
],
function(angular, API, APIREQUEST, NVDATASERVICEFACTORY) {
    "use strict";

    var module = angular.module("cjt2.services.cpanel.nvdata", ["cjt2.services.api"]);

    module.factory("nvDataService", [ "APIService", function(APIService) {
        return NVDATASERVICEFACTORY(APIREQUEST, APIService);
    }]);
});
