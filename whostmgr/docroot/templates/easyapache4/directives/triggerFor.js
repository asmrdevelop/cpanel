/*
# whostmgr/docroot/templates/cpanel_customization/directive/triggerFor.js     Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */
define([
    "angular"
], function(angular) {

    // This directive will trigger a "click" event on another element when the linked element is clicked.
    angular
        .module("App")
        .directive("triggerFor", [function() {
            return {
                restrict: "A",
                link: function link($scope, $element, $attrs) {
                    $element.bind("click", function() {
                        document.querySelector("#" + $attrs.triggerFor).click();
                    });
                }
            };
        }]);
});
