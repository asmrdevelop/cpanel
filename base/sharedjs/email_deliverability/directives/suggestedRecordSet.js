/*
# email_deliverability/directives/suggestedRecordSet.js          Copyright 2022 cPanel, L.L.C.
#                                                                All rights reserved.
# copyright@cpanel.net                                              http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/directives/copyField",
        "shared/js/email_deliverability/filters/htmlSafeString",
        "cjt/util/locale",
        "cjt/core",
        "cjt/directives/callout",
        "cjt/modules"
    ],
    function(angular, _, CopyField, HTMLSafeString, LOCALE, CJT) {

        "use strict";


        var RELATIVE_PATH = "shared/js/email_deliverability/directives/suggestedRecordSet.ptt";
        var TEMPLATE_PATH = CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : CJT.buildPath(RELATIVE_PATH);
        var MODULE_NAMESPACE = "shared.emailDeliverability.suggestedRecordSet.directive";
        var MODULE_REQUIREMENTS = [ CopyField.namespace, HTMLSafeString.namespace ];

        var SPLIT_REGEX = new RegExp("(.{1,255})", "g");

        var CONTROLLER_INJECTABLES = [ "$scope" ];
        var CONTROLLER = function SuggestedRecordSetController($scope) {

            $scope.domainName = $scope.domain.domain;

            $scope._suggestionMode = function() {
                $scope.label = LOCALE.maketext("Suggested “[_1]” ([_2]) Record", $scope.recordType.toUpperCase(), $scope.recordZoneType );
                $scope.record = $scope.domain.getSuggestedRecord($scope.recordType);
                $scope.noRecordMessage = LOCALE.maketext("Suggested “[_1]” does not exist.", $scope.recordType.toUpperCase());
                $scope.nameText = $scope.record.name;
                $scope.originalValueText = $scope.valueText = $scope.record.value;
            };

            $scope._currentMode = function() {
                $scope.label = LOCALE.maketext("Current “[_1]” ([_2]) Record", $scope.recordType.toUpperCase(), $scope.recordZoneType );
                $scope.record = $scope.domain.getCurrentRecord($scope.recordType);
                $scope.noRecordMessage = LOCALE.maketext("Current “[_1]” does not exist.", $scope.recordType.toUpperCase());
                $scope.nameText = $scope.record.name;
                $scope.originalValueText = $scope.valueText = $scope.record.value;
            };

            $scope._recordsReady = function() {
                if (!$scope.domain.recordsLoaded) {
                    return;
                }

                $scope.recordValid = $scope.domain.isRecordValid($scope.recordType);
                $scope.recordsLoaded = true;

                if ($scope.alwaysCurrent) {
                    $scope._currentMode();
                } else if ($scope.alwaysSuggested) {
                    $scope._suggestionMode();
                } else if ($scope.recordValid) {
                    $scope._currentMode();
                } else {
                    $scope._suggestionMode();
                }

                if (Object.keys($scope.record).length === 0) {
                    $scope.record = false;
                }
            };

            $scope._checkRecordsReady = function() {
                return $scope.domain.recordsLoaded;
            };

            $scope.splitMode = "full";

            $scope.toggleSplitMode = function() {
                $scope.splitMode = $scope.splitMode === "full" ? "split" : "full";

                if ( $scope.splitMode === "split" ) {

                    if ( !$scope.splitText ) {
                        var split = $scope.originalValueText.match(SPLIT_REGEX);
                        $scope.splitText = _.join( _.map(split, function(e) {
                            return "\"" + e + "\"";
                        }), " " );
                    }

                    $scope.valueText = $scope.splitText;
                } else {
                    $scope.valueText = $scope.originalValueText;
                }
            };

            $scope.$watch($scope._checkRecordsReady, $scope._recordsReady);

            $scope.label = LOCALE.maketext("Loading “[_1]” Record", $scope.recordType.toUpperCase() );

        };

        var module = angular.module(MODULE_NAMESPACE, MODULE_REQUIREMENTS);

        var DIRECTIVE_LINK = function($scope, $element, $attrs) {
            if (_.isUndefined($attrs["hideExtras"]) === false) {
                $scope.hideExtras = true;
            }
            if (_.isUndefined($attrs["alwaysSuggested"]) === false) {
                $scope.alwaysSuggested = true;
            }
            if (_.isUndefined($attrs["alwaysCurrent"]) === false) {
                $scope.alwaysCurrent = true;
            }
        };

        module.directive("suggestedRecordSet", function suggestedRecordSetDirectiveFactory() {

            return {
                templateUrl: TEMPLATE_PATH,
                scope: {
                    parentID: "@id",
                    domain: "=",
                    recordType: "@",
                    recordZoneType: "@",
                    splitable: "="
                },
                restrict: "E",
                replace: true,
                transclude: true,
                link: DIRECTIVE_LINK,
                controller: CONTROLLER_INJECTABLES.concat(CONTROLLER)
            };

        });

        return {
            "class": CONTROLLER,
            "namespace": MODULE_NAMESPACE,
            "template": TEMPLATE_PATH
        };
    }
);
