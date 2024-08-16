/*
# templates/easyapache4/views/additionalPackages.js                  Copyright(c) 2020 cPanel, L.L.C.
#                                                                   All rights reserved.
# copyright@cpanel.net                                                 http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
    ],
    function(angular) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("additionalPackages",
            ["$scope",
                function($scope) {
                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("additional");
                    });
                }
            ]
        );
    }
);
