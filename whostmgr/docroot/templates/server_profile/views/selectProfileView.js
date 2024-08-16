/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/selectProfileView.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular"
    ],
    function(angular) {
        "use strict";

        var app = angular.module("whm.serverProfile");

        app.controller("selectProfileController",
            ["$scope", "$location", "serverProfileService",
                function($scope, $location, serverProfileService) {

                    $scope.profiles = {};

                    serverProfileService.getAvailableProfiles().then(
                        function(response) {
                            $scope.profiles.available = response.data;

                            return serverProfileService.getCurrentProfile().then(
                                function(response) {
                                    $scope.profiles.selected = $scope.profiles.current = response.data;
                                }
                            );

                        }
                    );

                    $scope.continue = function() {

                        serverProfileService.setSelectedProfile($scope.profiles.selected);

                        if ( $scope.profiles.selected.optional_roles.length === 0 ) {
                            serverProfileService.setOptionalRoles([]);
                            $location.path("/confirmProfile");
                        } else {
                            $location.path("/selectOptions");
                        }
                    };

                    $scope.info = function(profile) {
                        $scope.openInfo = profile === $scope.openInfo ? undefined : profile;
                    };

                }
            ]
        );

    }
);
