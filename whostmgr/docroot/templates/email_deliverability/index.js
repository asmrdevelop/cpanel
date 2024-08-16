/*
# email_deliverability/index.js                      Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require, define, PAGE */

/** @namespace cpanel.emailDeliverability */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "app/controllers/ROUTES",
        "app/controllers/route",
        "shared/js/email_deliverability/services/domains",
        "shared/js/email_deliverability/filters/htmlSafeString",
        "app/decorators/paginationDecorator",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1",
        "ngRoute",
        "ngAnimate",
        "cjt/modules",
        "angular-chosen",
        "cjt/directives/breadcrumbs",
        "cjt/services/alertService",
        "cjt/directives/loadingPanel",
        "shared/js/email_deliverability/views/manageDomain",
        "shared/js/email_deliverability/views/manageDomainSPF",
        "shared/js/email_deliverability/views/manageDomainDKIM",
        "shared/js/email_deliverability/views/listDomains",
    ],
    function(angular, _, CJT, ROUTES, RouteController, DomainsService, SafeStringFilter, PaginationDecorator, APIRequest) {

        "use strict";

        CJT.config.html5Mode = false;

        /**
         * App Controller for Email Deliverability
         *
         * @module index
         *
         * @memberof whm.emailDeliverability
         *
         */

        return function() {

            var APP_MODULE_NAME = "whm.emailDeliverability";

            var appModules = [
                "ngRoute",
                "ngAnimate",
                "cjt2.whm",
                "cjt2.directives.loadingPanel",
                "cjt2.services.alert",
                DomainsService.namespace,
                SafeStringFilter.namespace,
                RouteController.namespace,
                PaginationDecorator.namespace
            ];

            var cjtDependentModules = [
                "cjt/bootstrap"
            ];

            ROUTES.forEach(function(route) {
                appModules.push("shared.emailDeliverability.views." + route.controllerAs);
            });

            // First create the application
            angular.module(APP_MODULE_NAME, appModules);

            // Then load the application dependencies
            var app = require(cjtDependentModules, function(BOOTSTRAP) {

                var app = angular.module(APP_MODULE_NAME);
                app.value("PAGE", PAGE);
                app.value("ADD_RESOURCE_PANEL", CJT.buildFullPath("email_deliverability/views/additionalResourcesPanel.ptt"));

                app.factory("APIInitializer", function() {

                    var APIInitializer = function() {

                        function _apiTranslator(module, func) {
                            if (module === "Batch" && func === "strict") {
                                return ["", "batch"];
                            }
                            return ["", func];
                        }

                        function _initialize(module, func) {

                            var apiCall = new APIRequest.Class();
                            return apiCall.initialize.apply(apiCall, this.apiTranslator(module, func) );

                        }

                        function _buildBatchCommandItem(module, func, paramsObj) {
                            var commandString = func;

                            if (paramsObj) {
                                var commandParams = [];
                                angular.forEach(paramsObj, function(value, key) {
                                    commandParams.push(key + "=" + encodeURIComponent(value));
                                });

                                commandString += "?" + commandParams.join("&");
                            }

                            return commandString;
                        }

                        this.init = _initialize.bind(this);
                        this.buildBatchCommandItem = _buildBatchCommandItem.bind(this);
                        this.apiTranslator = _apiTranslator.bind(this);

                    };

                    return new APIInitializer();

                });

                app.value("ITEM_LISTER_CONSTANTS", {
                    TABLE_ITEM_BUTTON_EVENT: "TableItemActionButtonEmitted",
                    ITEM_LISTER_UPDATED_EVENT: "ItemListerUpdatedEvent"
                });

                app.value("RECORD_STATUS_CONSTANTS", {
                    VALID: "validRecordStatus",
                    OUT_OF_SYNC: "outOfSyncRecordStatus",
                    MISSING: "missingRecordStatus",
                    TOO_MANY: "tooManyRecordStatus",
                    LOADING: null
                });

                app.config([
                    "$routeProvider",
                    "$animateProvider",
                    function($routeProvider, $animateProvider) {

                        $animateProvider.classNameFilter(/^((?!no-animate).)*$/);

                        ROUTES.forEach(function(route) {
                            $routeProvider.when(route.route, route);
                        });

                        $routeProvider.otherwise({
                            "redirectTo": "/"
                        });

                    }
                ]);

                BOOTSTRAP("#content", APP_MODULE_NAME);

            });

            return app;
        };
    }
);
