/*
# domains/index.js                        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require, define, PAGE */

/** @namespace cpanel.domains */

define(
    [
        "angular",
        "cjt/core",
        "app/views/ROUTES",
        "app/views/createDomain",
        "cjt/modules",
        "ngRoute",
        "ngAnimate",
        "cjt/services/alertService",
        "app/services/domains",
        "app/directives/itemLister",
        "app/directives/domainListerViewDirective",
        "app/validators/subdomain",
        "app/validators/domainIsUnique",
        "cjt/directives/callout",
        "cjt/directives/loadingPanel",
        "angular-chosen"
    ],
    function(angular, CJT, ROUTES, CreateDomain) {

        "use strict";

        return function() {

            // First create the application
            angular.module("cpanel.domains", [
                "ngRoute",
                "ngAnimate",
                "cjt2.cpanel",
                "cpanel.domains.domains.service",
                "cpanel.domains.itemLister.directive",
                "cpanel.domains.domainListerView.directive",
                CreateDomain.namespace,
                "cjt2.directives.loadingPanel",
                "cjt2.services.alert",
                "localytics.directives"
            ]);

            var requires = [
                "cjt/bootstrap",
                "cjt/directives/breadcrumbs",
                "app/views/main"
            ];

            ROUTES.forEach(function(route) {
                requires.push("app/views/" + route.controller);
            });

            // Then load the application dependencies
            var app = require(requires, function(BOOTSTRAP) {

                var app = angular.module("cpanel.domains");
                app.value("PAGE", PAGE);
                app.value("ZONE_EDITOR_APP_OBJ", PAGE.zoneEditorAppObj);

                app.value("ITEM_LISTER_CONSTANTS", {
                    TABLE_ITEM_BUTTON_EVENT: "TableItemActionButtonEmitted",
                    ITEM_LISTER_UPDATED_EVENT: "ItemListerUpdatedEvent"
                });

                app.config([
                    "$routeProvider",
                    "$animateProvider",
                    function($routeProvider, $animateProvider) {

                        $animateProvider.classNameFilter(/^((?!no-animate).)*$/);

                        ROUTES.forEach(function(route) {
                            $routeProvider.when(route.route, {
                                controller: route.controller,
                                templateUrl: route.templateUrl,
                                breadcrumb: route.breadcrumb,
                                resolve: route.resolve
                            });
                        });

                        $routeProvider.otherwise({
                            "redirectTo": "/"
                        });

                    }
                ]);

                BOOTSTRAP("#content", "cpanel.domains");

            });

            return app;
        };
    }
);
