/*
# templates/easyapache4/views/yumUpdate.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, PAGE */

define(
    [
        "angular",
        "cjt/util/locale",
        "lodash",
        "cjt/services/alertService",
        "cjt/directives/alertList",
        "app/services/ea4Data",
        "app/services/ea4Util",
        "app/services/pkgResolution"
    ],
    function(angular, LOCALE, _) {

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("yumUpdate",
            [ "$scope", "$location", "ea4Data", "ea4Util", "alertService", "growl", "growlMessages",
                function($scope, $location, ea4Data, ea4Util, alertService, growl, growlMessages) {
                    $scope.fixFailed = false;
                    var fixYumCache = function() {
                        $scope.fixingYum = true;
                        ea4Data.fixYumCache().then(function(result) {
                            if (result.status && result.data.cache_seems_ok_now) {
                                app.firstLoad = false;
                                ea4Data.setData( { "ea4ThrewError": false } );
                                $location.path("profile");
                            } else {
                                $scope.fixFailed = true;
                            }
                        }, function(error) {
                            $scope.fixFailed = true;
                        }).finally(function() {
                            $scope.fixingYum = false;
                        });
                    };
                    $scope.$on("$viewContentLoaded", function() {

                        // Destroy all old growls when view is loaded.
                        growlMessages.destroyAllMessages();
                        var error = ea4Data.getData("ea4ThrewError");
                        if (error) {
                            fixYumCache();
                        }
                    });
                }]);
    }
);
