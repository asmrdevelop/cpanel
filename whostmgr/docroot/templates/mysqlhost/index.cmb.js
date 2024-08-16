/*
# templates/mysqlhost/directives/mysqlhost_domain_validators.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define: false     */
/* --------------------------*/

define('app/directives/mysqlhost_domain_validators',[
    "angular",
    "cjt/validator/validator-utils",
    "cjt/util/locale",
    "cjt/util/inet6",
    "cjt/validator/domain-validators",
    "cjt/validator/validateDirectiveFactory",
],
function(angular, validationUtils, LOCALE, inet6, DOMAIN_VALIDATORS) {

    // Correlate with $Cpanel::Regex::regex{'ipv4'}
    var ipV4Regex = /^(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$/;

    /**
         * Validate document root
         *
         * @method  docRootPath
         * @param {string} document root path
         * @return {object} validation result
         */
    var validators = {

        hostnameOrIp: function(val) {
            var result = validationUtils.initializeValidationResult();
            var isValid = false;

            if (_isLoopback(val)) {
                isValid = true;
            } else if (_isValidIp(val)) {
                isValid = true;
            } else {
                var output = DOMAIN_VALIDATORS.methods.fqdn(val);
                isValid = output.isValid;

                // grab messages from the other validator to this one
                if (!isValid) {
                    for (var i = 0, len = output.messages.length; i < len; i++) {
                        result.add(output.messages[i].name, output.messages[i].message);
                    }
                }
            }

            if (!isValid) {
                result.isValid = false;
                result.add("hostnameOrIp", LOCALE.maketext("The host must be a valid [asis,IP] address or [asis,hostname]."));
            }

            return result;
        },

        loopback: function(val) {
            var result = validationUtils.initializeValidationResult();

            if (_isLoopback(val)) {
                result.isValid = true;
            } else {
                result.isValid = false;
                result.add("localhost", LOCALE.maketext("The value must be a valid [asis,loopback] address."));
            }

            return result;
        }
    };

    function _isLoopback(ipOrHost) {
        switch (ipOrHost) {
            case "localhost":
            case "localhost.localdomain":
            case "0000:0000:0000:0000:0000:0000:0000:0001":
            case "0:0:0:0:0:0:0:1":
            case ":1":
            case "::1":
            case "0:0:0:0":
            case "0000:0000:0000:0000:0000:0000:0000:0000":
                return true;

            default:
                if (/^0000:0000:0000:0000:0000:ffff:7f/.test(ipOrHost) ||
                        /^::ffff:127\./.test(ipOrHost) ||
                        /^127\./.test(ipOrHost)) {
                    return true;
                }
        }

        return false;
    }

    /* hosts, domains and ip addresses */

    function _isValidIp(ipOrHost) {
        return inet6.isValid(ipOrHost) || ipV4Regex.test(ipOrHost);
    }

    var validatorModule = angular.module("cjt2.validate");

    validatorModule.run(["validatorFactory",
        function(validatorFactory) {
            validatorFactory.generate(validators);
        }
    ]);

    return {
        methods: validators,
        name: "mysqlhostDomainValidators",
        description: "Validation directives for ip address and hostname.",
        version: 11.52,
    };
}
);

/*
# templates/mysqlhost/models/MysqlProfile.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/models/MysqlProfile',["lodash"],
    function(_) {

        function MysqlProfile(defaults) {
            if (!_.isObject(defaults)) {
                defaults = {};
            }
            this.type = "mysql";
            this.active = false;
            this.name = defaults.name || "";
            this.host = defaults.host || "";
            this.port = defaults.port || 3306;
            this.account = defaults.account || "";
            this.password = defaults.password || "";
            this.comment = defaults.comment || "";
            this.is_local = defaults.is_local || void 0;
            this.is_supported = defaults.is_supported || void 0;
        }
        MysqlProfile.prototype.activate = function() {
            this.active = true;
        };
        MysqlProfile.prototype.deactivate = function() {
            this.active = false;
        };
        MysqlProfile.prototype.convertToProfileObject = function(ConvertToThis) {
            return new ConvertToThis({
                active: this.active,
                name: this.name,
                host: this.host,
                account: this.account,
                comment: this.comment,
                is_local: this.is_local,
                is_supported: this.is_supported
            });
        };

        return MysqlProfile;
    }
);

/*
# templates/mysqlhost/models/MysqlProfileUsingSsh.js  Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/models/MysqlProfileUsingSsh',["lodash"],
    function(_) {
        function MysqlProfileUsingSsh(defaults) {
            if (!_.isObject(defaults)) {
                defaults = {};
            }
            this.type = "ssh";
            this.active = false;
            this.name = defaults.name || "";
            this.host = defaults.host || "";
            this.port = defaults.port || 22;
            this.account = defaults.account || "";
            this.password = defaults.password || "";
            this.ssh_key = defaults.ssh_key || "";
            this.ssh_passphrase = defaults.ssh_passphrase || "";
            this.escalation_type = defaults.escalation_type || "";
            this.escalation_password = defaults.escalation_password || "";
            this.comment = defaults.comment || "";
            this.is_local = defaults.is_local || void 0;
            this.is_supported = defaults.is_supported || void 0;
        }
        MysqlProfileUsingSsh.prototype.activate = function() {
            this.active = true;
        };
        MysqlProfileUsingSsh.prototype.deactivate = function() {
            this.active = false;
        };
        MysqlProfileUsingSsh.prototype.convertToProfileObject = function(ConvertToThis) {
            return new ConvertToThis({
                active: this.active,
                name: this.name,
                host: this.host,
                account: this.account,
                comment: this.comment,
                is_local: this.is_local,
                is_supported: this.is_supported
            });
        };

        return MysqlProfileUsingSsh;
    }
);

/*
# templates/mysqlhost/services/MySQLHostDataSource.js Copyright(c) 2020 cPanel, L.L.C.
#                                                               All rights reserved.
# copyright@cpanel.net                                             http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/services/MySQLHostDataSource',[
        "angular",
        "jquery",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/io/api",
        "cjt/io/whm-v1-request",
        "cjt/io/whm-v1", // IMPORTANT: Load the driver so it's ready
        "app/models/MysqlProfile",
        "app/models/MysqlProfileUsingSsh"
    ],
    function(angular, $, _, LOCALE, PARSE, API, APIREQUEST, APIDRIVER, MysqlProfile, MysqlProfileUsingSsh) {

        // Retrieve the current application
        var app = angular.module("App");

        var mysqlHostData = app.factory("MySQLHostDataSource", ["$q", function($q) {

            var mysqlHostData = {};

            mysqlHostData.profiles = {};

            mysqlHostData.clearCache = function() {
                mysqlHostData.profiles = {};
            };

            mysqlHostData.generateErrorMessageForDisplay = function(metadata) {
                if (!metadata) {
                    return LOCALE.maketext("An unexpected error occurred.");
                }

                var error = _.escape(metadata.reason) + "<br><br>",
                    i = 0,
                    len = metadata.error_count,
                    escapedMessages = [];

                for (i; i < len; i++) {
                    escapedMessages.push(_.escape(metadata.errors[i]));
                }

                error += escapedMessages.join("<br>");

                return error;
            };

            mysqlHostData.createObjectForTransport = function(object) {
                var obj = {};

                if (object instanceof MysqlProfile) {
                    obj = {
                        "name": object.name,
                        "mysql_host": object.host,
                        "mysql_port": object.port,
                        "mysql_user": object.account,
                        "mysql_pass": object.password
                    };
                    if (object.hasOwnProperty("active")) {
                        obj.active = object.active ? 1 : 0;
                    }
                } else if (object instanceof MysqlProfileUsingSsh) {
                    obj = {
                        "name": object.name,
                        "host": object.host,
                        "port": object.port,
                        "user": object.account,
                        "password": object.password,
                        "sshkey_name": object.ssh_key,
                        "sshkey_passphrase": object.ssh_passphrase,
                        "root_escalation_method": object.escalation_type
                    };
                    if (object.hasOwnProperty("active")) {
                        obj.active = object.active ? 1 : 0;
                    }
                    if (object.escalation_type === "su") {
                        obj.root_password = object.escalation_password;
                    }
                }

                return obj;
            };

            mysqlHostData.createObjectFromAPI = function(name, object) {
                var obj = new MysqlProfile({
                    name: name,
                    host: object.mysql_host,
                    port: object.mysql_port,
                    account: object.mysql_user,
                    password: object.mysql_pass,
                    comment: object.setup_via,
                    is_local: object.is_localhost_profile,
                    is_supported: object.mysql_version_is_supported
                });
                var isActive = PARSE.parsePerlBoolean(object.active);
                if (isActive) {
                    obj.activate();
                } else {
                    obj.deactivate();
                }

                return obj;
            };

            mysqlHostData.createObjectsFromAPI = function(data) {
                var profiles = {};
                for (var i = 0, keys = _.keys(data), len = keys.length; i < len; i++) {
                    var name = keys[i];
                    var obj = mysqlHostData.createObjectFromAPI(name, data[keys[i]]);
                    profiles[name] = obj;
                }
                return profiles;
            };

            mysqlHostData.createProfile = function(profileData) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                if (profileData.type === "ssh") {
                    apiCall.initialize("", "remote_mysql_create_profile_via_ssh");
                } else {
                    apiCall.initialize("", "remote_mysql_create_profile");
                }

                var obj = mysqlHostData.createObjectForTransport(profileData);
                for (var i = 0, keys = _.keys(obj), len = keys.length; i < len; i++) {
                    var value = obj[keys[i]];
                    apiCall.addArgument(keys[i], value);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            mysqlHostData.profiles[response.data.profile_saved] = mysqlHostData.createObjectFromAPI(response.data.profile_saved, response.data.profile_details);
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.updateProfile = function(profileData) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();

                apiCall.initialize("", "remote_mysql_update_profile");

                var obj = mysqlHostData.createObjectForTransport(profileData);
                for (var i = 0, keys = _.keys(obj), len = keys.length; i < len; i++) {
                    var value = obj[keys[i]];
                    apiCall.addArgument(keys[i], value);
                }

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            mysqlHostData.profiles[response.data.profile_saved] = mysqlHostData.createObjectFromAPI(response.data.profile_saved, response.data.profile_details);
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };


            mysqlHostData.loadProfiles = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_read_profiles");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            mysqlHostData.profiles = mysqlHostData.createObjectsFromAPI(response.data);
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.deleteProfile = function(profileName) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_delete_profile");
                apiCall.addArgument("name", profileName);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {

                        // create items from the response
                        response = response.parsedResponse;
                        if (response.status) {
                            delete mysqlHostData.profiles[profileName];
                            deferred.resolve(null);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.validateProfile = function(profileName) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_validate_profile");
                apiCall.addArgument("name", profileName);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data.profile_validated);
                        } else {
                            var errorHtml;

                            errorHtml = mysqlHostData.generateErrorMessageForDisplay(response.meta);
                            errorHtml = mysqlHostData.appendTroubleshootingLink({
                                html: errorHtml,
                                linkId: "validate-troubleshoot-link-" + profileName,
                            });

                            deferred.reject(errorHtml);
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.activateProfile = function(profileName) {

                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_initiate_profile_activation");
                apiCall.addArgument("name", profileName);

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (response.status) {
                            deferred.resolve(response.data.activation_job_started);
                        } else {
                            deferred.reject(mysqlHostData.generateErrorMessageForDisplay(response.meta));
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.monitorActivation = function(profileName) {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_monitor_profile_activation");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;
                        if (!response.data.job_in_progress && response.data.last_job_details.status === "FAILED") {
                            deferred.reject(response.data);
                        } else {
                            deferred.resolve(response.data);
                        }
                    });

                return deferred.promise;
            };

            mysqlHostData.activationInProgress = function() {
                var deferred = $q.defer();
                var apiCall = new APIREQUEST.Class();
                apiCall.initialize("", "remote_mysql_monitor_profile_activation");

                API.promise(apiCall.getRunArguments())
                    .done(function(response) {
                        response = response.parsedResponse;

                        var activationDetails = {};

                        if (_.isNull(response.data.job_in_progress) && _.isNull(response.data.last_job_details)) {
                            deferred.reject({ in_progress: false });
                        }

                        activationDetails.in_progress = response.data.job_in_progress ? true : false;
                        if (activationDetails.in_progress) {
                            activationDetails.payload = response.data.job_in_progress;
                        } else {
                            activationDetails.payload = response.data.last_job_details;
                        }

                        deferred.resolve(activationDetails);
                    });

                return deferred.promise;
            };

            /**
             * Appends HTML for the troubleshooting link to the end of a growl
             * message's HTML.
             *
             * @method appendTroubleshootingLink
             * @param {object} args
             * @param {string} args.html - The HTML string to which the troubleshooting message should be appended.
             * @param {string} args.linkId - The ID to use on the anchor tag for the link.
             * @returns {string} - The final HTML string, with the troubleshooting message appended.
             */
            mysqlHostData.appendTroubleshootingLink = function(args) {
                var finalHtml = args.html;
                var troubleshootingLinkId = args.linkId;

                var troubleshootingHtml = LOCALE.maketext(
                    "For more information, read our [output,url,_1,documentation,target,_2,id,_3].",
                    "https://go.cpanel.net/troubleshootmysqlprofiles",
                    "troubleshootingDocs",
                    troubleshootingLinkId
                );

                finalHtml += "<div class=\"growl-troubleshooting-link\">" + troubleshootingHtml + "</div>";
                return finalHtml;
            };


            return mysqlHostData;
        }]);

        return mysqlHostData;
    }
);

/*
# templates/mysqlhost/views/profiles.js           Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/profiles',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/util/parse",
        "app/directives/mysqlhost_domain_validators",
        "cjt/validator/datatype-validators",
        "cjt/validator/length-validators",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/decorators/growlDecorator",
        "cjt/directives/actionButtonDirective",
        "app/services/MySQLHostDataSource"
    ],
    function(angular, _, LOCALE, PARSE, MYSQL_DOMAIN_VALIDATORS) {
        "use strict";

        var app = angular.module("App");

        var controller = app.controller(
            "profilesController",
            ["$scope", "$uibModal", "$location", "$timeout", "growl", "MySQLHostDataSource", "growlMessages",
                function($scope, $uibModal, $location, $timeout, growl, MySQLHostDataSource, growlMessages) {

                    $scope.profiles = {};

                    $scope.activeProfile = "";
                    $scope.loadingProfiles = true;
                    $scope.modalInstance = null;
                    $scope.lastActivation = {
                        in_progress: false,
                        profile: "",
                        steps: [],
                        final_step: 0,
                        expanded: false
                    };
                    var monitorPromise;

                    $scope.messages = {
                        "DONE": LOCALE.maketext("This step completed."),
                        "FAILED": LOCALE.maketext("This step failed."),
                        "SKIPPED": LOCALE.maketext("This step was skipped."),
                        "INPROGRESS": LOCALE.maketext("This step is in progress.")
                    };

                    $scope.message = function(status) {
                        return $scope.messages[status];
                    };

                    $scope.profileListIsEmpty = function() {
                        if ($scope.loadingProfiles || ($scope.profiles && Object.keys($scope.profiles).length > 0)) {
                            return false;
                        }

                        return true;
                    };

                    $scope.confirmDeleteProfile = function(profileName) {
                        $scope.currentProfileName = profileName;
                        $scope.modalInstance = $uibModal.open({
                            templateUrl: "confirmprofiledeletion.html",
                            scope: $scope
                        });
                        return $scope.modalInstance.result
                            .then(function(profileName) {
                                return $scope.deleteProfile(profileName);
                            }, function() {
                                $scope.clearModalInstance();
                            });
                    };

                    $scope.confirmActivateProfile = function(profile) {
                        $scope.currentProfileName = profile.name;
                        $scope.is_not_supported = profile.is_local && !profile.is_supported;
                        $scope.modalInstance = $uibModal.open({
                            templateUrl: "confirmprofileactivation.html",
                            scope: $scope
                        });
                        return $scope.modalInstance.result
                            .then(function(profileName) {
                                return $scope.changeActiveProfile(profileName);
                            }, function() {
                                $scope.clearModalInstance();
                            });
                    };

                    $scope.clearModalInstance = function() {
                        if ($scope.modalInstance) {
                            $scope.modalInstance.close();
                            $scope.modalInstance = null;
                        }
                    };

                    $scope.disableProfileOperations = function(profileName) {
                        if ($scope.lastActivation.in_progress || $scope.profiles[profileName].active) {
                            return true;
                        }
                        return false;
                    };

                    function loadActivationSteps(obj) {
                        var i = $scope.lastActivation.final_step;
                        for (i; i < obj.steps.length; i++) {
                            $scope.lastActivation.steps.push(obj.steps[i]);
                        }

                        // iterate over the steps to make sure the status for each step is correct
                        for (var j = 0; j < obj.steps.length; j++) {
                            $scope.lastActivation.steps[j].status = obj.steps[j].status;
                        }
                        $scope.lastActivation.final_step = i;
                    }

                    $scope.monitorProfileChange = function(profileName) {
                        return MySQLHostDataSource.monitorActivation(profileName)
                            .then( function(data) {
                                if (!data.job_in_progress) {

                                    // disable the timeout
                                    $timeout.cancel(monitorPromise);

                                    loadActivationSteps(data.last_job_details);

                                    if ($scope.activeProfile && $scope.activeProfile !== "" && $scope.profiles[$scope.activeProfile]) {
                                        $scope.profiles[$scope.activeProfile].deactivate();
                                    }
                                    $scope.profiles[data.last_job_details.profile_name].activate();
                                    $scope.activeProfile = data.last_job_details.profile_name;
                                    $scope.lastActivation.in_progress = false;
                                    growlMessages.destroyAllMessages();
                                    growl.success(LOCALE.maketext("Activation completed for “[_1]”.", _.escape(profileName)));
                                    return null;
                                } else {
                                    $scope.lastActivation.in_progress = true;
                                    loadActivationSteps(data.job_in_progress);
                                    monitorPromise = $timeout(function() {
                                        return $scope.monitorProfileChange(data.job_in_progress.profile_name);
                                    }, 2000);
                                    return monitorPromise;
                                }
                            }, function(data) {

                                // disable the timeout
                                $timeout.cancel(monitorPromise);
                                loadActivationSteps(data.last_job_details);

                                var errorHtml = LOCALE.maketext("Activation failed for “[_1]” during step “[_2]” because of an error: [_3]",
                                    _.escape(data.last_job_details.profile_name),
                                    _.escape(data.last_job_details.steps[data.last_job_details.steps.length - 1].name),
                                    _.escape(data.last_job_details.steps[data.last_job_details.steps.length - 1].error)
                                );

                                errorHtml = MySQLHostDataSource.appendTroubleshootingLink({
                                    html: errorHtml,
                                    linkId: "monitor-troubleshoot-link-" + profileName,
                                });

                                growlMessages.destroyAllMessages();
                                growl.error(errorHtml);
                                $scope.lastActivation.in_progress = false;
                            });
                    };

                    $scope.changeActiveProfile = function(profileName) {
                        $scope.lastActivation.profile = profileName;
                        $scope.lastActivation.final_step = 0;
                        $scope.lastActivation.steps = [];
                        $scope.lastActivation.in_progress = true;
                        return MySQLHostDataSource.activateProfile(profileName)
                            .then( function() {
                                $scope.lastActivation.expanded = true;
                                growl.info(LOCALE.maketext("Activation in progress for “[_1]”.", _.escape(profileName)));
                                return $timeout(function() {
                                    return $scope.monitorProfileChange(profileName);
                                }, 2000);
                            }, function(error) {
                                growlMessages.destroyAllMessages();
                                growl.error(error);
                                $scope.lastActivation.in_progress = false;
                            });
                    };

                    $scope.deleteProfile = function(profileName) {
                        $scope.clearModalInstance();
                        return MySQLHostDataSource.deleteProfile(profileName)
                            .then( function() {
                                $scope.profiles = MySQLHostDataSource.profiles;
                                growl.success(LOCALE.maketext("You have successfully deleted the profile, “[_1]”.", _.escape(profileName)));
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.validateProfile = function(profileName) {
                        return MySQLHostDataSource.validateProfile(profileName)
                            .then( function() {
                                growl.success(LOCALE.maketext("The profile “[_1]” is valid.", _.escape(profileName)));
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.initialMonitorCheck = function() {
                        return MySQLHostDataSource.activationInProgress()
                            .then( function(last_activation) {
                                $scope.lastActivation.profile = last_activation.payload.profile_name;
                                loadActivationSteps(last_activation.payload);

                                if (last_activation.in_progress) {
                                    $scope.lastActivation.in_progress = true;
                                    return $scope.monitorProfileChange(last_activation.payload.profile_name);
                                }
                            });
                    };

                    $scope.loadProfiles = function() {
                        $scope.loadingProfiles = true;
                        return MySQLHostDataSource.loadProfiles()
                            .then( function() {
                                $scope.profiles = MySQLHostDataSource.profiles;
                                for (var name in $scope.profiles) {
                                    if ($scope.profiles[name].hasOwnProperty("active")) {
                                        if ($scope.profiles[name].active) {
                                            $scope.activeProfile = name;
                                            break;
                                        }
                                    }
                                }
                            }, function(error) {
                                growl.error(error);
                            })
                            .finally(function() {
                                $scope.loadingProfiles = false;
                            });
                    };

                    $scope.hasLocalhostProfile = function() {
                        for (var i = 0, keys = _.keys($scope.profiles), len = keys.length; i < len; i++) {
                            if ($scope.profiles[keys[i]].is_local) {
                                return true;
                            }
                        }
                        return false;
                    };

                    $scope.forceLoadProfiles = function() {
                        if ($scope.lastActivation.in_progress) {
                            return;
                        }
                        $scope.profiles = {};
                        $scope.loadProfiles();
                    };

                    $scope.goToAddProfile = function() {
                        if ($scope.lastActivation.in_progress) {
                            return;
                        }
                        return $location.path("/profiles/new");
                    };

                    $scope.goToAddLocalhostProfile = function() {
                        if ($scope.lastActivation.in_progress) {
                            return;
                        }
                        return $location.path("/profiles/newlocalhost");
                    };

                    var init = function() {
                        return $scope.loadProfiles()
                            .then(function() {
                                $scope.initialMonitorCheck();
                            });
                    };

                    init();
                }
            ]);

        return controller;
    }
);

/*
# templates/mysqlhost/views/profile_details.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    'app/views/profile_details',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/validator/length-validators",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/decorators/growlDecorator",
        "cjt/directives/actionButtonDirective",
        "app/services/MySQLHostDataSource",
        "app/directives/mysqlhost_domain_validators"
    ],
    function(angular, _, LOCALE) {

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "profileDetailsController",
            ["$scope", "$location", "$q", "$routeParams", "growl", "MySQLHostDataSource",
                function($scope, $location, $q, $routeParams, growl, MySQLHostDataSource) {

                    $scope.currentProfile = null;
                    $scope.loadingProfiles = false;

                    $scope.disableSave = function(form) {
                        return (form.$dirty && form.$invalid) || $scope.loadingProfiles;
                    };

                    $scope.saveProfile = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        return MySQLHostDataSource.updateProfile($scope.currentProfile)
                            .then( function() {
                                growl.success(LOCALE.maketext("You have successfully updated the profile, “[_1]”.", _.escape($scope.currentProfile.name)));
                                $location.path("/profiles");
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.loadProfiles = function() {
                        $scope.loadingProfiles = true;
                        return MySQLHostDataSource.loadProfiles()
                            .then( function() {
                                $scope.loadingProfiles = false;
                            }, function(error) {
                                growl.error(error);
                                $scope.loadingProfiles = true;
                            });
                    };

                    $scope.loadProfileData = function(profileName) {
                        var profileData = MySQLHostDataSource.profiles[profileName];
                        if (typeof profileData !== "undefined") {
                            $scope.currentProfile = profileData;
                            return true;
                        } else {
                            return false;
                        }
                    };

                    function init() {

                    // we are trying to load a particular profile. does the profile exist?
                        $scope.loadProfiles()
                            .then(function() {
                                var result = $scope.loadProfileData($routeParams.profileName);
                                if (!result) {

                                // the profile does not exist, take them back to the profile page
                                    $location.path("profiles");
                                } else {
                                    $scope.loadingProfiles = false;
                                }
                            });
                    }

                    init();
                }
            ]);

        return controller;
    }
);

/*
# templates/mysqlhost/views/add_profile.js        Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false, PAGE: false */
/* jshint -W100 */

define(
    'app/views/add_profile',[
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/models/MysqlProfile",
        "app/models/MysqlProfileUsingSsh",
        "cjt/validator/datatype-validators",
        "cjt/validator/compare-validators",
        "cjt/validator/length-validators",
        "uiBootstrap",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/decorators/growlDecorator",
        "cjt/directives/actionButtonDirective",
        "app/services/MySQLHostDataSource",
        "app/directives/mysqlhost_domain_validators"
    ],
    function(angular, _, LOCALE, MysqlProfile, MysqlProfileUsingSsh) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        var controller = app.controller(
            "addProfileController",
            ["$scope", "$location", "$q", "$routeParams", "growl", "MySQLHostDataSource",
                function($scope, $location, $q, $routeParams, growl, MySQLHostDataSource) {

                    $scope.currentProfile = null;
                    $scope.workflow = {
                        currentProfileAuthType: "password",
                        disableSshProfileAuthType: false
                    };
                    $scope.ssh_keys = {};
                    $scope.enableCreateViaSSH = true;

                    $scope.disableSave = function(form) {
                        return (form.$dirty && form.$invalid);
                    };

                    $scope.saveProfile = function(form) {
                        if (!form.$valid) {
                            return;
                        }

                        // if the ssh auth type is enabled and a key has been selected, use it
                        if (!$scope.workflow.disableSshProfileAuthType && $scope.currentProfile.sshKey && $scope.currentProfile.sshKey.key) {
                            $scope.currentProfile.ssh_key = $scope.currentProfile.sshKey.key;
                        }

                        return MySQLHostDataSource.createProfile($scope.currentProfile)
                            .then( function() {
                                growl.success(LOCALE.maketext("You have successfully created the profile, “[_1]”.", _.escape($scope.currentProfile.name)));
                                $location.path("/profiles");
                            }, function(error) {
                                growl.error(error);
                            });
                    };

                    $scope.convertProfileType = function(type) {
                        if (type === "ssh") {
                            $scope.currentProfile = $scope.currentProfile.convertToProfileObject(MysqlProfileUsingSsh);

                            // default to grabbing the first key
                            $scope.currentProfile.sshKey = $scope.ssh_keys[0];
                        } else if (type === "mysql") {
                            $scope.currentProfile = $scope.currentProfile.convertToProfileObject(MysqlProfile);
                        }
                    };

                    $scope.requiresEscalation = function() {
                        return $scope.currentProfile &&
                        $scope.currentProfile.type === "ssh" &&
                        $scope.currentProfile.account &&
                        $scope.currentProfile.account.length > 0 &&
                        $scope.currentProfile.account !== "root";
                    };

                    function init() {

                        // which route is this?
                        $scope.currentRoute = $location.path();

                        if ($scope.currentRoute === "/profiles/newlocalhost") {
                            $scope.currentProfile = new MysqlProfile({
                                name: "localhost",
                                host: "localhost",
                                port: 3306,
                                account: "root"
                            });
                            $scope.enableCreateViaSSH = false;
                        } else {

                            // default profile type is the Mysql Using SSH credentials
                            $scope.currentProfile = new MysqlProfileUsingSsh();
                        }
                        $scope.currentProfile.sshKey = $scope.currentProfile.ssh_key;

                        if (typeof PAGE.key_list !== "undefined" && PAGE.key_list.length > 0) {
                            $scope.ssh_keys = PAGE.key_list;
                            $scope.currentProfile.sshKey = $scope.ssh_keys[0];
                        } else {
                            $scope.workflow.disableSshProfileAuthType = true;
                            $scope.workflow.currentProfileAuthType = "password";
                        }
                    }

                    init();
                }
            ]);

        return controller;
    }
);

/*
# templates/mysqlhost/index.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global require: false, define: false */
/* jshint -W100 */

define(
    'app/index',[
        "angular",
        "jquery",
        "lodash",
        "cjt/core",
        "cjt/modules",
        "ngRoute",
        "uiBootstrap",
        "ngSanitize",
        "ngAnimate"
    ],
    function(angular, $, _, CJT) {
        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load first
                "ngRoute",
                "ui.bootstrap",
                "ngSanitize",
                "ngAnimate",
                "angular-growl",
                "cjt2.whm"
            ]);

            var app = require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "cjt/util/locale",
                    "cjt/util/inet6",

                    // Application Modules
                    "app/views/profiles",
                    "app/views/profile_details",
                    "app/views/add_profile",
                    "app/directives/mysqlhost_domain_validators"
                ], function(BOOTSTRAP, LOCALE) {

                    var app = angular.module("App");

                    app.config(["$routeProvider",
                        function($routeProvider) {

                            // Setup the routes
                            $routeProvider.when("/profiles", {
                                controller: "profilesController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/profiles.ptt"),
                            });

                            $routeProvider.when("/profiles/profile-:profileName", {
                                controller: "profileDetailsController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/profile_details.ptt"),
                            });

                            $routeProvider.when("/profiles/new", {
                                controller: "addProfileController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/add_profile.ptt"),
                            });

                            $routeProvider.when("/profiles/newlocalhost", {
                                controller: "addProfileController",
                                templateUrl: CJT.buildFullPath("mysqlhost/views/add_profile.ptt"),
                            });


                            $routeProvider.otherwise({
                                "redirectTo": "/profiles"
                            });

                        }
                    ]);

                    app.run(["$rootScope", "$timeout", "$location", "growl", "growlMessages", function($rootScope, $timeout, $location, growl, growlMessages) {
                    }]);

                    BOOTSTRAP(document);

                });

            return app;
        };
    }
);

