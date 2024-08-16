/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/activatingProfileView.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/parse",
        "cjt/util/locale",
        "cjt/io/eventsource",
    ],
    function(angular, CJT, PARSE, LOCALE, EVENTSOURCE) {
        "use strict";

        var app = angular.module("whm.serverProfile");

        function ProfileEventSource(sse) {
            var obj = this;

            sse.addEventListener("finish", function(e) {
                sse.close();
                obj._meta = JSON.parse( e.data );
                if (obj._onclose) {
                    obj._onclose();
                }
            });

            this._sse = sse;
        }
        ProfileEventSource.prototype.succeeded = function() {
            return this._meta && PARSE.parsePerlBoolean(this._meta.SUCCESS);
        };
        ProfileEventSource.prototype.onmessage = function(func) {
            this._sse.addEventListener("message", function(e) {
                func(JSON.parse(e.data));
            });
        };
        ProfileEventSource.prototype.onclose = function(func) {
            this._onclose = func;
        };

        app.controller("activatingProfileController",
            ["$scope", "$location", "$document", "$q", "alertService", "serverProfileService",
                function($scope, $location, $document, $q, alertService, serverProfileService) {

                    $scope.settingProfile = true;
                    $scope.$emit("ActivateProfileEvent");

                    $scope.back = function() {
                        $location.path("/selectProfile");
                    };

                    $scope.pageTitle = LOCALE.maketext("Activating Profile …");
                    $scope.activationState = "inProgress";

                    $scope.activationInitiated = true;

                    $scope.logId = serverProfileService.getLogId();
                    $scope.selected = serverProfileService.getSelectedProfile();

                    $scope.actionLog = "";
                    $scope.transferLogMessage = LOCALE.maketext("The profile activation log is located at: [_1]", "/var/cpanel/logs/activate_profile/" + $scope.logId + "/txt" );

                    $scope.showDetails = false;

                    $scope.toggleDetails = function() {
                        $scope.showDetails = !$scope.showDetails;
                    };

                    var sseUrl = CJT.securityToken + "/sse/ActivateProfile?log_id=" + serverProfileService.getLogId();
                    EVENTSOURCE.create(sseUrl).then( function(e) {
                        var sse = new ProfileEventSource(e.target);

                        sse.onmessage( function(msg) {

                            $scope.actionLog += msg;
                            $scope.$apply();

                            if ( !$scope.logElement ) {
                                $scope.logElement = $document[0].getElementById("activationLog");
                            }

                            if ( $scope.logElement ) {
                                $scope.logElement.scrollTop = $scope.logElement.scrollHeight;
                            }

                        } );

                        sse.onclose(function() {

                            if ( $scope.logElement ) {
                                $scope.logElement.scrollTop = $scope.logElement.scrollHeight;
                            }

                            if (sse.succeeded()) {

                                serverProfileService.setCurrentProfile($scope.selected);

                                $scope.activationState = "success";
                                $scope.pageTitle = LOCALE.maketext("Activation Successful");

                                alertService.add({
                                    type: "success",
                                    message: LOCALE.maketext("Successfully changed the server profile to “[_1]”.", $scope.selected.name),
                                    closeable: true,
                                    autoClose: 5000
                                });

                            } else {

                                $scope.activationState = "failed";
                                $scope.pageTitle = LOCALE.maketext("Activation Failed");

                                alertService.add({
                                    type: "danger",
                                    message: LOCALE.maketext("The system failed to change the server profile to “[_1]”.", $scope.selected.name),
                                    closeable: true,
                                });

                                $scope.showDetails = true;
                            }

                            $scope.settingProfile = false;

                            $scope.$apply();
                        });
                    }).catch( function(err) {
                        alertService.add({
                            type: "danger",
                            message: err,
                            closeable: true,
                        });
                    } );
                }
            ]
        );

    }
);
