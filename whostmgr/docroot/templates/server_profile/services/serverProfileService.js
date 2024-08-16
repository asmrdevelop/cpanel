/*
#  cpanel - whostmgr/docroot/templates/server_profile/services/serverProfileService.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    [
        "angular",
        "cjt/util/parse",
        "cjt/io/batch-request",
        "cjt/io/whm-v1-request",
        "cjt/services/APICatcher",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so its ready
    ],
    function(angular, PARSE, BATCH, APIREQUEST) {
        "use strict";

        var app = angular.module("whm.serverProfile.serverProfileService", ["cjt2.services.apicatcher", "cjt2.services.api"]);

        return app.factory("serverProfileService", ["APICatcher", "$q", "PAGE", function(api, $q, PAGE) {

            var NO_MODULE = "";

            var state = {
                availableProfiles: undefined,
                currentProfile: undefined,
                logId: undefined,
                optionalRoles: [],
                selectedProfile: undefined
            };

            if ( PAGE.availableProfiles ) {

                state.availableProfiles = PAGE.availableProfiles;

                if ( state.availableProfiles.length > 0 && PAGE.currentProfile ) {
                    for ( var i = 0; i < state.availableProfiles.length; i++ ) {
                        if ( state.availableProfiles[i].code === PAGE.currentProfile.code ) {
                            state.currentProfile = state.selectedProfile = state.availableProfiles[i];
                            break;
                        }
                    }
                }

            }

            function getAvailableProfiles() {

                var defer = $q.defer();

                if ( state.availableProfiles ) {
                    defer.resolve({ data: state.availableProfiles });
                } else {
                    var apiCall = new APIREQUEST.Class().initialize(NO_MODULE, "get_available_profiles");
                    api.promise(apiCall).then(
                        function(response) {
                            state.availableProfiles = response.data;
                            defer.resolve(response);
                        },
                        function(error) {
                            defer.reject(error);
                        }
                    );
                }

                return defer.promise;
            }

            function getCurrentProfile() {

                var defer = $q.defer();

                if ( state.currentProfile ) {
                    defer.resolve({  data: state.currentProfile });
                } else {
                    var apiCall = new APIREQUEST.Class().initialize(NO_MODULE, "get_current_profile");
                    api.promise(apiCall).then(
                        function(response) {
                            state.currentProfile = response.data;
                            defer.resolve(response);
                        },
                        function(error) {
                            defer.reject(error);
                        }
                    );
                }

                return defer.promise;
            }

            function setCurrentProfile(profile) {
                state.currentProfile = profile;
            }

            function getSelectedProfile() {
                return state.selectedProfile;
            }

            function setSelectedProfile(profile) {
                state.selectedProfile = profile;
            }

            function activateProfile(code, optional) {
                var apiCall = new APIREQUEST.Class().initialize(NO_MODULE, "start_profile_activation", { code: code, optional: JSON.stringify(optional) });
                return api.promise(apiCall);
            }

            function isRoleEnabled(role) {
                var apiCall = new APIREQUEST.Class().initialize(NO_MODULE, "is_role_enabled", { role: role });
                return api.promise(apiCall);
            }

            function getOptionalRoles() {
                return state.optionalRoles;
            }

            function setOptionalRoles(roles) {
                state.optionalRoles = roles;
            }

            function getLogId() {
                return state.logId;
            }

            function setLogId(id) {
                state.logId = id;
            }

            // Returns a promise whose resolution is an array of booleans
            // that corresponds with the array of roles passed in.
            function areRolesEnabled(roles) {

                if ( roles.length === 0 ) {
                    return $q(function(r) {
                        r({ data: [] });
                    });
                }

                var commands = roles.map( function(r) {
                    return new APIREQUEST.Class().initialize(
                        NO_MODULE,
                        "is_role_enabled",
                        { role: r }
                    );
                } );

                return api.promise( new BATCH.Class( commands ) ).then( function(result) {
                    return result.data.map( function(resp) {
                        return PARSE.parsePerlBoolean( resp.data.enabled );
                    });
                } );
            }

            return {
                activateProfile: activateProfile,
                areRolesEnabled: areRolesEnabled,
                getAvailableProfiles: getAvailableProfiles,
                getCurrentProfile: getCurrentProfile,
                getLogId: getLogId,
                getOptionalRoles: getOptionalRoles,
                getSelectedProfile: getSelectedProfile,
                isRoleEnabled: isRoleEnabled,
                setCurrentProfile: setCurrentProfile,
                setOptionalRoles: setOptionalRoles,
                setSelectedProfile: setSelectedProfile,
                setLogId: setLogId
            };

        }]);

    }
);
