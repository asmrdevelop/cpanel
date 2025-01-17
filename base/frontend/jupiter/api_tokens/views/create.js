/*
# api_tokens/views/create.js                       Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define */

define(
    [
        "angular",
        "lodash",
        "cjt/util/locale",
        "app/services/apiTokens",
        "cjt/directives/copyField",
        "cjt/directives/timePicker",
        "cjt/directives/datePicker",
        "app/validators/uniqueTokenName",
        "cjt/modules",
        "cjt/directives/actionButtonDirective",
        "cjt/services/cpanel/componentSettingSaverService",
        "cjt/directives/validationContainerDirective",
        "cjt/directives/validationItemDirective",
        "cjt/directives/toggleSwitchDirective",
        "cjt/directives/searchDirective",
        "cjt/directives/indeterminateState",
        "cjt/services/alertService",
    ],
    function(angular, _, LOCALE, APITokensService, CopyFieldDirective, TimePickerDirective, DatePickerDirective) {

        "use strict";

        var CSSS_COMPONENT_NAME = "createAPITokenView";
        var VIEW_TITLE = LOCALE.maketext("Create API Token");
        var MODULE_NAMESPACE = "cpanel.apiTokens.views.create";
        var TEMPLATE_URL = "views/create.ptt";
        var MODULE_DEPENDANCIES = [
            "cjt2.directives.validationContainer",
            "cjt2.directives.validationItem",
            "cjt2.directives.toggleSwitch",
            "cjt2.directives.search",
            "cjt2.directives.indeterminateState",
            TimePickerDirective.namespace,
            DatePickerDirective.namespace,
            CopyFieldDirective.namespace,
        ];

        var CONTROLLER_INJECTABLES = ["$scope", "$location", "alertService", APITokensService.serviceName, "componentSettingSaverService", "CAN_CREATE_LIMITED", "apiTokens", "features"];
        var CONTROLLER_NAME = "CreateTokenController";
        var CONTROLLER = function APITokensListController($scope, $location, $alertService, $service, $CSSS, CAN_CREATE_LIMITED, apiTokens, features) {

            // For contingency of shipping without limited
            $scope.canCreateLimited = CAN_CREATE_LIMITED;
            $scope.pageTitle = VIEW_TITLE;
            $scope.RTL = LOCALE.is_rtl();
            $scope.showAllHelp = false;
            $scope.selectedFeatures = [];
            $scope.ui = {
                stayAfterCopy: false
            };
            $scope.checkAll = {
                all: false
            };
            $scope.features = features;
            $scope.apiTokens = apiTokens;
            $scope.working = {};

            $scope.datePickerOptions = {};
            $scope.timePickerOptions = {};

            var minDate = new Date();
            minDate.setHours(0);
            minDate.setMinutes(0);
            minDate.setSeconds(0, 0);

            var defaultExpiresDate = new Date(minDate.getTime());
            defaultExpiresDate.setHours(23);
            defaultExpiresDate.setMinutes(59);
            defaultExpiresDate.setSeconds(59, 999);
            defaultExpiresDate.setFullYear(defaultExpiresDate.getFullYear() + 1);

            /**
             * Iniitate the view
             *
             */
            $scope.init = function init() {
                $CSSS.register(CSSS_COMPONENT_NAME).then(function CSSSLoaded(data) {
                    if (data) {
                        $scope.showAllHelp = data.showAllHelp;
                        $scope.ui.stayAfterCopy = data.stayAfterCopy;
                    }
                });
                $scope.reset();
            };

            /**
             * Reset the form values
             *
             * @param {HTMLDomElement} form form to set pristine
             */
            $scope.reset = function reset(form) {
                $scope.datePickerOptions.minDate = minDate;
                $scope.timePickerOptions.min = minDate;

                $scope.working = {
                    name: "",
                    unrestricted: CAN_CREATE_LIMITED ? false : true,
                    features: {},
                    tokenExpires: false,
                    expiresAt: defaultExpiresDate
                };
                $scope.generatedToken = null;
                $scope.pageTitle = VIEW_TITLE;
                $scope.selectedFeatures = [];
                if (form) {
                    form.$setPristine();
                }
            };


            /**
             * Update the nvdata saved
             *
             * @private
             *
             */
            $scope._updateCSSS = function _updateCSSS() {
                $CSSS.set(CSSS_COMPONENT_NAME, {
                    showAllHelp: $scope.showAllHelp,
                    stayAfterCopy: $scope.ui.stayAfterCopy
                });
            };

            /**
             * Toggle Showing or Hiding All help
             *
             */
            $scope.toggleHelp = function toggleHelp() {
                $scope.showAllHelp = !$scope.showAllHelp;
                $scope._updateCSSS();
            };

            /**
             * Set the generatedToken and prepare the display for showing it.
             *
             * @param {String} newToken
             */
            $scope._tokenCreated = function _tokenCreated(newToken) {
                $scope.generatedToken = newToken;
                $scope.pageTitle = LOCALE.maketext("Token Created Successfully");
                $scope.apiTokens = $service.getTokens();
                var message;

                if ($scope.working.unrestricted) {
                    message = LOCALE.maketext("You successfully created an [output,strong,unrestricted] [asis,API] token “[_1]”.", $scope.working.name);
                } else {
                    message = LOCALE.maketext("You successfully created a [output,strong,limited-access] [asis,API] token “[_1]”.", $scope.working.name);
                }

                $alertService.success(message);
                return newToken;
            };

            /**
             * Create a new token
             *
             * @param {Object} workingToken
             * @returns {Promise<String>} returns the promise and then the newly created token
             */
            $scope.create = function create(workingToken) {

                if ( workingToken.tokenExpires ) {
                    workingToken.expiresAt.setHours(23);
                    workingToken.expiresAt.setMinutes(59);
                    workingToken.expiresAt.setSeconds(59, 999);
                }

                var expiresAt = workingToken.tokenExpires ? Math.floor(workingToken.expiresAt / 1000) : null;
                return $service.createToken(workingToken.name, workingToken.unrestricted, $scope.selectedFeatures, expiresAt).then($scope._tokenCreated);
            };

            $scope.newTokenExpiresMessage = function newTokenExpiresMessage(token) {
                var expirationDate = LOCALE.datetime(token.expiresAt, "datetime_format_medium");
                return LOCALE.maketext("This [asis,API] token will expire on [_1][comment,Bareword is a date].", expirationDate);
            };

            /**
             * Toggle (de)selecting all features in the feature chooser
             *
             */
            $scope.toggleSelectAllFeatures = function toggleSelectAllFeatures() {
                if ($scope.selectedFeatures.length < $scope.features.length) {
                    $scope.features.forEach(function selectAll(feature) {
                        $scope.working.features[feature.id] = true;
                    });
                } else {
                    $scope.features.forEach(function selectAll(feature) {
                        $scope.working.features[feature.id] = false;
                    });
                }

                $scope.updateSelectedFeatures();
            };

            /**
             * Determine if a partial number of items is selected
             *
             * @returns {Booolean} indeterminate state
             */
            $scope.getFeaturesIndeterminateState = function getFeaturesIndeterminateState() {
                return $scope.selectedFeatures.length && $scope.features.length && $scope.features.length !== $scope.selectedFeatures.length;
            };

            /**
             * Update the selected features list
             *
             */
            $scope.updateSelectedFeatures = function updateSelectedFeatures() {
                $scope.selectedFeatures = [];
                angular.forEach($scope.working.features, function(featureSelected, featureKey) {
                    if (featureSelected) {
                        $scope.selectedFeatures.push(featureKey);
                    }
                });
            };

            /**
             * Return to the lister view
             *
             */
            $scope.backToListView = function backToListView() {
                $location.path("/");
            };

            /**
             * Upon completion of a token copy, determine whether to return to the list
             *
             * @param {HTMLFormElement} form passed to reset for resetting to pristine
             */
            $scope.tokenCopied = function tokenCopied(form) {

                if ($scope.ui.stayAfterCopy) {
                    $scope.reset(form);
                } else {
                    $scope.backToListView();
                }

            };

            /**
             * Called when the stayAfterCopy is altered
             *
             */
            $scope.stayAfterCopyChanged = function stayAfterCopyChanged() {
                $scope._updateCSSS();
            };

            $scope.dateValidator = function dateValidator(input) {
                if ($scope.working.tokenExpires && $scope.working.expiresAt) {
                    $scope.working.expiresAt.setHours(23);
                    $scope.working.expiresAt.setMinutes(59);
                    $scope.working.expiresAt.setSeconds(59, 999);
                }

                if ($scope.working.tokenExpires && $scope.datePickerOptions.minDate > $scope.working.expiresAt) {
                    input.$invalid = true;
                    input.$valid = false;
                }
            };

            $scope.resetDate = function resetDate() {
                if ($scope.working.tokenExpires) {
                    $scope.working.expiresAt = defaultExpiresDate;
                }
            };

            $scope.$on("$destroy", $CSSS.unregister.bind($CSSS, CSSS_COMPONENT_NAME));

            $scope.init();

        };

        var app = angular.module(MODULE_NAMESPACE, MODULE_DEPENDANCIES);
        app.controller(CONTROLLER_NAME, CONTROLLER_INJECTABLES.concat(CONTROLLER));

        var resolver = {
            "apiTokens": [ APITokensService.serviceName, function($service) {
                return $service.fetchTokens();
            }],
            "features": [ APITokensService.serviceName, function($service) {
                return $service.getFeatures();
            }]
        };

        return {
            "id": "createAPIToken",
            "route": "/create",
            "controller": CONTROLLER_NAME,
            "class": CONTROLLER,
            "templateUrl": TEMPLATE_URL,
            "title": VIEW_TITLE,
            "namespace": MODULE_NAMESPACE,
            "showResourcePanel": true,
            "resolve": resolver
        };
    }
);
