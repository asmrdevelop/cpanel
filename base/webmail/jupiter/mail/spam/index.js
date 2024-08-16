/*
# cpanel - base/webmail/jupiter/mail/spam/index.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require: false */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/uapi-request",
        "cjt/io/uapi", // IMPORTANT: Load the driver so it’s ready
        "cjt/modules",
        "cjt/directives/formWaiting",
        "cjt/decorators/alertAPIReporter",
        "uiBootstrap",
        "cjt/services/APICatcher",
        "cjt/directives/alertList",
    ],
    function(angular, _, LOCALE, PARSE, APIREQUEST) {
        "use strict";

        var savedSpamSettings = _.assign(
            {},
            CPANEL.PAGE.spam_settings
        );

        var cpanelAuthuser = CPANEL.PAGE.authuser;

        var BOOLEANS_TO_COPY = [
            "spam_auto_delete",
            "cpuser_spam_auto_delete",
        ];
        var NUMBERS_TO_COPY = [
            "spam_auto_delete_score",
            "cpuser_spam_auto_delete_score",
        ];

        var DEFAULT_SPAM_SCORE = 5;

        return function() {
            require(
                [

                    // Application Modules
                    "cjt/bootstrap",
                ], function(BOOTSTRAP) {
                    var app = angular.module("App", [
                        "cjt2.webmail",
                        "cjt2.decorators.alertAPIReporter",
                        "ui.bootstrap",
                    ]);

                    app.controller("BaseController", [
                        "$scope",
                        "$timeout",
                        "APICatcher",
                        "alertService",
                        function( $scope, $timeout, APICatcher, alertService ) {
                            NUMBERS_TO_COPY.forEach( function(st) {
                                $scope[st] = parseInt( savedSpamSettings[st], 10 );
                            } );

                            BOOLEANS_TO_COPY.forEach( function(st) {
                                $scope[st] = PARSE.parsePerlBoolean(savedSpamSettings[st]);
                            } );

                            function _showSuccess(result) {
                                alertService.add( {
                                    type: "success",
                                    message: LOCALE.maketext("Success!"),
                                } );
                            }

                            function _showWarnings(result) {
                                result.warnings.forEach(function(warning) {
                                    alertService.add( {
                                        type: "warning",
                                        message: warning,
                                    } );
                                });
                            }

                            if (!$scope.spam_auto_delete_score) {
                                if ($scope.cpuser_spam_auto_delete) {
                                    $scope.spam_auto_delete_score = $scope.cpuser_spam_auto_delete_score - 1;
                                } else {
                                    $scope.spam_auto_delete_score = DEFAULT_SPAM_SCORE;
                                }
                            }

                            _.assign(
                                $scope,
                                {
                                    deferred_focus: function _deferredFocus(id) {
                                        $timeout(
                                            function() {
                                                document.getElementById(id).focus();
                                            }
                                        );
                                    },

                                    save: function _saveSpamSettings() {
                                        var apicall;

                                        var scope = this;

                                        if ( scope.spam_auto_delete ) {
                                            apicall = new APIREQUEST.Class().initialize(
                                                "Email",
                                                "add_spam_filter",
                                                {
                                                    required_score: scope.spam_auto_delete_score,
                                                    account: cpanelAuthuser,
                                                }
                                            );
                                        } else {
                                            apicall = new APIREQUEST.Class().initialize(
                                                "Email",
                                                "disable_spam_autodelete",
                                                {
                                                    account: cpanelAuthuser,
                                                }
                                            );
                                        }

                                        return APICatcher.promise(apicall).then(
                                            function(result) {
                                                if ( result.warnings ) {
                                                    _showWarnings(result);
                                                } else {
                                                    _showSuccess(result);
                                                }
                                            }
                                        );
                                    },
                                }
                            );
                        },
                    ] );

                    BOOTSTRAP("#ng_content", "App");
                }
            );
        };
    }
);
