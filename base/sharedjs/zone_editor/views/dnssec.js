/*
# zone_editor/views/dnssec.js                      Copyright 2022 cPanel, L.L.C.
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
        "cjt/directives/alert",
        "cjt/services/alertService",
        "app/services/dnssec",
        "uiBootstrap"
    ],
    function(angular, _, LOCALE, PARSE, FeaturesService) {
        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.views.dnssec";
        var app = angular.module(MODULE_NAMESPACE, []);

        /**
         * Create Controller for DNSSEC view
         *
         * @module DnsSecController
         */
        app.controller(
            "DnsSecController", [
                "$scope",
                "$q",
                "$routeParams",
                "DnsSecService",
                FeaturesService.serviceName,
                "alertService",
                "$uibModal",
                function(
                    $scope,
                    $q,
                    $routeParams,
                    DnsSecService,
                    Features,
                    alertService,
                    $uibModal) {
                    var dnssec = this;
                    dnssec.domain = $routeParams.domain;

                    dnssec.is_loading = false;
                    dnssec.loading_error = false;
                    dnssec.loading_error_message = "";
                    dnssec.is_generating = false;
                    dnssec.keys = [];
                    dnssec.isRTL = PAGE.isRTL;

                    var EPOCH_FOR_TODAY = Date.now() / 1000;

                    /**
                     * Creates a controller for the Deactivate Key modal
                     *
                     * @method DeactivateKeyModalController
                     * @param {object} $uibModalInstance - the modal object
                     * @param {object} key - a key object
                     */
                    function DeactivateKeyModalController($uibModalInstance, key) {
                        var ctrl = this;
                        ctrl.key = key;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return DnsSecService.deactivate(dnssec.domain, key.key_id)
                                .then(function(result) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("Key “[_1]” successfully deactivated.", key.key_tag),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor"
                                    });
                                    key.active = false;
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
                                    $uibModalInstance.close();
                                });
                        };
                    }
                    DeactivateKeyModalController.$inject = ["$uibModalInstance", "key"];

                    /**
                     * Creates a controller for the Delete Key modal
                     *
                     * @method DeleteKeyModalController
                     * @param {object} $uibModalInstance - the modal object
                     * @param {object} key - a key object
                     */
                    function DeleteKeyModalController($uibModalInstance, key) {
                        var ctrl = this;
                        ctrl.key = key;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return DnsSecService.remove(dnssec.domain, key.key_id)
                                .then(function(result) {
                                    alertService.add({
                                        type: "success",
                                        message: LOCALE.maketext("Key “[_1]” successfully deleted.", key.key_tag),
                                        closeable: true,
                                        replace: false,
                                        autoClose: 10000,
                                        group: "zoneEditor"
                                    });
                                    return dnssec.load();
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
                                    $uibModalInstance.close();
                                });
                        };
                    }
                    DeleteKeyModalController.$inject = ["$uibModalInstance", "key"];

                    /**
                     * Creates a controller for the Generate Keys modal
                     *
                     * @method GenerateModalController
                     * @param {object} $uibModalInstance - the modal object
                     */
                    function GenerateModalController($uibModalInstance) {
                        var ctrl = this;

                        ctrl.cancel = function() {
                            $uibModalInstance.dismiss("cancel");
                        };
                        ctrl.confirm = function() {
                            return dnssec.generate()
                                .finally(function() {
                                    $uibModalInstance.close();
                                });
                        };
                        ctrl.goToGenerate = function() {
                            $uibModalInstance.dismiss("cancel");
                            return dnssec.goToInnerView("generate");
                        };
                    }
                    GenerateModalController.$inject = ["$uibModalInstance"];

                    dnssec.goToInnerView = function(view, keyId) {
                        return DnsSecService.goToInnerView(view, dnssec.domain, keyId);
                    };

                    function parseDnssecKeys(dnssecKeys) {
                        for (var i = 0, len = dnssecKeys.length; i < len; i++) {
                            var key = dnssecKeys[i];
                            key.active = PARSE.parsePerlBoolean(key.active);
                            key.bits_msg = LOCALE.maketext("[quant,_1,bit,bits]", key.bits);
                            key.isExpanded = false;
                            if (key.created !== void 0 && key.created !== "0") {
                                var suggestedRotationDate = DnsSecService.getSuggestedKeyRotationDate(key.created, key.key_type);
                                key.should_rotate = suggestedRotationDate < EPOCH_FOR_TODAY;
                                key.created = LOCALE.local_datetime(key.created, "datetime_format_medium");
                            } else {
                                key.created = LOCALE.maketext("Unknown");
                            }
                        }
                    }

                    dnssec.expandKey = function(key, isExpanded) {
                        key.isExpanded = isExpanded;
                    };

                    dnssec.activate = function(key) {
                        return DnsSecService.activate(dnssec.domain, key.key_id)
                            .then(function(result) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key “[_1]” successfully activated.", key.key_tag),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });
                                key.active = true;
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

                    dnssec.confirmDeactivateKey = function(key) {
                        $uibModal.open({
                            templateUrl: "dnssec_confirm_deactivate.html",
                            controller: DeactivateKeyModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                key: function() {
                                    return key;
                                },
                            }
                        });
                    };

                    dnssec.confirmDeleteKey = function(key) {
                        $uibModal.open({
                            templateUrl: "dnssec_confirm_delete.html",
                            controller: DeleteKeyModalController,
                            controllerAs: "ctrl",
                            resolve: {
                                key: function() {
                                    return key;
                                },
                            }
                        });
                    };

                    dnssec.launchGenerateModal = function(key) {
                        $uibModal.open({
                            templateUrl: "quick_generate.html",
                            controller: GenerateModalController,
                            controllerAs: "ctrl",
                        });
                    };

                    dnssec.generate = function() {
                        dnssec.is_generating = true;
                        return DnsSecService.generate(dnssec.domain)
                            .then(function(result) {
                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Key generated successfully."),
                                    closeable: true,
                                    replace: false,
                                    autoClose: 10000,
                                    group: "zoneEditor"
                                });

                                return dnssec.goToInnerView("dsrecords", result.enabled[dnssec.domain].new_key_id);
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
                                dnssec.is_generating = false;
                            });
                    };

                    dnssec.load = function() {
                        dnssec.keys = [];
                        dnssec.is_loading = true;
                        return DnsSecService.fetch(dnssec.domain)
                            .then(function(result) {
                                dnssec.keys = result;
                                parseDnssecKeys(dnssec.keys);
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
                            dnssec.load();
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
