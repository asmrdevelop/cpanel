/*
# zone_editor/views/dnssec_export.js               Copyright 2022 cPanel, L.L.C.
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

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecExport";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecExportController",
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

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.isRTL = defaultInfo.isRTL;

                    dnssec.backToListView = function() {
                        return DnsSecService.goToInnerView("", dnssec.domain);
                    };

                    dnssec.putOnClipboard = function(text) {
                        try {
                            DnsSecService.copyTextToClipboard(text);
                            alertService.add({
                                type: "success",
                                message: LOCALE.maketext("Successfully copied to the clipboard."),
                                closeable: true,
                                replace: false,
                                autoClose: 10000,
                                group: "zoneEditor"
                            });
                        } catch (error) {
                            alertService.add({
                                type: "danger",
                                message: _.escape(error),
                                closeable: true,
                                replace: false,
                                group: "zoneEditor"
                            });
                        }
                    };

                    dnssec.load = function() {
                        dnssec.is_loading = true;
                        return DnsSecService.exportKey(dnssec.domain, dnssec.keyId)
                            .then(function(result) {
                                dnssec.keyContent = result.key_content;
                                dnssec.keyTag = result.key_tag;
                                dnssec.keyType = result.key_type;
                            })
                            .catch(function(error) {
                                alertService.add({
                                    type: "danger",
                                    message: _.escape(error),
                                    closeable: true,
                                    replace: false,
                                    group: "zoneEditor"
                                });
                            })
                            .finally(function() {
                                dnssec.is_loading = false;
                            });
                    };

                    dnssec.init = function() {
                        if (!Features.dnssec) {
                            dnssec.loading_error = true;
                            dnssec.loading_error_message = LOCALE.maketext("This feature is not available to your account.");
                        } else {
                            dnssec.load();
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
