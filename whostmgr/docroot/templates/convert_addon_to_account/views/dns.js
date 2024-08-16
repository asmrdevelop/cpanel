/*
# views/dns.js                                    Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/decorators/growlDecorator",
        "app/services/ConvertAddonData"
    ],
    function(angular, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "dnsSelectionController",
            ["$anchorScroll", "$location", "$routeParams", "growl", "ConvertAddonData",
                function($anchorScroll, $location, $routeParams, growl, ConvertAddonData) {

                    var dns = this;

                    dns.loading = true;

                    dns.moveIt = true;
                    dns.addonDomain = "";
                    dns.domainData = {};

                    dns.load = function() {
                        return ConvertAddonData.getAddonDomainDetails(dns.addonDomain)
                            .then(
                                function(result) {
                                    dns.moveIt = result.move_options["custom-dns-records"];
                                    dns.domainData = result;
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally(
                                function() {
                                    dns.loading = false;
                                }
                            );
                    };

                    dns.goToOverview = function() {
                        return $location.path("/convert/" + dns.addonDomain + "/migrations");
                    };

                    dns.save = function() {
                        dns.domainData.modified = true;
                        dns.domainData.move_options["custom-dns-records"] = dns.moveIt;
                        dns.goToOverview();
                    };

                    dns.cancel = function() {
                        dns.goToOverview();
                    };

                    dns.init = function() {
                        dns.addonDomain = $routeParams.addondomain;
                        dns.load();
                    };

                    dns.init();
                }
            ]);

        return controller;
    }
);
