/*
# zone_editor/views/dnssec_import.js               Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "app/services/dnssec",
        "uiBootstrap",
        "cjt/services/cpanel/componentSettingSaverService"
    ],
    function(angular, _, LOCALE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecImport";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecImportController",
            [
                "$scope",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "defaultInfo",
                "componentSettingSaverService",
                function(
                    $scope,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    defaultInfo,
                    componentSettingSaverService) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;
                    dnssec.keyId = $routeParams.keyid;

                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.settings = {};
                    var SAVED_SETTINGS_DEFAULTS = {
                        showAllHelp: true,
                    };

                    dnssec.isRTL = defaultInfo.isRTL;

                    // setup defaults
                    dnssec.details = {
                        keyToImport: "",
                        keyType: "KSK"
                    };

                    dnssec.goToInnerView = function(view, keyId) {
                        return DnsSecService.goToInnerView(view, dnssec.domain, keyId);
                    };

                    dnssec.backToListView = function() {
                        alertService.clear(void 0, "zoneEditor");
                        return dnssec.goToInnerView("");
                    };

                    dnssec.goToDSRecords = function(keyId) {
                        return dnssec.goToInnerView("dsrecords", keyId);
                    };

                    dnssec.toggleHelp = function() {
                        dnssec.settings.showAllHelp = !dnssec.settings.showAllHelp;
                        componentSettingSaverService.set("zone_editor_dnssec", dnssec.settings);
                    };

                    dnssec.importKey = function(details) {
                        dnssec.importForm.$submitted = true;

                        if (!dnssec.importForm.$valid || dnssec.importForm.$pending) {
                            return;
                        }

                        return DnsSecService.importKey(dnssec.domain, details.keyType, details.keyToImport)
                            .then(function(result) {
                                alertService.clear(void 0, "zoneEditor");
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key imported successfully"),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });

                                dnssec.goToDSRecords(result.new_key_id);
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            });
                    };


                    dnssec.init = function() {

                        // get the settings for the app
                        var settings = componentSettingSaverService.getCached("zone_editor_dnssec").cachedValue;
                        _.merge(dnssec.settings, SAVED_SETTINGS_DEFAULTS, settings || {});

                        if (!Features.dnssec) {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        }
                    };

                    dnssec.init();
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };
    }
);
