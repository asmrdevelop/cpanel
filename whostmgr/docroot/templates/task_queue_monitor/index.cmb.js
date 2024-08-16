define(
    'app/directives/tasklist',[
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

/*
# whostmgr/docroot/templates/autossl/index.js        Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define, require, PAGE */
/* jshint -W100 */

define(
    'app/index',[
        "lodash",
        "angular",
        "cjt/util/locale",
        "cjt/core",
        "cjt/io/eventsource",
        "cjt/util/parse",
        "cjt/modules",
        "uiBootstrap",
    ],
    function(_, angular, LOCALE, CJT, EVENTSOURCE) {
        "use strict";

        var QUEUE_KEYS = ["waiting", "processing", "deferred"];

        CJT.config.html5Mode = false;

        function _massageTask(task) {
            task.timestamp = LOCALE.local_datetime( parseInt( task.timestamp, 10 ), "datetime_format_medium" );
            task.retries_remaining = LOCALE.numf( parseInt( task.retries_remaining, 10 ) );
            if (task.child_timeout && task.child_timeout > 0) {
                task.child_timeout = LOCALE.maketext("[quant,_1,second,seconds]", parseInt( task.child_timeout, 10 ));
            }

            var newTask = {};
            for (var key in task) {
                if ((task[key] !== null) && (task[key] !== undefined)) {
                    newTask[key] = task[key];
                }
            }

            return newTask;
        }

        return function() {
            angular.module("App", [
                "cjt2.config.whm.configProvider", // This needs to load before any of its configured services are used.
                "ui.bootstrap",
                "cjt2.whm",
                "angular-growl",
            ]);

            return require(
                [
                    "cjt/bootstrap",

                    // Application Modules
                    "uiBootstrap",

                    "app/directives/tasklist",
                ],
                function appRequire(BOOTSTRAP) {
                    var app = angular.module("App");

                    // This prevents performance issues
                    // when the queue gets large.
                    // cf. https://docs.angularjs.org/guide/animations#which-directives-support-animations-
                    app.config(["$animateProvider",
                        function($animateProvider) {
                            $animateProvider.classNameFilter(/INeverWantThisToAnimate/);
                        }
                    ]);

                    app.controller("BaseController", [
                        "$rootScope",
                        "$scope",
                        "growl",
                        function($rootScope, $scope, growl) {

                            $scope.LOCALE = LOCALE;

                            function _publish() {
                                $scope.last_update_descr = LOCALE.maketext("Last update received at: [local_datetime,_1,time_format_medium]", new Date());
                                $rootScope.$apply();
                            }

                            var sseUrl = PAGE.security_token + "/sse/Tasks";

                            EVENTSOURCE.create(sseUrl).then( function(e) {
                                var sse = e.target;

                                // NB: It would be ideal to have a useful
                                // error handler; however, EventSource doesn’t
                                // seem to provide very useful error events.

                                sse.addEventListener("queue-update", function(e) {
                                    var payload = JSON.parse(e.data);

                                    $scope.queue_count = 0;

                                    QUEUE_KEYS.forEach( function(key) {
                                        payload[key] = payload[key].map(_massageTask);
                                        $scope.queue_count += payload[key].length;
                                    } );

                                    $scope.queue = payload;
                                    _publish();
                                });

                                sse.addEventListener("sched-update", function(e) {
                                    var payload = JSON.parse(e.data);
                                    payload = payload.map( function(schedItem) {
                                        return _.assign(
                                            {
                                                time: LOCALE.local_datetime(schedItem.time, "datetime_format_medium"),
                                            },
                                            _massageTask(schedItem.task)
                                        );
                                    } );

                                    $scope.sched = payload;
                                    _publish();
                                });

                                var suppressErrorNotice;
                                window.addEventListener("beforeunload", function(e) {
                                    suppressErrorNotice = true;
                                });

                                // EventSource doesn’t actually tell us anything
                                // useful in its error objects.
                                sse.onerror = function(e) {
                                    if (!suppressErrorNotice) {
                                        growl.error( LOCALE.maketext("An unknown [asis,EventSource] error occurred at [local_datetime,_1,time_format_short].", new Date() ) );
                                    }
                                };
                            } ).catch( function(e) {
                                var msg = "Failed to connect (" + _.escape(sseUrl) + "): " + _.escape(e);

                                growl.error(msg);
                            } );
                        }
                    ] );

                    BOOTSTRAP();
                }
            );
        };
    }
);

