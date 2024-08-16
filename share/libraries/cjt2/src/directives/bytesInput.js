/*
# cjt/directives/bytesInput.js                    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "angular",
        "lodash",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/parse",
        "cjt/templates" // NOTE: Pre-load the template cache
    ],
    function(angular, _, CJT, LOCALE, PARSE) {
        "use strict";

        var RELATIVE_PATH = "libraries/cjt2/directives/bytesInput.phtml";

        var SI_UNITS = {
            B: { abbr: LOCALE.maketext("Bytes"), full: LOCALE.maketext("Bytes"),      multiplier: 0 },
            KB: { abbr: LOCALE.maketext("KB"),    full: LOCALE.maketext("Kilobytes"),  multiplier: 1 },
            MB: { abbr: LOCALE.maketext("MB"),    full: LOCALE.maketext("Megabytes"),  multiplier: 2 },
            GB: { abbr: LOCALE.maketext("GB"),    full: LOCALE.maketext("Gigabytes"),  multiplier: 3 },
            TB: { abbr: LOCALE.maketext("TB"),    full: LOCALE.maketext("Terabytes"),  multiplier: 4 },
            PB: { abbr: LOCALE.maketext("PB"),    full: LOCALE.maketext("Petabytes"),  multiplier: 5 },
            EB: { abbr: LOCALE.maketext("EB"),    full: LOCALE.maketext("Exabytes"),   multiplier: 6 },
            ZB: { abbr: LOCALE.maketext("ZB"),    full: LOCALE.maketext("Zettabytes"), multiplier: 7 },
            YB: { abbr: LOCALE.maketext("YB"),    full: LOCALE.maketext("Yottabytes"), multiplier: 8 },
        };

        var BINARY_UNITS = {
            B: { abbr: LOCALE.maketext("Bytes"), full: LOCALE.maketext("Bytes"),     multiplier: 0 },
            KiB: { abbr: LOCALE.maketext("KiB"),   full: LOCALE.maketext("Kibibytes"), multiplier: 1 },
            MiB: { abbr: LOCALE.maketext("MiB"),   full: LOCALE.maketext("Mebibytes"), multiplier: 2 },
            GiB: { abbr: LOCALE.maketext("GiB"),   full: LOCALE.maketext("Gibibytes"), multiplier: 3 },
            TiB: { abbr: LOCALE.maketext("TiB"),   full: LOCALE.maketext("Tebibytes"), multiplier: 4 },
            PiB: { abbr: LOCALE.maketext("PiB"),   full: LOCALE.maketext("Pebibytes"), multiplier: 5 },
            EiB: { abbr: LOCALE.maketext("EiB"),   full: LOCALE.maketext("Exbibytes"), multiplier: 6 },
            ZiB: { abbr: LOCALE.maketext("ZiB"),   full: LOCALE.maketext("Zebibytes"), multiplier: 7 },
            YiB: { abbr: LOCALE.maketext("YiB"),   full: LOCALE.maketext("Yobibytes"), multiplier: 8 },
        };

        // Retrieve the application object
        var module = angular.module("cjt2.directives.bytesInput", [
            "cjt2.templates"
        ]);

        /**
         * @summary Directive that allows for entering byte sizes while picking units such as MB/GB/TB/etc from a drop-down
         *
         * @attribute {String}        name          A name for the component. This will be used to set the name and id attributes
         *                                          on the text input field to "{{name}}InputValue" and the name and id attributed
         *                                          on the drop-down button to name="{{name}}DropDownButton". Defaults to
         *                                          "bytesInput".
         *
         * @attribute {String}        displayFormat Either 'si' or 'binary' to define whether to display SI (KB/MB/GB/etc) or
         *                                          binary (KiB/MiB/GiB/etc) units. Defaults to "si".
         *
         * @attribute {String}        valueFormat   Either 'si' or 'binary' to define whether to calculate the number of bytes using
         *                                          SI (1000/1000000/1000000000/etc) or binary (1024/1048576/1073741824/etc) values.
         *                                          Provided because cPanel typically displays SI units but calculates sizes in
         *                                          binary. Defaults to "binary".
         *
         * @attribute {Array[String]} allowedUnits  An array of strings indicating what values are selectable from the drop-down
         *                                          selector. Each element must be a valid SI or binary unit, depending on the
         *                                          displayFormat. Defaults to ["MB", "GB", "TB", "PB"] for the "si" displayFormat
         *                                          or ["MiB", "GiB", "TiB", "PiB"] for the binary displayFormat.
         *
         * @attribute {String}        defaultUnit   Which value to initially select in the drop-down selector. The value must be a
         *                                          valid SI or binary unit, depending on the displayFormat. If not specified, it
         *                                          will default to the smallest unit in the allowedUnits.
         *
         * @attribute {Number}        size          The size of the input field. This value will be directly applied to the size
         *                                          attribute on the <input> element. If not specified, it will default to 10.
         *
         * @attribute {Number}        maxlength     The maximum length of the input field. This value will be directly applied to
         *                                          the maxlength attribute on the <input> element. If not specified, it will
         *                                          default to 10.
         *
         * @attribute {String}        selectedUnit  The currently selected unit for the dropdown selector. A two way binding, it
         *                                          allows a string to be passed in to be converted to a unit object to be used
         *                                          internally by the directive. The string should be equivalent to the en-us
         *                                          abbreviation for the unit (e.g. MB, MiB, etc…)
         *
         * @attribute {Number}        bytesInputMax The maximum value of the input field. (optional)
         *
         * @attribute {Number}        bytesInputMin The minimum value of the input field. (optional)
         *
         * @attribute {Boolean}       isDisabled    True if the input field and drop-down selector should be disabled, false if
         *                                          not. This diverges from the typical use of the plain disabled attribute due
         *                                          to issues on IE11 where the descendents of an element can have unexpected
         *                                          behavior. See: {@link https://docs.angularjs.org/guide/ie}
         *
         * @required ngModel This directive requires ngModel be set on the element. The model value will be set to the number of
         *                   bytes specified by the component.
         *
         * NOTE: This directive is wired to support values up to Yobibytes (2 ^ 80), however the current implementation of Number
         *       in JavaScript limits the maximum value of an integer to 2 ^ 53 or 9 PiB. This is probably good enough for most
         *       practical applications, but if a value of greater than 2 ^ 53 is required, this directive will need to be
         *       updated to use BigInteger implementation. This would only be useful is the API backing the component usage also
         *       supports BigIntegers.
         *
         * @example
         * Using defaults:
         * <bytes-input ng-model="numberOfBytes"></bytes-input>
         *
         * Specifying all attributes:
         * <bytes-input ng-model="numberOfBytes"
         *      displayFormat="si"
         *      valueFormat="binary"
         *      allowedUnits="['MB', 'GB', 'TB']"
         *      defaultUnit="MB"
         *      size="5"
         *      maxlength="5"></bytes-input>
         *
         */
        module.directive("bytesInput", ["bytesInputConfig", "$timeout", function(bytesInputConfig, $timeout) {
            return {
                restrict: "E",
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                require: "ngModel",
                replace: true,
                scope: {
                    displayFormat: "@",
                    valueFormat: "@",
                    valueUnit: "@",
                    allowedUnits: "=",
                    defaultUnit: "@",
                    ngFocus: "&",
                    size: "=",
                    maxlength: "=",
                    extraInputClasses: "@",
                    isDisabled: "=",
                    selectedUnit: "="
                },

                link: function(scope, element, attrs, ngModel) {

                    if ( attrs.disabled !== undefined ) {
                        throw "Do not use “disabled” on this component, use “isDisabled” instead.";
                    }

                    var testViewValue = function(view, testFunc) {

                        if ( scope.isDisabled ) {
                            return true;
                        }

                        if ( ngModel.$isEmpty(view) ) {

                            // We have no value, skip this validation and let required take care of it
                            return true;
                        } else if ( scope.inputValue && scope.inputValue > 0 && ("" + scope.inputValue).length > scope.maxlength ) {

                            // Value is over maxlength, we're quietly trimming it, so ignore validation errors for it
                            // until the trim happens
                            return true;
                        } else {
                            return testFunc(view);
                        }

                    };

                    ngModel.$validators.max = function(model, view) {
                        return testViewValue(view, function(v) {
                            return !attrs.bytesInputMax || isNaN(attrs.bytesInputMax) ? true : view <= parseInt(attrs.bytesInputMax, 10);
                        });
                    };

                    ngModel.$validators.min = function(model, view) {
                        return testViewValue(view, function(v) {
                            return !attrs.bytesInputMin || isNaN(attrs.bytesInputMin) ? true : view >= parseInt(attrs.bytesInputMin, 10);
                        });
                    };

                    ngModel.$validators.integer = function(model, view) {
                        return testViewValue(view, function(v) {
                            var parsed = new Number(v);

                            // In this case, we really just want to compare value, not type
                            // eslint-disable-next-line eqeqeq
                            return parsed == parsed.toFixed(0);
                        });
                    };

                    element.find("input[type=number]").on("focus", function() {
                        this.select();
                    });

                    scope.setUnitFromString = function(str) {

                        // Set the selected unit to the string if it's provided and valid, otherwise use the smallest allowed
                        if ( str && scope.units[str] ) {
                            scope.selectedUnit = scope.units[str];
                        } else {
                            scope.selectedUnit = scope.units[Object.keys(scope.units)[0]];
                        }
                    };

                    var inputEl = element.find("input[type='number']");

                    scope.displayFormat = scope.displayFormat || bytesInputConfig.displayFormat;
                    scope.valueFormat = scope.valueFormat || bytesInputConfig.valueFormat;
                    scope.size = scope.size || bytesInputConfig.size;
                    scope.maxlength = scope.maxlength || bytesInputConfig.size;
                    scope.isDisabled = scope.isDisabled || false;
                    scope.required = scope.required || false;
                    scope.dirty = false;
                    scope.min = !attrs.bytesInputMin || isNaN(attrs.bytesInputMin) ? 0 : parseInt(attrs.bytesInputMin, 10);
                    scope.units = [];

                    scope.name = attrs.name || "bytesInput";

                    if ( scope.valueFormat === "si" ) {
                        scope.valueUnitObj = SI_UNITS[scope.valueUnit] || SI_UNITS[bytesInputConfig.valueUnit];
                    } else if ( scope.valueFormat === "binary" ) {
                        scope.valueUnitObj = BINARY_UNITS[scope.valueUnit] || BINARY_UNITS[bytesInputConfig.valueUnit];
                    }

                    // Check for bad displayFormat values
                    if ( scope.displayFormat === "si" || scope.displayFormat === "binary" ) {

                        // Pick out the allowed units from the full list
                        if ( scope.displayFormat === "si" ) {
                            scope.units = _.pick(SI_UNITS, scope.allowedUnits || bytesInputConfig.siAllowed);
                        } else if ( scope.displayFormat === "binary" ) {
                            scope.units = _.pick(BINARY_UNITS, scope.allowedUnits || bytesInputConfig.binaryAllowed);
                        }

                        scope.setUnitFromString(scope.defaultUnit);
                    }

                    scope.selectUnit = function(unit) {
                        if ( scope.units[unit] ) {
                            scope.selectedUnit = scope.units[unit];
                            scope.calculateValue();
                        }
                    };

                    scope.calculateValue = function() {

                        if ( scope.valueFormat !== "si" && scope.valueFormat !== "binary" ) {
                            ngModel.$setViewValue(undefined);
                            return;
                        }

                        if ( !scope.inputValue || scope.inputValue === "" || isNaN(scope.inputValue) ) {
                            ngModel.$setViewValue(scope.inputValue);
                            return;
                        }

                        var inputValue = new Number(scope.inputValue);

                        var inputMultiplier = scope.selectedUnit.multiplier;
                        var outputMultiplier = scope.valueUnitObj.multiplier;
                        var base = scope.valueFormat === "si" ? 1000 : 1024;
                        var value = inputValue * Math.pow(base, inputMultiplier) / Math.pow(base, outputMultiplier);

                        ngModel.$setViewValue(value);
                        ngModel.$validate();
                    };

                    scope.setFromModel = function() {

                        if ( !scope.selectedUnit || (scope.valueFormat !== "si" && scope.valueFormat !== "binary") ) {
                            return;
                        }

                        if ( typeof scope.selectedUnit === "string" ) {
                            scope.setUnitFromString(scope.selectedUnit);
                        }

                        var base = scope.valueFormat === "si" ? 1000 : 1024;
                        var inputMultiplier = scope.selectedUnit.multiplier;
                        var outputMultiplier = scope.valueUnitObj.multiplier;

                        if ( !ngModel.$modelValue || isNaN(ngModel.$modelValue) ) {

                            if ( ngModel.$modelValue === undefined && ngModel.$viewValue !== null && !isNaN(ngModel.$viewValue) ) {
                                scope.inputValue = ngModel.$viewValue * Math.pow(base, outputMultiplier) / Math.pow(base, inputMultiplier);
                            } else {
                                scope.inputValue = ngModel.$modelValue;
                            }

                        } else {

                            var modelValue = new Number(ngModel.$modelValue);
                            var newValue = parseInt(new Number(modelValue * Math.pow(base, outputMultiplier) / Math.pow(base, inputMultiplier)));

                            // This is just to prevent us from auto-editing things like 5.0 to 5 so it's not
                            // weirdly changing things for the user
                            // eslint-disable-next-line eqeqeq
                            if ( scope.inputValue != newValue ) {
                                scope.inputValue = newValue;
                            }

                        }

                        ngModel.$setDirty();
                        ngModel.$validate();
                    };

                    scope.$watch(
                        function() {
                            return ngModel.$modelValue;
                        },
                        scope.setFromModel
                    );

                    scope.$watch("inputValue", scope.calculateValue);

                    scope.$watch("selectedUnit", function() {
                        if ( typeof scope.selectedUnit === "string" ) {
                            scope.setUnitFromString(scope.selectedUnit);
                        }
                    });

                    scope.$watch(
                        function() {
                            return element.find("input[type=number]")[0].disabled;
                        },
                        function() {
                            var el = element.find("input[type=number]")[0];
                            if ( !el.disabled ) {
                                el.select();
                            }
                        }
                    );

                    if (scope.maxlength && scope.maxlength > 0) {
                        inputEl.on("input", function(e) {
                            var str = ("" + scope.inputValue);
                            if (str.length > scope.maxlength) {
                                scope.inputValue = parseInt(str.slice(0, scope.maxlength));
                            }
                        });
                    }

                }

            };

        }]);

        module.constant("bytesInputConfig", {
            displayFormat: "si",
            valueFormat: "binary",
            valueUnit: "B",
            siAllowed: ["MB", "GB", "TB", "PB"],
            binaryAllowed: ["MiB", "GiB", "TiB", "PiB"],
            size: 10,
            maxlength: 10
        });
    }
);
