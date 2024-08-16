/*
# zone_editor/views/dnssec_ds_records.js           Copyright 2022 cPanel, L.L.C.
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
        "cjt/util/parse",
        "app/services/features",
        "cjt/directives/actionButtonDirective",
        "cjt/directives/alertList",
        "cjt/services/alertService",
        "app/services/dnssec",
        "uiBootstrap"
    ],
    function(angular, _,  LOCALE, PARSE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssecDSRecords";
        var app = angular.module(MODULE_NAMESPACE, []);

        app.controller(
            "DnsSecDSRecordsController",
            ["$scope", "$q", "$routeParams", "DnsSecService", FeaturesService.serviceName, "alertService", "defaultInfo",
                function($scope, $q, $routeParams, DnsSecService, Features, alertService, defaultInfo) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;
                    dnssec.keyId = $routeParams.keyid;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";

                    dnssec.keyContent = {};

                    dnssec.isRTL = defaultInfo.isRTL;

                    dnssec.goToInnerView = function(view, keyId) {
                        return DnsSecService.goToInnerView(view, dnssec.domain, keyId);
                    };

                    dnssec.backToListView = function() {
                        return dnssec.goToInnerView("");
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

                    function getKeyDetails(keys, keyId) {
                        var key = {};
                        keyId = parseInt(keyId);
                        for (var i = 0, len = keys.length; i < len; i++) {
                            var tempkey = keys[i];
                            if (tempkey.key_id === keyId) {
                                key = {
                                    active: PARSE.parsePerlBoolean(tempkey.active),
                                    algoDesc: tempkey.algo_desc,
                                    algoNum: tempkey.algo_num,
                                    algoTag: tempkey.algo_tag,
                                    flags: tempkey.flags,
                                    keyTag: tempkey.key_tag,
                                    keyId: tempkey.key_id,
                                    bits: tempkey.bits,
                                    bitsMsg: LOCALE.maketext("[quant,_1,bit,bits]", tempkey.bits),
                                    created: (tempkey.created !== void 0 && tempkey.created !== "0") ? LOCALE.local_datetime(tempkey.created, "datetime_format_medium") : LOCALE.maketext("Unknown"),
                                    digests: tempkey.digests.map(function(key) {
                                        return {
                                            algoDesc: key.algo_desc,
                                            algoNum: key.algo_num,
                                            digest: key.digest,
                                        };
                                    })
                                };
                                return key;
                            }
                        }
                        return;
                    }

                    dnssec.load = function() {
                        dnssec.is_loading = true;
                        return DnsSecService.fetch(dnssec.domain)
                            .then(function(result) {
                                var content;
                                if (result.length) {
                                    content = getKeyDetails(result, dnssec.keyId);
                                }

                                if (!content) {
                                    dnssec.loading_error = true;
                                    dnssec.loading_error_message = LOCALE.maketext("The [asis,DNSSEC] key you were trying to view does not exist.");
                                }
                                dnssec.keyContent = content;
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
                        if (Features.dnssec) {
                            return dnssec.load();
                        } else {
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
