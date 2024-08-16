/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/confirmProfileView.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale"
    ],
    function(angular, _, LOCALE) {
        "use strict";

        var app = angular.module("whm.serverProfile");

        app.controller("confirmProfileController",
            ["$rootScope", "$scope", "$location", "serverProfileService",
                function($rootScope, $scope, $location, serverProfileService) {

                    var ENABLED  = LOCALE.maketext("Enabled");
                    var DISABLED = LOCALE.maketext("Disabled");

                    $scope.loading = true;

                    $scope.selected = serverProfileService.getSelectedProfile();

                    $scope.newEnabled  = [];
                    $scope.newDisabled = [];
                    $scope.optional    = serverProfileService.getOptionalRoles();
                    $scope.unchanged   = [];

                    var appendStateToName = function(name, state) {
                        return name + " (" + (state ? ENABLED : DISABLED) + ")";
                    };

                    serverProfileService.getCurrentProfile().then(
                        function(result) {

                            $scope.current = result.data;

                            var roleLookups = [];

                            _.forEach($scope.selected.enabled_roles, function(o) {
                                if ( _.includes($scope.current.enabled_roles, o) ) {
                                    $scope.unchanged.push(_.assign({}, o, { name: appendStateToName(o.name, true) }));
                                } else {
                                    roleLookups.push(o.module);
                                }
                            });

                            _.forEach($scope.selected.disabled_roles, function(o) {
                                if ( _.includes($scope.current.disabled_roles, o) ) {
                                    $scope.unchanged.push(_.assign({}, o, { name: appendStateToName(o.name, false) }));
                                } else {
                                    roleLookups.push(o.module);
                                }
                            });

                            _.forEach($scope.optional, function(o) {
                                if ( o.current === o.selected ) {
                                    $scope.unchanged.push(_.assign({}, o, { name: appendStateToName(o.name, o.current) }));
                                } else if ( o.current ) {
                                    $scope.newDisabled.push(o);
                                } else {
                                    $scope.newEnabled.push(o);
                                }
                            });

                            serverProfileService.areRolesEnabled(roleLookups).then(
                                function(result) {
                                    for ( var i = 0; i < result.length; i++ ) {

                                        var enabled = result[i];
                                        var r;

                                        if ( (r = _.find($scope.selected.enabled_roles, function(o) {
                                            return o.module === roleLookups[i];
                                        })) ) {
                                            if ( !enabled ) {
                                                $scope.newEnabled.push(r);
                                            } else {
                                                $scope.unchanged.push(_.assign({}, r, { name: appendStateToName(r.name, true) }));
                                            }
                                        } else if ( (r = _.find($scope.selected.disabled_roles, function(o) {
                                            return o.module === roleLookups[i];
                                        })) ) {
                                            if ( enabled ) {
                                                $scope.newDisabled.push(r);
                                            } else {
                                                $scope.unchanged.push(_.assign({}, r, { name: appendStateToName(r.name, false) }));
                                            }
                                        }

                                    }
                                }
                            ).finally( function() {
                                $scope.loading = false;
                            } );

                        },
                        function() {
                            $scope.loading = false;
                        }
                    );

                    $scope.cancel = function() {
                        $location.path("/selectProfile");
                    };

                    $scope.continue = function(profile) {

                        $scope.settingProfile = true;

                        var optional = {};

                        _.each($scope.optional, function(role) {
                            optional[role.module] = role.selected ? 1 : 0;
                        });

                        return serverProfileService.activateProfile(profile.code, optional).then(
                            function(resp) {
                                serverProfileService.setLogId(resp.data.log_id);
                                $location.path("/activatingProfile");

                            }
                        ).finally(function() {
                            $scope.settingProfile = false;
                        });

                    };

                }
            ]
        );

    }
);
