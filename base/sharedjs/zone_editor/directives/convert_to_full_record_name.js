/*
# zone_editor/directives/convert_to_full_record_name.js         Copyright(c) 2020 cPanel, L.L.C.
#                                                                           All rights reserved.
# copyright@cpanel.net                                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define(
    [
        "angular"
    ],
    function(angular) {

        "use strict";

        var MODULE_NAMESPACE = "shared.zoneEditor.directives.convertToFullRecordName";
        var app = angular.module(MODULE_NAMESPACE, []);
        app.directive("convertToFullRecordName",
            ["Zones",
                function(Zones) {
                    return {
                        restrict: "A",
                        require: "ngModel",
                        scope: {
                            domain: "="
                        },
                        link: function(scope, element, attrs, ngModel) {

                        // we cannot work without ngModel
                            if (!ngModel) {
                                return;
                            }

                            // eslint-disable-next-line camelcase
                            function format_zone(eventName) {
                                var fullRecordName = Zones.format_zone_name(scope.domain, ngModel.$viewValue);
                                if (fullRecordName !== ngModel.$viewValue) {
                                    ngModel.$setViewValue(fullRecordName, eventName);
                                    ngModel.$render();
                                }
                            }

                            element.on("blur", function() {
                                format_zone("blur");
                            });

                            // trigger on Return/Enter
                            element.on("keydown", function(event) {
                                if (event.keyCode === 13) {
                                    format_zone("keydown");
                                }
                            });
                        }
                    };
                }
            ]);

        return {
            namespace: MODULE_NAMESPACE
        };

    }
);
