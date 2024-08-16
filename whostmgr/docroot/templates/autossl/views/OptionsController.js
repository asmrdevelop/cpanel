/*
# templates/autossl/views/OptionsController.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */
/* jshint -W100 */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/formWaiting",
    ],
    function(_, angular, LOCALE, CJT, CJT_PARSE) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var AUTOSSL_NOTIFICATIONS = {
            disable: [ ],
            certFailures: [ "notify_autossl_expiry", "notify_autossl_expiry_coverage", "notify_autossl_renewal_coverage_reduced", "notify_autossl_renewal_coverage" ]
        };

        AUTOSSL_NOTIFICATIONS.failWarnDefer = _.concat( AUTOSSL_NOTIFICATIONS.certFailures, "notify_autossl_renewal_uncovered_domains" );
        AUTOSSL_NOTIFICATIONS.all           = _.concat( AUTOSSL_NOTIFICATIONS.failWarnDefer, "notify_autossl_renewal" );

        // Setup the controller
        return app.controller(
            "OptionsController", [
                "$scope",
                "manageService",
                "growl",
                "PAGE",
                function($scope, manageService, growl, PAGE) {
                    function growlError(result) {
                        return growl.error( _.escape(result.error) );
                    }

                    angular.extend( $scope, {
                        metadata: manageService.metadata,

                        clobber_externally_signed_string: function() {
                            return LOCALE.maketext("This option will allow [asis,AutoSSL] to replace certificates that the [asis,AutoSSL] system did not issue. When you enable this option, [asis,AutoSSL] will install certificates that replace users’ [output,abbr,CA,Certificate Authority]-issued certificates if they are invalid or expire within [quant,_1,day,days].", PAGE.constants.MIN_VALIDITY_DAYS_LEFT_BEFORE_CONSIDERED_ALMOST_EXPIRED);
                        },

                        do_submit: function() {

                            _.each(AUTOSSL_NOTIFICATIONS.all, function(n) {
                                manageService.metadata[n] = 0;
                                manageService.metadata[n + "_user"] = 0;
                            });

                            _.each(AUTOSSL_NOTIFICATIONS[$scope.adminNotifications], function(n) {
                                manageService.metadata[n] = 1;
                            });

                            _.each(AUTOSSL_NOTIFICATIONS[$scope.userNotifications], function(n) {
                                manageService.metadata[n + "_user"] = 1;
                            });

                            return manageService.save_metadata().then(
                                function() {
                                    growl.success( LOCALE.maketext("Success!") );
                                },
                                growlError
                            );
                        }
                    } );

                    if ( manageService.metadata.notify_autossl_renewal ) {
                        $scope.adminNotifications = "all";
                    } else if ( manageService.metadata.notify_autossl_renewal_uncovered_domains ) {
                        $scope.adminNotifications = "failWarnDefer";
                    } else if ( _.find(AUTOSSL_NOTIFICATIONS.certFailures, function(n) {
                        return manageService.metadata[n];
                    }) ) {
                        $scope.adminNotifications = "certFailures";
                    } else {
                        $scope.adminNotifications = "disable";
                    }

                    if ( manageService.metadata.notify_autossl_renewal_user ) {
                        $scope.userNotifications = "all";
                    } else if ( manageService.metadata.notify_autossl_renewal_uncovered_domains_user ) {
                        $scope.userNotifications = "failWarnDefer";
                    } else if ( _.find(AUTOSSL_NOTIFICATIONS.certFailures, function(n) {
                        return manageService.metadata[n + "_user"];
                    }) ) {
                        $scope.userNotifications = "certFailures";
                    } else {
                        $scope.userNotifications = "disable";
                    }

                }
            ]
        );
    }
);
