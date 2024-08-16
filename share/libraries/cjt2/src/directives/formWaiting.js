/*
# cjt/directives/formWaiting.js                   Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "cjt/core"
    ],
    function(angular, CJT) {
        "use strict";

        var DEFAULT_SPINNER_SIZE = 4;

        var module = angular.module("cjt2.directives.formWaiting", []);

        var TEMPLATE_PATH = "libraries/cjt2/directives/formWaiting.phtml";

        /**
         * An attribute directive that disables and overlays a mask with
         * spinner on top of a form when the form is submitted. The
         * directive’s value is evaluated according to these rules:
         *  - If it’s boolean true, set the mask on.
         *  - If it’s a promise, set the mask on only when the promise
         *    is not yet finished.
         *  - If it’s falsey, set the mask off.
         *
         * IMPORTANT: The promise’s resolution needs to interact with
         * AngularJS. If you don’t use one of AngularJS’s own promises,
         * then you have to imitate its interaction with AngularJS’s
         * digest cycle. (maybe $apply() after a 0 $timeout?)
         *
         * Also, the <form> isn’t itself disabled; it’s actually
         * a <fieldset> element that gets inserted into the <form> and
         * wraps the given content. But there should be no functional
         * difference as long as the browser supports disabled <fieldset>.
         * This means that IE9 is not supported and that some other IE
         * versions act strangely, but visually there’s no actual breakage.
         *
         * This could be implemented by disabling the <form> rather than the
         * <fieldset>. (Maybe even getting rid of the <fieldset>?) This would
         * allow older browsers to work better, but this way seems better
         * encapsulated since we’re not altering the <form> element beyond
         * the directive’s transclusion.
         *
         * @example
         *
         * Example of how to use it:
         *
         * <form cp-form-waiting="doSubmit()">
         *      ... form elements
         * </form>
         *
         */

        module.directive("cpFormWaiting", [ "$parse", function($parse) {

            return {
                restrict: "A",

                transclude: true,

                scope: {
                    spinner_size: "@cpFormWaitingSpinnerSize",
                },

                templateUrl: CJT.config.debug ? CJT.buildFullPath(TEMPLATE_PATH) : TEMPLATE_PATH,

                link: function(scope, iElement, iAttrs, controller, transcludeFn) {
                    var _clear_promise = function _clear_promise() {
                        delete scope._show_mask;
                    };

                    if (!iAttrs.cpFormWaiting) {
                        throw "cp-form-waiting needs an expression!";
                    }

                    // Much of the below is adapted from the AngularJS
                    // source (src/ng/directive/ngEventDirs.js).

                    var fn = $parse(iAttrs.cpFormWaiting, /* interceptorFn */ null, /* expensiveChecks */ true);

                    iElement.on("submit", function(event) {
                        var promise = fn(scope.$parent, { $event: event });

                        if (promise === true) {
                            scope._show_mask = true;
                        } else if (promise) {

                            // We can’t assume this promise
                            // has a .finally() method …
                            scope._show_mask = promise;

                            // It’s possible that this promise is already
                            // completed. $q seems to do .then() on such a
                            // promise after a timeout; just in case, though,
                            // add .then() *after* we assign to scope; that way,
                            // if some engine were to do .then() in in the same
                            // execution thread, this won’t break.
                            promise.then(
                                _clear_promise,
                                _clear_promise
                            );
                        } else {
                            _clear_promise();
                        }

                        scope.$apply();
                    });
                },

                controller: [ "$scope", function($scope) {
                    if (!$scope.spinner_size) {
                        $scope.spinner_size = DEFAULT_SPINNER_SIZE;
                    }
                } ]
            };
        } ] );

        // ngTransclude will always use a sub-scope. This frustrates
        // the intent of this directive to be “seamless”; we don’t want
        // the <form>’s transcluded content to have to be “aware” that it
        // is transcluded. We use our own transclude logic so we can
        // manually set the scope to the same scope that the <form> uses.
        module.directive("cpFormWaitingTransclude", function() {
            return {
                restrict: "C",
                link: function(scope, el, attr, ctrl, transclude) {

                    // Magic incantation lifted from ngTransclude.js
                    transclude(

                        // Why we need this directive
                        scope.$parent,

                        function(clone) {
                            el.append(clone);
                        },
                        null,
                        attr.ngTransclude || attr.ngTranscludeSlot
                    );
                },
            };
        } );
    }
);
