/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/selectOptionsView.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
    ],
    function(angular, _, LOCALE, PARSE) {
        "use strict";

        var app = angular.module("whm.serverProfile");

        app.controller("selectOptionsController",
            ["$scope", "$location", "serverProfileService", "LICENSE_BASED_SERVER_PROFILE",
                function($scope, $location, serverProfileService, LICENSE_BASED_SERVER_PROFILE) {

                    $scope.loading = true;
                    $scope.licenseBasedServerProfile = LICENSE_BASED_SERVER_PROFILE;

                    var lookups = [];

                    $scope.selectedProfile = serverProfileService.getSelectedProfile();

                    $scope.optional = _.map($scope.selectedProfile.optional_roles, function(o) {
                        var role = { name: o.name, description: o.description, module: o.module, selected: false };
                        lookups.push(o.module);
                        return role;
                    });

                    serverProfileService.areRolesEnabled(lookups).then(
                        function(result) {

                            for ( var i = 0; i < result.length; i++ ) {
                                var enabled = result[i];
                                $scope.optional[i].current = $scope.optional[i].selected = enabled;
                            }
                        }
                    ).finally( function() {
                        $scope.loading = false;
                    } );

                    $scope.cancel = function() {
                        $location.path("/selectProfile");
                    };

                    $scope.continue = function() {
                        serverProfileService.setOptionalRoles($scope.optional);
                        $location.path("/confirmProfile");
                    };

                }
            ]
        );
    }
);
