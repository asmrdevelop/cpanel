/*
# twofactorauth/directives/create_qrcode.js        Copyright(c) 2020 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular",
        "qrcode"
    ],
    function(angular, qrcode) {

        // Retrieve the current application
        var app;
        try {
            app = angular.module("App"); // For runtime
        } catch (e) {
            app = angular.module("App", []); // Fall-back for unit testing
        }
        app.directive("createQrCode", ["$timeout", function($timeout) {
            return {
                restrict: "A",
                scope: {
                    qrCodeData: "="
                },
                link: function(scope, element, attrs) {
                    /* jshint -W055 */
                    var the_qrcode = new qrcode(element[0]);
                    /* jshint +W055 */
                    scope.$watch("qrCodeData", function(newValue, oldValue) {
                        if (newValue && newValue.length > 0) {
                            the_qrcode.clear();
                            the_qrcode.makeCode(newValue);
                        }
                    });
                }
            };
        }]);
    }
);
