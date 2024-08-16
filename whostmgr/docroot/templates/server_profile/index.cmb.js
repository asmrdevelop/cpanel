/*
#  cpanel - whostmgr/docroot/templates/server_profile/filters/rolesLocaleStringFilter.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    'app/filters/rolesLocaleString',[
        "angular",
        "cjt/util/locale",
        "lodash"
    ],
    function(angular, LOCALE, _) {
        "use strict";

        /**
         * Filter that accepts a list of roles and a locale string and returns the localized text
         * @param {String} roles        The list of roles to inject into the locale string
         * @param {String} localeString The locale string to inject the roles into
         *
         * @example
         * <div>{{ profile.roles | rolesLocaleString:'Enables: [list_and,_1]'">
         *
         * NOTE: The locale string passed to this filter must be defined in a maketext string. ## no extract maketext
         */

        var module = angular.module("whm.serverProfile.rolesLocaleString", []);

        module.filter("rolesLocaleString", function() {
            return function(roles, localeString) {
                var roleNames = _.map(roles, "name");
                return LOCALE.makevar(localeString, roleNames, roles.length);
            };
        });

    }
);

/*
#  cpanel - whostmgr/docroot/templates/server_profile/services/serverProfileService.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/services/serverProfileService',[
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

/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/activatingProfileView.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/views/activatingProfileView',[
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

/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/confirmProfileView.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/views/confirmProfileView',[
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

/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/selectOptionsView.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/views/selectOptionsView',[
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

/*
#  cpanel - whostmgr/docroot/templates/server_profile/views/selectProfileView.js    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define(
    'app/views/selectProfileView',[
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

/*
#  cpanel - whostmgr/docroot/templates/server_profile/index.js Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false, PAGE: false */

define(
    'app/index',[
        "angular",
        "cjt/core",
        "cjt/modules",
        "app/filters/rolesLocaleString",
        "app/services/serverProfileService"
    ],
    function(angular, CJT) {
        "use strict";

        var APP = "whm.serverProfile";
        var COMPONENT_NAME = "ServerProfileSelector";

        return function() {

            angular.module(APP, ["cjt2.config.whm.configProvider", "cjt2.whm", "cjt2.services.alert", "whm.serverProfile.rolesLocaleString", "whm.serverProfile.serverProfileService"]);

            require(
                [
                    "cjt/bootstrap",
                    "app/views/activatingProfileView",
                    "app/views/confirmProfileView",
                    "app/views/selectOptionsView",
                    "app/views/selectProfileView"
                ],
                function(BOOTSTRAP) {

                    var app = angular.module(APP);
                    var LICENSE_BASED_SERVER_PROFILE = PAGE.availableProfiles.length === 1;
                    var currentProfile = PAGE.currentProfile;
                    var hasOptionalRoles = !!currentProfile.optional_roles.length;

                    app.value("PAGE", PAGE);
                    app.value("LICENSE_BASED_SERVER_PROFILE", LICENSE_BASED_SERVER_PROFILE);

                    app.config(["$routeProvider", function($routeProvider) {

                        // Do not include profile selection in routes if the license specifies a non-standard profile
                        if (!LICENSE_BASED_SERVER_PROFILE) {
                            $routeProvider.when("/selectProfile", {
                                controller: "selectProfileController",
                                templateUrl: CJT.buildFullPath("server_profile/views/selectProfileView.ptt")
                            });
                        }

                        $routeProvider.when("/selectOptions", {
                            controller: "selectOptionsController",
                            templateUrl: CJT.buildFullPath("server_profile/views/selectOptionsView.ptt")
                        });

                        $routeProvider.when("/confirmProfile", {
                            controller: "confirmProfileController",
                            templateUrl: CJT.buildFullPath("server_profile/views/confirmProfileView.ptt")
                        });

                        $routeProvider.when("/activatingProfile", {
                            controller: "activatingProfileController",
                            templateUrl: CJT.buildFullPath("server_profile/views/activatingProfileView.ptt")
                        });

                        // If the license specifies the profile, go straight to options
                        if (LICENSE_BASED_SERVER_PROFILE) {
                            $routeProvider.otherwise("/selectOptions");
                        } else {
                            $routeProvider.otherwise("/selectProfile");
                        }

                    }]);

                    app.controller("baseController", ["$scope", "componentSettingSaverService", "$location", "$timeout",
                        function($scope, csss, $location, $timeout) {

                            $scope.licenseBasedServerProfile = LICENSE_BASED_SERVER_PROFILE;
                            $scope.noOptionalRoles = !hasOptionalRoles;

                            $scope.$on("ActivateProfileEvent", function() {
                                $scope.activationInitiated = true;
                            });

                            $scope.$on("$destroy", function() {
                                csss.unregister(COMPONENT_NAME);
                            });

                            $scope.dismissWarning = function() {

                                csss.set(COMPONENT_NAME, {
                                    dismissedWarning: true
                                });

                                $scope.dismissedWarning = true;
                            };

                            var register = csss.register(COMPONENT_NAME);
                            if ( register ) {
                                register.then(function(result) {
                                    if ( result && result.dismissedWarning !== undefined ) {
                                        $scope.dismissedWarning = true;
                                    }
                                }).finally(function() {
                                    $location.path("/selectProfile");
                                    $timeout(function() {
                                        $scope.loaded = true;
                                    });
                                });
                            } else {
                                $location.path("/selectProfile");
                                $timeout(function() {
                                    $scope.loaded = true;
                                });
                            }

                        }]
                    );

                    BOOTSTRAP("#contentContainer", APP);
                }
            );
        };
    }
);

