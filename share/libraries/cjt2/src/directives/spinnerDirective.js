/*
# cjt/directives/spinnerDirective.js                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */


// ------------------------------------------------------------
// Developer notes:
// ------------------------------------------------------------
// The concept for this construct was derived from:
// angular-spinner version 0.2.1
// License: MIT.
// Copyright (C) 2013, Uri Shaked.
// Sources:
// http://ngmodules.org/modules/angular-spinner
// Used with permission.
// ------------------------------------------------------------

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/parse",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, _, CJT, parse) {
        "use strict";

        var module = angular.module("cjt2.directives.spinner", [
            "cjt2.templates"
        ]);

        /**
         * Service that runs the spinners in a user interface.
         *
         * @example
         *
         * Start all spinners:
         *
         * spinnerAPI.start();
         *
         * Stop all spinners:
         *
         * spinnerAPI.stop();
         *
         * Start a spinner by id:
         *
         * spinnerAPI.start("top");
         *
         * Stop a spinner by id:
         *
         * spinnerAPI.stop("top");
         *
         * Start a spinner by group name:
         *
         * spinnerAPI.stargGroup("loading");
         *
         * Stop a spinner by group name:
         *
         * spinnerAPI.stopGroup("loading");
         */

        module.factory("spinnerAPI", function() {

            /**
             * Collection of active spinners. Must register then with the semi-private
             * _add() api.
             * @type {Object}
             */
            var spinners = {};

            /**
             * Catchup queue. Actions are added here for spinners that can not be
             * found in the spinners collection and then run once those spinners appear.
             * @type {Array}
             */
            var queue = [];


            /**
             * Flush out any outstanding actions in the queue.
             *
             * @private
             * @method _flushQueue
             * @return {[type]} [description]
             */
            var _flushQueue = function() {
                queue = [];
            };

            /**
             * Make an action from the arguments
             *
             * @private
             * @_makeAction
             * @param  {String} fnName Name of the spinner method to call.
             * @param  {String} id     Optional spinner id
             * @param  {String} group  Optional spinner group name
             * @param  {Array} args    Array, usually just the parameters passed to the caller so it a psudo array.
             * @return {Object}        Packaged action object.
             */
            var _makeAction = function(fnName, id, group, args) {
                return {
                    fnName: fnName,
                    args: args,
                    id: id,
                    group: group
                };
            };

            /**
             * Runs the requested action
             *
             * @private
             * @_runAction
             * @param  {Object} action
             */
            var _runAction = function(action) {
                switch (action.fnName) {
                    case "start":
                        _start.apply(null, action.args);
                        break;
                    case "startGroup":
                        _startGroup.apply(null, action.args);
                        break;
                    case "stop":
                        _stop.apply(null, action.args);
                        break;
                    case "stopGroup":
                        _stopGroup.apply(null, action.args);
                        break;
                    case "kill":
                        _kill.apply(null, action.args);
                        break;
                    case "killGroup":
                        _killGroup.apply(null, action.args);
                        break;
                }
            };

            /**
             * Process the queue of pending catchup items
             *
             * @private
             * @_processQueue
             */
            var _processQueue = function() {
                var action;
                while ( ( action = queue.shift() ) ) {
                    if ( (action.id    && _has(action.id) ) ||
                        (action.group && _hasGroup(action.group))
                    ) {
                        _runAction(action);
                    }
                }
            };

            /**
             * Enqueue an action for future processing
             *
             * @private
             * @_enqueue
             * @param  {Object} action Action to perform
             */
            var _enqueue = function(action) {
                queue.push(action);
            };


            /**
             * Accounting helper to start a spinner.
             *
             * @method  _startSpin
             * @private
             * @param  {Spinner} spinner
             * @param  {Boolean} show
             */
            var _startSpin = function(spinner, show) {
                var className = spinner.scope.spinClass;
                if (className) {
                    spinner.element.addClass(className);
                }
                spinner.scope.display = show;
                spinner.scope.running = true;
            };

            /**
             * Accounting helper to stop a spinner.
             *
             * @method  _startSpin
             * @private
             * @param  {Spinner} spinner
             * @param  {Boolean} show
             * @param  {String} [className]
             */
            var _stopSpin = function(spinner, show) {
                var className = spinner.scope.spinClass;
                if (className) {
                    spinner.element.removeClass(className);
                }
                spinner.scope.display = show;
                spinner.scope.running = false;
            };

            /**
             * Test if the spinner is registered with the API.
             *
             * @method has
             * @param  {String}  [id] Optional Identifier for the spinner. If not passed then reports is any spinners are registered.
             * @return {Boolean}    true if the spinner exists, false otherwise.
             */
            var _has = function(id) {
                if (!id) {
                    return spinners.length > 0;
                } else {
                    return !!spinners[id];
                }
            };

            /**
             * Test if a spinner from the group is available.
             *
             * @method hasGroup
             * @param  {String} className CSS class to look for...
             * @return {Boolean}          true if the spinner exists, false otherwise.
             */
            var _hasGroup = function(className) {
                if (!className) {
                    return false;
                } else {
                    var keys = _.keys(spinners);
                    for (var i = keys.length; i > -1; i--) {
                        var key = keys[i];
                        if (key) {
                            var spinner = spinners[key];
                            if (spinner.element.hasClass(className)) {
                                return true;
                            }
                        }
                    }
                    return false;
                }
            };

            /**
             * Stop the specified spinner, if id is not passed, stops all spinners.
             *
             * @method stop
             * @param {String} id Identifier for the spinner.
             * @param {Boolean} [show] show state after the stop. Defaults to false meaning the element is hidden when stopped.
             */
            var _stop = function(id, show) {
                show = !_.isUndefined(show) ? show : false;
                if (!id) {
                    angular.forEach(spinners, function(spinner) {
                        _stopSpin(spinner, show);
                    });
                } else {
                    var spinner = spinners[id];
                    if (spinner) {
                        _stopSpin(spinner, show);
                    }
                }
            };

            /**
             * Stop the group of spinners with the designated CSS class.
             *
             * @method stopGroup
             * @param  {String} className CSS class to look for...
             * @param  {Boolean} [show] show state after the stop. Defaults to false meaning the element is hidden when stopped.
             */
            var _stopGroup = function(className, show) {
                show = !_.isUndefined(show) ? show : false;
                angular.forEach(spinners, function(spinner) {
                    if (spinner.element.hasClass(className)) {
                        _stopSpin(spinner, show);
                    }
                });
            };

            /**
             * Starts the specified spinner, if id is not passed, starts all the spinners
             *
             * @method start
             * @param  {String} id Identifier for the spinner.
             * @param  {Boolean} [show] show state after the start. Defaults to true meaning the element is visible when spinning.
             */
            var _start = function(id, show) {
                show = !_.isUndefined(show) ? show : true;
                if (!id) {
                    angular.forEach(spinners, function(spinner) {
                        _startSpin(spinner, true);
                    });
                } else {
                    var spinner = spinners[id];
                    if (spinner) {
                        _startSpin(spinner, true);
                    }
                }
            };

            /**
             * Start the group of spinners with the designated CSS class.
             *
             * @method startGroup
             * @param  {String} className CSS class to look for...
             * @param  {Boolean} [show] show state after the start. Defaults to true meaning the element is visible when spinning.
             */
            var _startGroup = function(className, show) {
                show = !_.isUndefined(show) ? show : true;
                angular.forEach(spinners, function(spinner) {
                    if (spinner.element.hasClass(className)) {
                        _startSpin(spinner, show, "fa-spin");
                    }
                });
            };

            /**
             * Kills the specified spinner, if id is not passed, kills all the spinners
             *
             * @private
             * @method _kill
             * @param  {String} id Identifier for the spinner.
             */
            var _kill = function(id) {
                var spinner;

                if (!id) {
                    var keys = _.keys(spinners);
                    for (var i = keys.length; i > -1; i--) {
                        var key = keys[i];
                        if (key) {
                            _stopSpin(spinners[key], false, "fa-spin");
                            spinners[key] = null;
                            delete spinners[key];
                        }
                    }
                } else {
                    if (id) {
                        spinner = spinners[id];
                        if (spinner) {
                            _stopSpin(spinner, false, "fa-spin");
                            spinners[id] = null;
                            delete spinners[id];
                        } else {

                            // check the queue instead
                            for (var j = queue.length - 1; j >= 0; j--) {
                                if (queue[j].id === id) {
                                    queue.splice(j, 1);
                                }
                            }
                        }
                    }
                }
            };

            /**
             * Kill a group of spinners by classname
             *
             * @private
             * @method _killGroup
             * @param  {String} className CSS class to look for...
             */
            var _killGroup = function(className) {
                var keys = _.keys(spinners);
                var found = false;
                for (var i = keys.length; i > -1; i--) {
                    var key = keys[i];
                    if (key) {
                        var spinner = spinners[key];
                        if (spinner.element.hasClass(className)) {
                            _stopSpin(spinner, false, "fa-spin");
                            spinners[key] = null;
                            delete spinners[key];
                            found = true;
                        }
                    }
                }

                if (!found) {

                    // Check the queue instead
                    for (var j = queue.length - 1; j >= 0; j--) {
                        if (queue[j].className === className) {
                            queue.splice(j, 1);
                        }
                    }
                }
            };

            return {
                spinners: spinners,

                /**
                 * Add a spinner management object to the system.
                 *
                 * @method add
                 * @protected
                 * @param {String}  id Identifier for the spinner.
                 * @param {Element} element    Wrapped element.
                 * @param {Boolean} autoStart  Start the animation if true, do not start the animation if false or undefined.
                 * @param {Boolean} show       Show state after the stop. Defaults to false meaning the element is hidden when stopped.
                 */
                _add: function(id, element, autoStart, show, scope) {
                    var spinner = spinners[id] = {
                        id: id,
                        element: element,
                        scope: scope
                    };

                    if (autoStart) {
                        _startSpin(spinner, show);
                    } else {
                        _stopSpin(spinner, show);
                    }

                    // Try to catch up now that there is a new one added
                    _processQueue();
                },

                has: _has,
                hasGroup: _hasGroup,

                /**
                 * Starts the specified spinner, if id is not passed, starts all the spinners. If id is passed, but the spinner has not
                 * been added yet, the request will be queued.
                 *
                 * @method start
                 * @param  {String} id Identifier for the spinner.
                 * @param  {Boolean} [show] show state after the start. Defaults to true meaning the element is visible when spinning.
                 */
                start: function(id, show) {
                    if (id && !_has(id)) {
                        _enqueue(_makeAction("start", id, null, arguments));
                    } else {
                        _start(id, show);
                    }
                },

                /**
                 * Start the group of spinners with the designated CSS class. If className is passed, but the spinner has not
                 * been added yet, the request will be queued.
                 *
                 * @method startGroup
                 * @param  {String} className CSS class to look for...
                 * @param  {Boolean} [show] show state after the start. Defaults to true meaning the element is visible when spinning.
                 */
                startGroup: function(className, show) {
                    if (className && !_hasGroup(className)) {
                        _enqueue(_makeAction("startGroup", null, className, arguments));
                    } else {
                        _startGroup(className, show);
                    }
                },

                /**
                 * Stop the specified spinner, if id is not passed, stops all spinners. If id is passed, but the spinner has not
                 * been added yet, the request will be queued.
                 *
                 * @method stop
                 * @param {String} id Identifier for the spinner.
                 * @param {Boolean} [show] show state after the stop. Defaults to false meaning the element is hidden when stopped.
                 */
                stop: function(id, hide) {
                    if (id && !_has(id)) {
                        _enqueue(_makeAction("stop", id, null, arguments));
                    } else {
                        _stop(id, hide);
                    }
                },

                /**
                 * Stop the group of spinners with the designated CSS class.
                 * Stop the group of spinners with the designated CSS class. If className is passed, but the spinner has not
                 * been added yet, the request will be queued.
                 *
                 * @method startGroup
                 * @param  {String} className CSS class to look for...
                 * @param  {Boolean} [show] show state after the start. Defaults to true meaning the element is visible when spinning.
                 */
                stopGroup: function(className, hide) {
                    if (className && !_hasGroup(className)) {
                        _enqueue(_makeAction("stopGroup", null, className, arguments));
                    } else {
                        _stopGroup(className, hide);
                    }
                },

                /**
                 * Kills the specified spinner, if id is not passed, kills all the spinners. If id is passed, but the spinner has not
                 * been added yet, the request will be queued.
                 *
                 * @method kill
                 * @param  {String} id Identifier for the spinner.
                 */
                kill: function(id) {
                    if (id && !_has(id)) {
                        _enqueue(_makeAction("kill", id, null, arguments));
                    } else {
                        _kill(id);
                    }
                },

                /**
                 * Kill a group of spinners by CSS class name.  If className is passed, but the spinner has not
                 * been added yet, the request will be queued.
                 *
                 * @method killGroup
                 * @param  {String} className CSS class to look for...
                 */
                killGroup: function(className) {
                    if (className && !_hasGroup(className)) {
                        _enqueue(_makeAction("killGroup", null, className, arguments));
                    } else {
                        _killGroup(className);
                    }
                },

                /**
                 * Flush out any outstanding actions in the action queue
                 *
                 * @method flushQueue
                 */
                flush: _flushQueue
            };
        });

        /**
         * Directive that generates a spinner in the user interface.
         *
         * @attribute {Object}  spinner          configuration for the spinner.
         * @attribute {Boolean} [cpAutostart] optional starts the spinner automatically if true, doesn't if false. Defaults to false.
         * @attribute {Boolean} [cpShow]      optional shows the glyph if true, doesn't if false. Defaults to false.
         * @attribute {Boolean} [groupClass]  optional css group name for use with startGroup and stopGroup API.
         * @attribute {Boolean} [glyphClass]  optional css class to define the glyph to use in the directive.
         * @attribute {Boolean} [spinClass]   optional css class to define how to start the animation.
         * @example
         * Basic spinner
         * <div spinner></div>
         *
         * Non-auto-start Spinner, invisible while not running:
         *
         * <div spinner cp-autostart="false"></div>
         *
         * Visible while not running:
         *
         * <div spinner cp-show="true"></div>
         *
         * Making two spinners part of a group:
         *
         * <div spinner group-class="loading" id="top"></div>
         * <div spinner group-class="loading" id="bottom"></div>
         *
         */
        module.directive("spinner", ["spinnerAPI",
            function(spinnerAPI) {
                var ct = 0;
                var RELATIVE_PATH = "libraries/cjt2/directives/spinner.phtml";
                return {
                    scope: true,
                    restrict: "EA",
                    replace: true,
                    controller: ["$scope",
                        function($scope) {
                            $scope.api     = spinnerAPI;
                            $scope.display = false;
                            $scope.running = false;
                        }
                    ],
                    templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                    compile: function(element, attrs) {
                        return {
                            pre: function(scope, element, attrs) {
                                if (_.isUndefined(attrs.glyphClass)) {
                                    attrs.glyphClass = "fas fa-spinner fa-2x";
                                }

                                if (_.isUndefined(attrs.spinClass)) {
                                    attrs.spinClass = "fa-spin";
                                }

                                if (_.isUndefined(attrs.id) || attrs.id === "") {
                                    attrs.id =  "spinner_" + ct++;
                                }
                            },
                            post: function(scope, element, attrs) {
                                var show = !_.isUndefined(attrs.cpShow) ? parse.parseBoolean(attrs.cpShow) : false;
                                var autoStart = !_.isUndefined(attrs.cpAutostart) ? parse.parseBoolean(attrs.cpAutostart) : false;

                                var id = attrs.id;
                                element.attr("id", id);

                                // These are used to group spinners into groups
                                // for startGroup and stopGroup API calls. Not needed
                                // if you don't intend to use those api calls.
                                var groupClass = attrs.groupClass;
                                if (groupClass) {
                                    if (!element.hasClass(groupClass)) {
                                        element.addClass(groupClass);
                                    }
                                }

                                var glyphClass = attrs.glyphClass;
                                if (glyphClass) {
                                    if (!element.hasClass(glyphClass)) {
                                        element.addClass(glyphClass);
                                    }
                                }

                                // Setup the scope
                                scope.id        = id;
                                scope.spinClass = attrs.spinClass;


                                scope.$on("$destroy", function() {
                                    scope.api.kill(scope.id);
                                });

                                scope.api._add(scope.id, element, autoStart, show, scope);
                            }
                        };
                    }
                };
            }]);
    }
);
