/*
# zone_editor/index.js                             Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* require: false, define: false, PAGE: false */

define(
    [
        "angular",
        "app/services/features",
        "app/services/recordTypes",
        "app/services/domains",
        "app/services/zones",
        "app/services/page_data_service",

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
        "shared/js/zone_editor/directives/ds_validators",
        "shared/js/zone_editor/directives/loc_validators",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "app/services/dnssec",
    ],
    function(angular,
        FeaturesService,
        RecordTypesService,
        DomainsService,
        ZonesService,
        PageDataService,
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
            angular.module("whm.zoneEditor", [
                "ngRoute",
                "ui.bootstrap",
                "cjt2.whm",
                "whm.zoneEditor.services.dnssec",
                DomainsService.namespace,
                ZonesService.namespace,
                PageDataService.namespace,
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

                    var app = angular.module("whm.zoneEditor");

                    app.value("RECORD_TYPES", PAGE.RECORD_TYPES);

                    // setup the defaults for the various services.
                    app.factory("defaultInfo", [
                        PageDataService.serviceName,
                        function(pageDataService) {
                            return pageDataService.prepareDefaultInfo(PAGE);
                        },
                    ]);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            $routeProvider.when("/", {
                                controller: "ListDomainsController",
                                controllerAs: "list",
                                templateUrl: "views/domain_selection.ptt",
                            });

                            $routeProvider.when("/manage/", {
                                controller: "ManageZoneRecordsController",
                                controllerAs: "manage",
                                templateUrl: "views/manage.ptt",
                            });

                            $routeProvider.when("/manage/copyzone", {
                                controller: "ManageZoneRecordsController",
                                controllerAs: "manage",
                                templateUrl: "views/copy_zone_file.ptt",
                            });

                            $routeProvider.when("/dnssec/", {
                                controller: "DnsSecController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec.ptt",
                            });

                            $routeProvider.when("/dnssec/generate", {
                                controller: "DnsSecGenerateController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_generate.ptt",
                            });

                            $routeProvider.when("/dnssec/dsrecords", {
                                controller: "DnsSecDSRecordsController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_ds_records.ptt",
                            });

                            $routeProvider.when("/dnssec/import", {
                                controller: "DnsSecImportController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_import.ptt",
                            });

                            $routeProvider.when("/dnssec/export", {
                                controller: "DnsSecExportController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_export.ptt",
                            });

                            $routeProvider.when("/dnssec/dnskey", {
                                controller: "DnsSecDnskeyController",
                                controllerAs: "dnssec",
                                templateUrl: "views/dnssec_dnskey.ptt",
                            });

                            $routeProvider.otherwise({
                                "redirectTo": "/",
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

                    BOOTSTRAP("#contentContainer", "whm.zoneEditor");

                });

            return app;
        };
    }
);
