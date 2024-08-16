/*
# views/docroot.js                                    Copyright(c) 2020 cPanel, L.L.C.
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
            "docrootController",
            ["$anchorScroll", "$location", "$routeParams", "growl", "ConvertAddonData",
                function($anchorScroll, $location, $routeParams, growl, ConvertAddonData) {

                    var docroot = this;

                    docroot.loading = true;

                    docroot.moveIt = false;
                    docroot.moveVhostIncludes = false;
                    docroot.copySSLCert = false;
                    docroot.sslCertInstalled = false;
                    docroot.addonDomain = "";
                    docroot.domainData = {};
                    docroot.noSSLCertTooltip = LOCALE.maketext("The domain does not have an [asis,SSL] certificate installed.");

                    docroot.load = function() {
                        return ConvertAddonData.getAddonDomainDetails(docroot.addonDomain)
                            .then(
                                function(result) {
                                    docroot.moveIt = result.move_options.docroot;
                                    docroot.moveVhostIncludes = result.move_options["custom-vhost-includes"];
                                    docroot.sslCertInstalled = result.details["has_ssl_cert_installed"] === 1 ? true : false;
                                    docroot.copySSLCert = result.move_options["copy-installed-ssl-cert"] && docroot.sslCertInstalled;
                                    docroot.domainData = result;
                                }, function(error) {
                                    growl.error(error);
                                }
                            )
                            .finally(
                                function() {
                                    docroot.loading = false;
                                }
                            );
                    };

                    docroot.goToOverview = function() {
                        return $location.path("/convert/" + docroot.addonDomain + "/migrations");
                    };

                    docroot.save = function() {
                        docroot.domainData.modified = true;
                        docroot.domainData.move_options.docroot = docroot.moveIt;
                        docroot.domainData.move_options["custom-vhost-includes"] = docroot.moveVhostIncludes;
                        docroot.domainData.move_options["copy-installed-ssl-cert"] = docroot.copySSLCert;
                        docroot.goToOverview();
                    };

                    docroot.cancel = function() {
                        docroot.goToOverview();
                    };

                    docroot.init = function() {
                        docroot.addonDomain = $routeParams.addondomain;
                        docroot.load();
                    };

                    docroot.init();
                }
            ]);

        return controller;
    }
);
