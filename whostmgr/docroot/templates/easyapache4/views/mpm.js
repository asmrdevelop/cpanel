/*
# templates/easyapache4/views/mpm.js                  Copyright(c) 2020 cPanel, L.L.C.
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

        // Retrieve the current application
        var app = angular.module("App");

        app.controller("mpm",
            ["$scope",
                function($scope) {
                    $scope.$on("$viewContentLoaded", function() {
                        $scope.customize.loadData("mpm");
                    });
                }
            ]
        );
    }
);