/*
# zone_editor/services/features.js                Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular"
    ],
    function(angular) {

        "use strict";

        var MODULE_NAMESPACE = "cpanel.zoneEditor.services.features";
        var SERVICE_NAME = "FeaturesService";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_FACTORY = app.factory(SERVICE_NAME, ["defaultInfo", function(defaultInfo) {

            var store = {};

            store.dnssec = false;
            store.mx = false;
            store.simple = false;
            store.advanced = false;

            store.init = function() {
                store.dnssec = defaultInfo.has_dnssec_feature;
                store.mx = defaultInfo.has_mx_feature;
                store.simple = defaultInfo.has_simple_feature;
                store.advanced = defaultInfo.has_adv_feature;
            };

            store.init();

            return store;
        }]);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);
