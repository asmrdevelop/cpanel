/*
# views/email_options.js                          Copyright(c) 2020 cPanel, L.L.C.
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
            "emailSelectionController",
            ["$scope", "$q", "$location", "$routeParams", "ConvertAddonData",
                function($scope, $q, $location, $routeParams, ConvertAddonData) {
                    var email_selection_vm = this;

                    email_selection_vm.ui = {};
                    email_selection_vm.ui.is_loading = false;
                    email_selection_vm.ui.domain_exists = false;
                    email_selection_vm.this_domain = {};

                    email_selection_vm.stats = {};

                    email_selection_vm.noEmailAccountsTooltip = LOCALE.maketext("The domain does not have email accounts.");
                    email_selection_vm.noAutorespondersTooltip = LOCALE.maketext("The domain does not have autoresponders.");
                    email_selection_vm.noForwardersTooltip = LOCALE.maketext("The domain does not have email forwarders.");

                    // initialize the view
                    function init() {
                        email_selection_vm.ui.is_loading = true;

                        ConvertAddonData.getAddonDomain($routeParams.addondomain)
                            .then(function(data) {
                                if (Object.keys(data).length) {
                                    email_selection_vm.domain_name = data.addon_domain;
                                    email_selection_vm.this_domain = data;

                                    if (data.details.number_of_email_forwarders === void 0) {
                                        data.details.number_of_email_forwarders = 0;
                                    }

                                    if (data.details.number_of_domain_forwarders === void 0) {
                                        data.details.number_of_domain_forwarders = 0;
                                    }

                                    if (data.details.number_of_email_accounts === void 0) {
                                        data.details.number_of_email_accounts = 0;
                                    }

                                    if (data.details.number_of_autoresponders === void 0) {
                                        data.details.number_of_autoresponders = 0;
                                    }

                                    email_selection_vm.email_accounts = data.move_options["email-accounts"];
                                    email_selection_vm.email_forwarders = data.move_options["email-forwarders"];
                                    email_selection_vm.autoresponders = data.move_options["autoresponders"];

                                    // disable webmail data if there are no email accounts
                                    if (data.details.number_of_email_accounts === 0) {
                                        email_selection_vm.webmail_data = false;
                                    }

                                    stringify_stats(email_selection_vm.this_domain.details);

                                    email_selection_vm.total_forwarders = data.details.number_of_email_forwarders +
                                    data.details.number_of_domain_forwarders;
                                    email_selection_vm.ui.domain_exists = true;
                                } else {
                                    email_selection_vm.domain_name = $routeParams.addondomain;
                                    email_selection_vm.ui.domain_exists = false;
                                }
                            })
                            .finally(function() {
                                email_selection_vm.ui.is_loading = false;
                            });
                    }

                    function stringify_stats(data) {
                        email_selection_vm.stats = {
                            "accounts": LOCALE.maketext("[quant,_1,Email account,Email accounts]", data.number_of_email_accounts),
                            "emailForwarders": LOCALE.maketext("[quant,_1,Email forwarder,Email forwarders]", data.number_of_email_forwarders),
                            "domainForwarders": LOCALE.maketext("[quant,_1,Domain forwarder,Domain forwarders]", data.number_of_domain_forwarders),
                            "autoresponders": LOCALE.maketext("[quant,_1,Autoresponder,Autoresponders]", data.number_of_autoresponders)
                        };
                    }

                    email_selection_vm.saveOptions = function() {
                        email_selection_vm.this_domain.modified = true;
                        email_selection_vm.this_domain.move_options["email-accounts"] = email_selection_vm.email_accounts;
                        email_selection_vm.this_domain.move_options["email-forwarders"] = email_selection_vm.email_forwarders;
                        email_selection_vm.this_domain.move_options["autoresponders"] = email_selection_vm.autoresponders;
                        return $location.path("/convert/" + email_selection_vm.domain_name + "/migrations");
                    };

                    email_selection_vm.goBack = function() {
                        return $location.path("/convert/" + email_selection_vm.domain_name + "/migrations");
                    };

                    init();
                }
            ]);

        return controller;
    }
);
