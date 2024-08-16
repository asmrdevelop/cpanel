define(
    [
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core"
    ],
    function(_, angular, LOCALE, CJT) {
        "use strict";

        // Retrieve the current application
        var app = angular.module("App");

        app.directive("tasklist",
            function() {
                var TEMPLATE_PATH = "directives/tasklist.phtml";
                var RELATIVE_PATH = "templates/task_queue_monitor/" + TEMPLATE_PATH;

                return {
                    replace: true,
                    restrict: "E",
                    scope: {
                        tasks: "=",
                    },
                    templateUrl: CJT.buildFullPath(RELATIVE_PATH),
                    controller: [ "$scope", function($scope) {
                        _.assign(
                            $scope,
                            {
                                isArray: angular.isArray.bind(angular),

                                taskAttributeLabel: {
                                    time: LOCALE.maketext("Scheduled Time[comment,the time at which a task is scheduled to happen]"),
                                    command: LOCALE.maketext("Command"),
                                    timestamp: LOCALE.maketext("Enqueue Time[comment,the time at which a task was placed in the queue]"),
                                    pid: LOCALE.maketext("Process ID"),
                                    retries_remaining: LOCALE.maketext("Remaining Retries"),
                                    child_timeout: LOCALE.maketext("Child Timeout"),
                                    id: LOCALE.maketext("Task ID"),
                                },

                                alwaysShow: {
                                    command: true,
                                    timestamp: true,
                                    time: true,
                                    pid: true,
                                },
                            }
                        );
                    } ],
                };
            }
        );
    }
);
