/*
# views/subaccounts.js                            Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
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

        var app = angular.module("App");

        var controller = app.controller(
            "subaccountSelectionController",
            ["$scope", "$q", "$location", "$routeParams", "ConvertAddonData",
                function($scope, $q, $location, $routeParams, ConvertAddonData) {
                    var sub_vm = this;

                    sub_vm.ui = {};
                    sub_vm.ui.is_loading = false;
                    sub_vm.ui.domain_exists = false;
                    sub_vm.this_domain = {};

                    sub_vm.stats = {};

                    function init() {
                        sub_vm.ui.is_loading = true;

                        ConvertAddonData.getAddonDomain($routeParams.addondomain)
                            .then(function(data) {
                                if (Object.keys(data).length) {
                                    sub_vm.domain_name = data.addon_domain;
                                    sub_vm.this_domain = data;

                                    sub_vm.ftp_accounts = data.move_options["ftp-accounts"];
                                    sub_vm.webdisk_accounts = data.move_options["webdisk-accounts"];

                                    sub_vm.ui.domain_exists = true;
                                } else {
                                    sub_vm.domain_name = $routeParams.addondomain;
                                    sub_vm.ui.domain_exists = false;
                                }
                            })
                            .finally(function() {
                                sub_vm.ui.is_loading = false;
                            });
                    }

                    sub_vm.saveOptions = function() {
                        sub_vm.this_domain.modified = true;
                        sub_vm.this_domain.move_options["ftp-accounts"] = sub_vm.ftp_accounts;
                        sub_vm.this_domain.move_options["webdisk-accounts"] = sub_vm.webdisk_accounts;
                        return $location.path("/convert/" + sub_vm.domain_name + "/migrations");
                    };

                    sub_vm.goBack = function() {
                        return $location.path("/convert/" + sub_vm.domain_name + "/migrations");
                    };

                    init();
                }
            ]);

        return controller;
    }
);
