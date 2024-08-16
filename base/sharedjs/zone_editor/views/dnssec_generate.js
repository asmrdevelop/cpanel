/*
# zone_editor/views/dnssec_generate.js             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/dnssec",
        "uiBootstrap",
        "cjt/services/cpanel/componentSettingSaverService"
    ],
    function(angular, LOCALE, _, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecGenerate";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecGenerateController",
            [
                "$scope",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "defaultInfo",
                "$document",
                "componentSettingSaverService",
                function(
                    $scope,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    defaultInfo,
                    $document,
                    componentSettingSaverService
                ) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.settings = {};
                    var SAVED_SETTINGS_DEFAULTS = {
                        showAllHelp: true,
                    };

                    dnssec.isRTL = defaultInfo.isRTL;

                    // setup defaults
                    dnssec.details = {
                        setup: "classic",
                        algorithm: 8,
                        active: true
                    };

                    dnssec.backToListView = function() {
                        return DnsSecService.goToInnerView("", dnssec.domain);
                    };

                    dnssec.goToDSRecords = function(keyId) {
                        return DnsSecService.goToInnerView("dsrecords", dnssec.domain, keyId);
                    };

                    dnssec.toggleHelp = function() {
                        dnssec.settings.showAllHelp = !dnssec.settings.showAllHelp;
                        componentSettingSaverService.set("zone_editor_dnssec", dnssec.settings);
                    };

                    dnssec.isClassicSetup = function() {
                        return dnssec.details.setup === "classic";
                    };

                    /**
                     * Ensure we select ECDSA when 'simple' is selected
                     */
                    dnssec.onSetupSelect = function($event) {
                        var value = $event.target.value;
                        if (value === "simple") {
                            dnssec.details.algorithm = 13;
                        }
                    };

                    dnssec.generate = function(details) {
                        return DnsSecService.generate(dnssec.domain, details.algorithm, details.setup, details.active)
                            .then(function(result) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key generated successfully"),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });

                                dnssec.goToDSRecords(result.enabled[dnssec.domain].new_key_id);
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
                        $document[0].body.scrollIntoView();  // scroll to top of window

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
