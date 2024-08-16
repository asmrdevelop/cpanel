/*
# templates/autossl/views/select_provider_controller.js
#                                                 Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
/* jshint -W100 */

define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/util/parse",
        "uiBootstrap",
        "cjt/directives/formWaiting",
    ],
    function(_, angular, LOCALE, CJT_PARSE) {
        "use strict";

        // Retrieve the current application
        // Or mock it for testing.
        var app;
        try {
            app = angular.module("App");
        } catch (e) {
            app = angular.module("App", []);
        }

        // Setup the controller
        var controller = app.controller(
            "select_provider_controller", [
                "$scope",
                "manageService",
                "growl",
                function($scope, manageService, growl) {
                    function _growlError(result) {
                        result.data && result.data.forEach(function(batchResponse) {
                            var parsedResponse = batchResponse.parsedResponse;
                            parsedResponse.messages.forEach(function(message) {
                                growl[message.level](_.escape(message.content));
                            });
                        });
                    }

                    function _convertMS(ms) {
                        var d, h, m, s, y;
                        s = Math.floor(ms / 1000);
                        m = Math.floor(s / 60);
                        s = s % 60;
                        h = Math.floor(m / 60);
                        m = m % 60;
                        d = Math.floor(h / 24);
                        h = h % 24;
                        y = Math.floor(d / 365);
                        d = d % 365;

                        return { y: y, d: d, h: h, m: m, s: s };
                    }

                    function _generateTimeString(timeObject) {
                        var timeString = [];
                        if (timeObject.y) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,year,years]", timeObject.y);
                        }
                        if (timeObject.d) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,day,days]", timeObject.d);
                        }
                        if (timeObject.h) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,hour,hours]", timeObject.h);
                        }
                        if (timeObject.m) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,minute,minutes]", timeObject.m);
                        }
                        if (timeObject.s) {
                            timeString[timeString.length] = LOCALE.maketext("[quant,_1,second,seconds]", timeObject.s);
                        }
                        return timeString.join("/");
                    }

                    function _getTimeString(value, unsetValue) {
                        if (!value) {
                            return unsetValue;
                        }

                        var fullTimeObject = _convertMS(value * 1000);

                        return _generateTimeString(fullTimeObject);
                    }

                    function _getFormattedSpec(specValue, specKey) {
                        specValue = _.isNil(specValue) ? "" : specValue;
                        var formattedSpec = specValue.toString();
                        switch (specKey) {
                            case "list_and_quoted":
                                formattedSpec = LOCALE.list_and_quoted(specValue);
                                break;
                            case "numf":
                                formattedSpec = LOCALE.numf(specValue);
                                break;
                            case "time_string":
                                formattedSpec = _getTimeString(specValue, LOCALE.maketext("[output,em,Unspecified]"));
                                break;
                            case "rate_limit":
                                formattedSpec = specValue.toString() === "0" ? LOCALE.maketext("unlimited") : specValue;
                        }
                        return formattedSpec.toString() === "" ? LOCALE.maketext("[output,em,Unspecified]") : formattedSpec.toString();
                    }

                    function _gather_save_data() { // eslint-disable-line camelcase
                        var providerModule = $scope.current_provider_module_name;

                        var providerObj = $scope.get_current_provider();

                        var tosAccepted = providerObj ? providerObj.x_terms_of_service_accepted : "";

                        var toSave = {
                            provider: providerModule
                        };
                        if (providerObj && providerObj.x_terms_of_service) {
                            toSave.x_terms_of_service_accepted = tosAccepted;
                        }

                        return toSave;
                    }

                    angular.extend($scope, {
                        providers: manageService.get_providers(),
                        showScoreDetails: false,
                        provider_by_module_name: {},
                        provider_submit_type: {},
                        current_provider_module_name: "",
                        getFormattedSpec: _getFormattedSpec,

                        toggleShowScoreDetails: function() {
                            $scope.showScoreDetails = !$scope.showScoreDetails;
                        },

                        get_current_provider: function() {
                            if ($scope.current_provider_module_name) {
                                return $scope.provider_by_module_name[$scope.current_provider_module_name];
                            }

                            return null;
                        },

                        getTableColumns: manageService.getTableColumns.bind(manageService),
                        getDetailsExplaination: function() {
                            var tableColumns = manageService.getTableColumns();
                            tableColumns = tableColumns.filter(function(column) {
                                return column.isScorePart;
                            }).map(function(column) {
                                return column.getLabel();
                            });
                            return LOCALE.maketext("This interface uses the following parameters to calculate the usability score: [list_and,_1].", tableColumns);
                        },

                        get_saved_provider_module_name: manageService.get_saved_provider_module_name,

                        do_submit: function() {
                            var toSave = _gather_save_data();

                            var providerObj = $scope.get_current_provider();

                            var toReset = ($scope.provider_submit_type[$scope.current_provider_module_name] === "reset");

                            var method;
                            if (toReset) {
                                method = "reset_provider_data";
                            } else {
                                method = "save_provider_data";
                            }

                            return manageService[method](toSave).then(
                                function() {
                                    var newProviderObj = $scope.provider_by_module_name[toSave.provider];

                                    if (toReset) {
                                        growl.success(LOCALE.maketext("You have created a new registration for this system with “[_1]” and configured [asis,AutoSSL] to use that provider.", _.escape(newProviderObj.display_name)));
                                    } else if (newProviderObj) {
                                        growl.success(LOCALE.maketext("You have configured [asis,AutoSSL] to use the “[_1]” provider.", _.escape(newProviderObj.display_name)));
                                    } else {
                                        growl.success(LOCALE.maketext("You have disabled [asis,AutoSSL]. Any users with [asis,SSL] certificates from [asis,AutoSSL] will continue to use them, but the system will not automatically renew these certificates."));
                                    }

                                    if (providerObj) {
                                        providerObj.saved_x_terms_of_service_accepted = providerObj.x_terms_of_service_accepted;
                                    }

                                    $scope.provider_submit_type[$scope.current_provider_module_name] = "";
                                },
                                _growlError
                            ).finally(function() {
                                $scope.$emit("provider-module-updated");
                            });
                        },
                    });

                    $scope.providers.forEach(function(p) {
                        if (CJT_PARSE.parsePerlBoolean(p.enabled)) {
                            $scope.current_provider_module_name = p.module_name;
                        }

                        $scope.provider_by_module_name[p.module_name] = p;
                    });

                    manageService.restore_and_save_scope(
                        "select_provider",
                        $scope, [
                            "current_provider_module_name",
                        ]
                    );
                }
            ]
        );

        return controller;
    }
);
