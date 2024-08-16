/*
# cpanel - whostmgr/docroot/templates/set_zone_ttls/index.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global require, define, PAGE */

define(
    [
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/modules",
        "angular-ui-scroll"
    ],
    function(angular, LOCALE, CJT) {
        "use strict";

        return function() {

            // First create the application
            angular.module("whm.setZoneTtl", [
                "cjt2.config.whm.configProvider",
                "cjt2.whm",
                "ui.scroll"
            ]);

            // Then load the application dependencies
            var app = require(
                [
                    "cjt/bootstrap",
                    "cjt/directives/searchDirective",
                    "cjt/validator/datatype-validators",
                ], function(BOOTSTRAP) {

                    var app = angular.module("whm.setZoneTtl");
                    app.value("PAGE", PAGE);

                    app.controller(
                        "listZones",
                        ["$scope", "$filter", "PAGE",
                            function($scope, $filter, PAGE) {
                                var zones = PAGE.domains;
                                var filteredZones = zones;
                                var selectedCount = 0;
                                var lastDescriptor = null;
                                var zoneChoiceViewport = angular.element("#zoneChoiceViewport");

                                $scope.ttl = 14400;
                                $scope.hasZones = zones.length > 0;
                                $scope.showSelectionValidationMsg = false;

                                $scope.selectedItems = {};

                                $scope.zonesDatasource = {
                                    get: function(descriptor, success) {
                                        var result = filteredZones.slice(Math.max(descriptor.index, 0), descriptor.index + descriptor.count);
                                        success(result);
                                        lastDescriptor = descriptor;
                                        lastDescriptor.position = zoneChoiceViewport.scrollTop();
                                    }
                                };

                                $scope.updateShowingText = function() {
                                    $scope.showingText = LOCALE.maketext("Showing [numf,_1] of [numf,_2] records.", filteredZones.length, zones.length);
                                };

                                $scope.searchFilterChanged = function() {
                                    fetch();
                                };

                                $scope.onSelectItem = function(zone) {
                                    if ($scope.selectedItems[zone]) {
                                        selectedCount++;
                                    } else {
                                        selectedCount--;
                                        delete $scope.selectedItems[zone];
                                    }

                                    $scope.showSelectionValidationMsg = selectedCount <= 0;

                                };

                                $scope.validateForm = function(event, form) {
                                    if (selectedCount <= 0) {
                                        $scope.showSelectionValidationMsg = true;
                                    }

                                    if (selectedCount <= 0 || !form.$valid) {
                                        event.preventDefault();
                                        return false;
                                    }

                                    return true;
                                };

                                function checkForReload() {
                                    if (!lastDescriptor) {
                                        return;
                                    }

                                    var newFirstItem = -1;
                                    var maxLoaded = lastDescriptor.index + lastDescriptor.count;
                                    var position = zoneChoiceViewport.scrollTop();

                                    if (position === 0) {
                                        newFirstItem = 0;
                                    } else {
                                        var percScrolled = lastDescriptor.position / position;
                                        newFirstItem = maxLoaded * percScrolled;
                                    }

                                    if (maxLoaded - newFirstItem > 200) {
                                        newFirstItem = Math.max(newFirstItem, 0);
                                        $scope.uiScrollAdapter.reload(newFirstItem);
                                    }
                                }

                                function filterZones(zones) {
                                    var filteredZones = zones;
                                    if ($scope.filterValue) {
                                        filteredZones = $filter("filter")(filteredZones, $scope.filterValue);
                                    }
                                    return filteredZones;
                                }

                                function fetch() {
                                    var newZones = zones;
                                    newZones = filterZones(newZones);

                                    // prevent some unnecessary flickering when it's showing all the zones
                                    var zonesChanged = filteredZones.length !== zones.length || newZones.length !== filteredZones.length;

                                    if (zonesChanged) {
                                        filteredZones = newZones;
                                        if ($scope.uiScrollAdapter && angular.isFunction($scope.uiScrollAdapter.reload)) {
                                            $scope.uiScrollAdapter.reload(0);
                                        }
                                    }

                                    $scope.updateShowingText();
                                }

                                function init() {
                                    fetch();
                                    zoneChoiceViewport.bind("scroll", checkForReload);
                                }

                                init();
                            }
                        ]
                    );

                    var appContent = angular.element("#pageContainer");

                    if (appContent[0] !== null) {

                        // apply the app after requirejs loads everything
                        BOOTSTRAP(appContent[0], "whm.setZoneTtl");
                    }

                });

            return app;
        };
    }
);
