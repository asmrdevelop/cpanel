/*
# zone_editor/index.js                             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require: false, define: false, PAGE: false */

define(
    [
        "angular",
        "app/services/features",
        "app/services/recordTypes",

        // Shared Zone Files
        "shared/js/zone_editor/views/domain_selection",
        "shared/js/zone_editor/views/manage",
        "shared/js/zone_editor/views/dnssec",
        "shared/js/zone_editor/views/dnssec_generate",
        "shared/js/zone_editor/views/dnssec_ds_records",
        "shared/js/zone_editor/views/dnssec_import",
        "shared/js/zone_editor/views/dnssec_export",
        "shared/js/zone_editor/views/dnssec_dnskey",
        "shared/js/zone_editor/directives/convert_to_full_record_name",
        "cjt/core",
        "shared/js/zone_editor/directives/base_validators",
        "shared/js/zone_editor/directives/dmarc_validators",
        "shared/js/zone_editor/directives/caa_validators",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "app/services/dnssec",
        "app/services/zones",
    ],
    function(angular,
        FeaturesService,
        RecordTypesService,
        DomainSelectionView,
        ManageView,
        DNSSECView,
        DNSSECGenerateView,
        DNSSECDSRecordsView,
        DNSSECImportView,
        DNSSECExportView,
        DNSSECDnsKeyView,
        ConvertToFullRecordName,
        CJT
    ) {

        "use strict";

        return function() {

            // First create the application
            angular.module("cpanel.zoneEditor", [
                "ngRoute",
                "ui.bootstrap",
                "cjt2.cpanel",
                "cpanel.zoneEditor.services.dnssec",
                "cpanel.zoneEditor.services.zones",
                RecordTypesService.namespace,
                FeaturesService.namespace,
                DomainSelectionView.namespace,
                ManageView.namespace,
                DNSSECView.namespace,
                DNSSECGenerateView.namespace,
                DNSSECDSRecordsView.namespace,
                DNSSECImportView.namespace,
                DNSSECExportView.namespace,
                DNSSECDnsKeyView.namespace,
                ConvertToFullRecordName.namespace,
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/locale",
                    "cjt/directives/breadcrumbs",
                    "cjt/services/alertService",
                    "cjt/directives/alert",
                    "cjt/directives/alertList",
                    "cjt/services/cpanel/componentSettingSaverService",
                    "app/services/page_data_service",
                    "app/services/domains",
                    "app/services/zones",
                    "app/services/dnssec",
                    "app/services/features",
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("cpanel.zoneEditor");

                    app.value("RECORD_TYPES", PAGE.RECORD_TYPES);

                    // setup the defaults for the various services.
                    app.factory("defaultInfo", [
                        "pageDataService",
                        function(pageDataService) {
                            return pageDataService.prepareDefaultInfo(PAGE);
                        },
                    ]);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/list", {
                                controller: "ListDomainsController",
                                controllerAs: "list",
                                templateUrl: "views/domain_selection.ptt",
                                breadcrumb: {
                                    id: "domains_list",
                                    name: LOCALE.maketext("Domains"),
                                    path: "/list",
                                },
                            });

                            $routeProvider.when("/manage", {
                                controller: "ManageZoneRecordsController",
                                controllerAs: "manage",
                                templateUrl: "views/manage.ptt",
                                breadcrumb: {
                                    id: "manage",
                                    name: LOCALE.maketext("Manage Zone"),
                                    path: "/manage/",
                                    parentID: "domains_list",
                                },
                            });

                            $routeProvider.when("/dnssec", {
                                controller: "DnsSecController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec.ptt",
                                breadcrumb: {
                                    id: "dnssec",
                                    name: "DNSSEC",
                                    path: "/dnssec/",
                                    parentID: "domains_list",
                                },
                            });

                            $routeProvider.when("/dnssec/generate", {
                                controller: "DnsSecGenerateController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_generate.ptt",
                                breadcrumb: {
                                    id: "dnssecGenerate",
                                    name: LOCALE.maketext("Generate"),
                                    path: "/dnssec/generate",
                                    parentID: "dnssec",
                                },
                            });

                            $routeProvider.when("/dnssec/dsrecords", {
                                controller: "DnsSecDSRecordsController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_ds_records.ptt",
                                breadcrumb: {
                                    id: "dnssecDSRecords",
                                    name: LOCALE.maketext("[asis,DS] Records"),
                                    path: "/dnssec/dsrecords",
                                    parentID: "dnssec",
                                },
                            });

                            $routeProvider.when("/dnssec/import", {
                                controller: "DnsSecImportController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_import.ptt",
                                breadcrumb: {
                                    id: "dnssecImport",
                                    name: LOCALE.maketext("Import"),
                                    path: "/dnssec/import",
                                    parentID: "dnssec",
                                },
                            });

                            $routeProvider.when("/dnssec/export", {
                                controller: "DnsSecExportController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_export.ptt",
                                breadcrumb: {
                                    id: "dnssecExport",
                                    name: LOCALE.maketext("Export"),
                                    path: "/dnssec/export",
                                    parentID: "dnssec",
                                },
                            });

                            $routeProvider.when("/dnssec/dnskey", {
                                controller: "DnsSecDnskeyController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_dnskey.ptt",
                                breadcrumb: {
                                    id: "dnssecDNSKEY",
                                    name: LOCALE.maketext("Public [asis,DNSKEY]"),
                                    path: "/dnssec/dnskey",
                                    parentID: "dnssec",
                                },
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/list",
                            });
                        },
                    ]);

                    app.run([
                        "componentSettingSaverService",
                        function(
                            componentSettingSaverService
                        ) {
                            componentSettingSaverService.register("zone_editor_dnssec");
                        },
                    ]);

                    BOOTSTRAP("#content", "cpanel.zoneEditor");

                });

            return app;
        };
    }
);
