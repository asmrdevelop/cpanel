/*
# views/move_options.js                       Copyright(c) 2020 cPanel, L.L.C.
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
        "cjt/validator/email-validator",
        "cjt/directives/validationItemDirective",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validateEqualsDirective",
        "cjt/directives/actionButtonDirective",
        "app/services/ConvertAddonData",
        "app/services/Databases",
        "app/services/account_packages",
        "app/directives/move_status",
    ],
    function(angular, LOCALE) {

        var app = angular.module("App");

        var controller = app.controller(
            "moveSelectionController",
            ["$q", "$location", "$routeParams", "defaultInfo", "growl", "ConvertAddonData", "Databases", "AccountPackages", "$scope",
                function($q, $location, $routeParams, defaultInfo, growl, ConvertAddonData, Databases, AccountPackages, $scope) {
                    var move_options_vm = this;

                    move_options_vm.ui = {};
                    move_options_vm.ui.is_loading = false;
                    move_options_vm.ui.domain_exists = false;
                    move_options_vm.ui.is_conversion_started = false;
                    move_options_vm.enable_db_button = false;
                    move_options_vm.this_domain = {};
                    move_options_vm.copy_mysql_dbs = false;
                    move_options_vm.has_dedicated_ip = false;
                    move_options_vm.account_packages = [];
                    move_options_vm.ip_addr_will_change = false;
                    move_options_vm.selected_package = void 0;

                    move_options_vm.stats = {};

                    move_options_vm.no_databases_tooltip = LOCALE.maketext("Disabled because there are no databases to move");
                    move_options_vm.no_email_tooltip = LOCALE.maketext("Disabled because there are no email-related items to move");

                    // initialize the view
                    function init() {
                        move_options_vm.ui.is_loading = true;

                        ConvertAddonData.getAddonDomainDetails($routeParams.addondomain)
                            .then(function(data) {
                                if (Object.keys(data).length) {
                                    move_options_vm.domain_name = data.addon_domain;
                                    move_options_vm.this_domain = data;

                                    move_options_vm.this_domain.account_settings.domain = data.addon_domain;
                                    if (move_options_vm.this_domain.account_settings.email === void 0) {
                                        move_options_vm.this_domain.account_settings.email = "";
                                    }

                                    if (move_options_vm.this_domain.account_settings.pkgname === void 0) {
                                        move_options_vm.this_domain.account_settings.pkgname = "";
                                    }

                                    if (move_options_vm.this_domain.account_settings.username === void 0) {
                                        move_options_vm.generate_username(move_options_vm.domain_name);
                                    }

                                    if (move_options_vm.this_domain.details.has_dedicated_ip === 1) {
                                        move_options_vm.ip_addr_will_change = true;
                                    }

                                    // we only want to show the SSL certificate copy option if the user has chosen to copy the ssl cert
                                    // and they have an SSL cert installed for that domain
                                    move_options_vm.show_ssl_copy_option = move_options_vm.this_domain.move_options["copy-installed-ssl-cert"] &&
                                    move_options_vm.this_domain.details.has_ssl_cert_installed === 1;

                                    // intelligently set some options based on the data we have
                                    if (!move_options_vm.this_domain.modified) {
                                        change_defaults(move_options_vm.this_domain);
                                        move_options_vm.this_domain.modified = false;
                                    }

                                    stringify_stats(move_options_vm.this_domain.details);

                                    move_options_vm.move_email_category =
                                    move_options_vm.this_domain.move_options["email-accounts"] ||
                                    move_options_vm.this_domain.move_options["email-forwarders"] ||
                                    move_options_vm.this_domain.move_options["autoresponders"];

                                    // Disable the email section configure button if there is no email data to move
                                    move_options_vm.disable_email_button = (
                                        move_options_vm.this_domain.details.number_of_email_accounts +
                                    move_options_vm.this_domain.details.number_of_domain_forwarders +
                                    move_options_vm.this_domain.details.number_of_email_forwarders +
                                    move_options_vm.this_domain.details.number_of_autoresponders) === 0;

                                    move_options_vm.move_db_category = move_options_vm.this_domain.move_options.mysql_dbs.length || move_options_vm.this_domain.move_options.mysql_users.length;
                                    move_options_vm.copy_mysql_dbs = (move_options_vm.this_domain.move_options.db_move_type === "copy") ? true : false;

                                    move_options_vm.move_website_data = move_options_vm.this_domain.move_options["docroot"] ||
                                                                    move_options_vm.this_domain.move_options["custom-vhost-includes"] ||
                                                                    move_options_vm.this_domain.move_options["copy-installed-ssl-cert"];

                                    move_options_vm.move_subaccount_category = move_options_vm.this_domain.move_options["ftp-accounts"] ||
                                    move_options_vm.this_domain.move_options["webdisk-accounts"];

                                    move_options_vm.selected_dbs_message = move_options_vm.copy_mysql_dbs ? LOCALE.maketext("You selected the following [asis,MySQL] databases to copy:") : LOCALE.maketext("You selected the following [asis,MySQL] databases to move:");

                                    // get the count of databases and the account packages available for the current user
                                    return $q.all([
                                        Databases.getDatabases(move_options_vm.this_domain.owner),
                                        AccountPackages.listPackages(),
                                    ])
                                        .then(function(data) {
                                            move_options_vm.enable_db_button = Object.keys(data[0]).length > 0;
                                            move_options_vm.account_packages = data[1];

                                            for (var i = 0, len = move_options_vm.account_packages.length; i < len; i++) {
                                                if (move_options_vm.account_packages[i].name &&
                                                    move_options_vm.account_packages[i].name === move_options_vm.this_domain.account_settings.pkgname) {
                                                    move_options_vm.selected_package = move_options_vm.account_packages[i];
                                                }
                                            }

                                            // default to the first package if one has not been selected
                                            if (move_options_vm.this_domain.account_settings.pkgname === "") {
                                                move_options_vm.selected_package = move_options_vm.account_packages[0];
                                            }

                                            move_options_vm.sync_pkg_settings();
                                        })
                                        .catch(function(meta) {
                                            var len = meta.errors.length;
                                            if (len > 1) {
                                                growl.error(meta.reason);
                                            }
                                            for (var i = 0; i < len; i++) {
                                                growl.error(meta.errors[i]);
                                            }
                                        })
                                        .finally(function() {
                                            move_options_vm.ui.domain_exists = true;
                                        });
                                } else {
                                    move_options_vm.domain_name = $routeParams.addondomain;
                                    move_options_vm.ui.domain_exists = false;
                                }
                            })
                            .finally(function() {
                                move_options_vm.ui.is_loading = false;
                            });
                    }

                    function stringify_stats(data) {
                        move_options_vm.stats.email = {
                            "accounts": LOCALE.maketext("[quant,_1,Email account,Email accounts]", data.number_of_email_accounts),
                            "forwarders": LOCALE.maketext("[quant,_1,Forwarder,Forwarders]", data.number_of_email_forwarders + data.number_of_domain_forwarders),
                            "autoresponders": LOCALE.maketext("[quant,_1,Autoresponder,Autoresponders]", data.number_of_autoresponders),
                        };
                    }

                    function change_defaults(data) {
                        if (data.details.number_of_email_accounts === 0) {
                            move_options_vm.this_domain.move_options["email-accounts"] = false;
                        }

                        var total_forwarders = data.details.number_of_domain_forwarders + data.details.number_of_email_forwarders;
                        if (total_forwarders === 0) {
                            move_options_vm.this_domain.move_options["email-forwarders"] = false;
                        }

                        if (data.details.number_of_autoresponders === 0) {
                            move_options_vm.this_domain.move_options["autoresponders"] = false;
                        }

                        move_options_vm.show_ssl_copy_option = move_options_vm.this_domain.details.has_ssl_cert_installed === 1;

                        move_options_vm.sync_pkg_settings();
                    }

                    move_options_vm.sync_pkg_settings = function() {
                        if (move_options_vm.this_domain.details.has_dedicated_ip === 1 || move_options_vm.has_dedicated_ip) {
                            move_options_vm.ip_addr_will_change = true;
                        } else {
                            move_options_vm.ip_addr_will_change = false;
                        }
                    };

                    move_options_vm.generate_username = function(domain) {

                        // we want to strip off the TLD, then replace the numbers, dots, and anything
                        // not an ascii character for the username
                        var username = domain
                            .replace(/^\d+/, "")
                            .replace(/\.[^.]+$/, "")
                            .replace(/[^A-Za-z0-9]/g, "")
                            .substr(0, defaultInfo.username_restrictions.maxLength);
                        move_options_vm.this_domain.account_settings.username = username.toLowerCase();
                    };

                    move_options_vm.disableSave = function(form) {
                        return (form.$dirty && form.$invalid) || move_options_vm.ui.is_conversion_started || !move_options_vm.account_packages.length;
                    };

                    move_options_vm.addDbPrefix = function(db) {
                        if (Databases.isPrefixingEnabled()) {
                            return Databases.addPrefixIfNeeded(db, move_options_vm.this_domain.account_settings.username);
                        }

                        return db;
                    };

                    // watch the value of the selected account package
                    $scope.$watch(function() {
                        return move_options_vm.selected_package;
                    }, function(newPkg, oldPkg) {

                        // if we have no data yet, then just return.
                        // newPkg being undefined happens on initial load
                        if (Object.keys(move_options_vm.this_domain).length === 0 ||
                        newPkg === void 0) {
                            return;
                        }

                        // if the new package is null, then give the default values
                        if (newPkg === null) {
                            move_options_vm.has_dedicated_ip = false;
                            move_options_vm.this_domain.account_settings.pkgname = "";
                        } else {

                            // we have a new selected package, so lets update the values.
                            move_options_vm.has_dedicated_ip = newPkg.IP === "y" ? true : false;
                            move_options_vm.this_domain.account_settings.pkgname = newPkg.name;
                        }

                        move_options_vm.sync_pkg_settings();
                    });

                    move_options_vm.startConversion = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        move_options_vm.this_domain.modified = true;

                        // add prefixes to the databases as the last step in case they change the username before submission
                        if (Databases.isPrefixingEnabled() && move_options_vm.this_domain.move_options.db_move_type === "copy") {
                            for (var j = 0, dblen = move_options_vm.this_domain.move_options.mysql_dbs.length; j < dblen; j++) {
                                var db = move_options_vm.this_domain.move_options.mysql_dbs[j];
                                db.new_name = Databases.addPrefix(db.new_name, move_options_vm.this_domain.account_settings.username);
                            }
                        }

                        return ConvertAddonData.beginConversion(move_options_vm.this_domain)
                            .then(function(data) {
                                growl.success(LOCALE.maketext("The system started the conversion process for “[_1]”.",
                                    move_options_vm.domain_name));
                                move_options_vm.ui.is_conversion_started = true;

                                // send the user to the conversion history page
                                // would be better to do to the conversion details
                                // page, but the job id is not available at this point

                                return $location.path("/history");
                            })
                            .catch(function(meta) {
                                var len = meta.errors.length;
                                if (len > 1) {
                                    growl.error(meta.reason);
                                }
                                for (var i = 0; i < len; i++) {
                                    growl.error(meta.errors[i]);
                                }

                                move_options_vm.ui.is_conversion_started = false;
                            });
                    };

                    move_options_vm.goToEditView = function(category) {
                        return $location.path("/convert/" + move_options_vm.domain_name + "/migrations/edit/" + category);
                    };

                    move_options_vm.goToMain = function() {

                        // reset the account settings
                        move_options_vm.this_domain.account_settings = {};
                        return $location.path("/main");
                    };

                    init();
                },
            ]);

        return controller;
    }
);
