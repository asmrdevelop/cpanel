/*
# cpanel - whostmgr/docroot/templates/cpanel_customization/directives/triggerFor.js
#                                                  Copyright 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

define([
    "angular",
], function(angular) {
    "use strict";

    var module = angular.module("customize.directives.triggerFor", []);

    // This directive will trigger a "click" event on another element when the linked element is clicked.
    module.directive("triggerFor", [function() {
        return {
            restrict: "A",
            link: function link($scope, $element, $attrs) {
                $element.bind("click", function() {
                    document.querySelector("#" + $attrs.triggerFor).click();
                });
            },
        };
    }]);
});
