/*
 * index.js                                        Copyright(c) 2020 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */

/* global require: false, define: false, PAGE: false */

define(
    [
        "angular",
        "jquery",
        "cjt/modules",
        "ngRoute",
        "ngAnimate",
        "ngSanitize",
        "uiBootstrap",

    ],
    function(angular, $) {

        return function() {
            angular.module("whm.createSupportTicket", [
                "cjt2.config.whm.configProvider", // This needs to load before ngRoute
                "ngRoute",
                "ngAnimate",
                "ngSanitize",
                "ui.bootstrap",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/util/parse",
                    "cjt/util/locale",

                    "cjt/views/applicationController",
                    "cjt/directives/alertList",
                    "cjt/services/autoTopService",
                    "cjt/services/whm/breadcrumbService",
                    "app/services/wizardApi",
                    "app/views/wizardController",
                    "app/views/startController",
                    "app/views/authorizeCustomerPortalController",
                    "app/views/termsofserviceController",
                    "app/views/grantController",
                    "app/views/supportInfoController",
                    "app/views/processingController",
                    "app/services/ticketService"
                ], function(BOOTSTRAP, PARSE, LOCALE) {

                    var app = angular.module("whm.createSupportTicket");

                    app.firstLoad = {};

                    // Normalize the data
                    PAGE.is_dns_only              = PARSE.parsePerlBoolean(PAGE.is_dns_only);
                    PAGE.is_tickets_authenticated = PARSE.parsePerlBoolean(PAGE.is_tickets_authenticated);
                    PAGE.is_cpanel_direct         = PARSE.parsePerlBoolean(PAGE.is_cpanel_direct);
                    PAGE.data = {
                        start: {},
                        tos: {},
                        grant: {},
                    };

                    // Inject the state in the application.
                    app.value("pageState", PAGE);
                    var wizardState = {
                        step: 0,
                        maxSteps: 7,
                        footer: false,
                        view: "/start"
                    };

                    if (PAGE.is_tickets_authenticated) {
                        wizardState.maxSteps -= 3;
                    }

                    app.value("wizardState", wizardState);

                    app.config([
                        "$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/start", {
                                controller: "startController",
                                templateUrl: "support/create_support_ticket/views/startView.ptt",
                                breadcrumb: LOCALE.maketext("Select Issue Type")
                            });

                            $routeProvider.when("/authorize-customer-portal/:status?", {
                                controller: "authorizeCustomerPortalController",
                                templateUrl: "support/create_support_ticket/views/authorizeCustomerPortalView.ptt",
                                breadcrumb: LOCALE.maketext("Authorize Customer Portal")
                            });

                            $routeProvider.when("/tos", {
                                controller: "termsofserviceController",
                                templateUrl: "support/create_support_ticket/views/termsofserviceView.ptt",
                                breadcrumb: LOCALE.maketext("Technical Support Agreement")
                            });

                            $routeProvider.when("/grant", {
                                controller: "grantController",
                                templateUrl: "support/create_support_ticket/views/grantView.ptt",
                                breadcrumb: LOCALE.maketext("Authorize Support Access")
                            });

                            $routeProvider.when("/processing", {
                                controller: "processingController",
                                templateUrl: "support/create_support_ticket/views/processingView.ptt",
                                breadcrumb: LOCALE.maketext("Processing")
                            });

                            $routeProvider.when("/supportinfo", {
                                controller: "supportInfoController",
                                templateUrl: "support/create_support_ticket/views/supportInfoView.ptt",
                                breadcrumb: LOCALE.maketext("Support Information")
                            });


                            $routeProvider.otherwise({
                                "redirectTo": "/start"
                            });
                        }
                    ]);

                    app.run([
                        "autoTopService",
                        "breadcrumbService",
                        "ticketService",
                        "wizardState",
                        function(autoTopService, breadcrumbService, ticketService) {
                            autoTopService.initialize();
                            breadcrumbService.initialize();
                            ticketService.setAuthState(PAGE.is_tickets_authenticated);
                            delete PAGE.is_tickets_authenticated;
                        }
                    ]);


                    BOOTSTRAP(document, "whm.createSupportTicket");

                });

            return app;
        };
    }
);
