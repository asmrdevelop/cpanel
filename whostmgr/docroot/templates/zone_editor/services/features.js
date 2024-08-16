/*
# zone_editor/services/features.js                Copyright 2022 cPanel, L.L.C.
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

        var MODULE_NAMESPACE = "whm.zoneEditor.services.features";
        var SERVICE_NAME = "FeaturesService";
        var app = angular.module(MODULE_NAMESPACE, []);
        var SERVICE_FACTORY = function(defaultInfo) {

            var store = {};

            store.dnssec = false;
            store.mx = false;
            store.simple = false;
            store.advanced = false;
            store.whmOnly = false;

            store.init = function() {
                store.dnssec = defaultInfo.has_dnssec_feature;
                store.mx = defaultInfo.has_mx_feature;
                store.simple = defaultInfo.has_simple_feature;
                store.advanced = defaultInfo.has_adv_feature;
                store.whmOnly = defaultInfo.has_whmOnly_feature;
            };

            store.init();

            return store;
        };
        app.factory(SERVICE_NAME, ["defaultInfo", SERVICE_FACTORY]);

        return {
            "class": SERVICE_FACTORY,
            "serviceName": SERVICE_NAME,
            "namespace": MODULE_NAMESPACE
        };
    }
);
