/*
# whostmgr/docroot/templates/mail_blocked_tlds/index.js
                                                   Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */

define(
    [
        "lodash",
        "angular",
        "punycode",
        "cjt/util/locale",
        "app/services/parser",
        "cjt/core",
        "cjt/util/parse",
        "cjt/modules",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
    ],
    function mailBlockedDomainsDefine(_, angular, PUNYCODE, LOCALE, PARSER) {
        "use strict";

        var PAGE = window.PAGE;

        return function inDefine() {
            angular.module("whm.mailBlockedDomains", [
                "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
                "ui.bootstrap",
                "cjt2.whm",
                "cjt2.services.alert",
                "whm.mailBlockedDomains.Service",
            ] );

            return require(
                [
                    "cjt/bootstrap",
                    "uiBootstrap",
                    "app/services/manageService",
                    "app/validators/domainList",
                ],
                function toRequire(BOOTSTRAP) {
                    var app = angular.module("whm.mailBlockedDomains");

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "manageService",
                        function($rootScope, $scope, manageService) {
                            manageService.setSavedDomains(PAGE.initial_blocked_domains);

                            var state = {
                                viewPunycodeYN: PAGE.initial_view_punycode,
                            };

                            function _parseDomainsFromView() {
                                return PARSER.parseDomainsFromText(state.domainsText);
                            }

                            function _pushDomainsToView(domains) {
                                state.domainsText = domains.join("\n");
                            }

                            function _syncDomainsText() {
                                var domains = manageService.getSavedDomains();

                                if (state.viewPunycodeYN) {
                                    domains = domains.map( PUNYCODE.toASCII );
                                }

                                _pushDomainsToView(domains);
                            }

                            _syncDomainsText();

                            _.assign(
                                $scope,
                                {
                                    updateViewPunycode: function updateViewPunycode() {
                                        var domains = _parseDomainsFromView();
                                        var xform = PUNYCODE[ state.viewPunycodeYN ? "toASCII" : "toUnicode" ];

                                        _pushDomainsToView(domains.map(xform));
                                    },

                                    domainsAreChanged: function domainsAreChanged() {
                                        var domains = _parseDomainsFromView();
                                        var saved = manageService.getSavedDomains();

                                        return !!_.xor(domains, saved).length;
                                    },

                                    submit: function submit() {
                                        var domains = PARSER.parseDomainsFromText(state.domainsText);

                                        $scope.inProgress = true;

                                        return manageService.saveBlockedDomains(domains).then( _syncDomainsText ).finally( function() {
                                            $scope.inProgress = false;
                                        } );
                                    },

                                    state: state,
                                }
                            );
                        },
                    ] );

                    BOOTSTRAP(document, "whm.mailBlockedDomains");
                }
            );
        };
    }
);
