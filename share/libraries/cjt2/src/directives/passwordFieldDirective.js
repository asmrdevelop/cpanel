/*
# cjt/directives/passwordFieldDirective.js          Copyright(c) 2020 cPanel, L.L.C.
#                                                             All rights reserved.
# copyright@cpanel.net                                           http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* global define: false */

define(
    [
        "angular",
        "cjt/core",
        "cjt/util/locale",
        "cjt/util/passwordGenerator",
        "cjt/directives/checkStrength",
        "cjt/directives/validateMinimumPasswordStrength",
        "cjt/directives/updatePasswordStrengthDirective",
        "cjt/directives/displayPasswordStrength",
        "cjt/decorators/dynamicName",
        "cjt/directives/limitRange",
        "cjt/templates"
    ],
    function(angular, CJT, LOCALE, GENERATOR) {

        // Constants
        var DEFAULT_MINIMUM_STRENGTH = 10;
        var DEFAULT_MINIMUM_LENGTH = 1;
        var DEFAULT_MAXIMUM_LENGTH = 100;
        var DEFAULT_GENERATOR_MINIMUM_LENGTH = 10;
        var DEFAULT_GENERATOR_MAXIMUM_LENGTH = 18;
        var DEFAULT_NO_REQ_TEXT = LOCALE.translatable("This password has a strength of [_1].");
        var DEFAULT_DOES_NOT_MEET_TEXT = LOCALE.translatable("This password has a strength of [_1], but your system requires a strength of [_2].");
        var DEFAULT_MEETS_OR_EXCEEDS_TEXT = LOCALE.translatable("This password has a strength of [_1], which meets or exceeds the system requirement of [_2].");
        var DEFAULT_PLACEHOLDER = LOCALE.maketext("Enter Password");
        var DEFAULT_GENERATE_BUTTON_TEXT = LOCALE.maketext("Generate");
        var DEFAULT_GENERATE_BUTTON_TITLE = LOCALE.maketext("Auto generates password.");
        var DEFAULT_GENERATE_SETTINGS_TITLE = LOCALE.maketext("Adjust the generate password options.");
        var DEFAULT_TOGGLE_VIEW_BUTTON_TITLE = LOCALE.maketext("Show or Hide password.");

        var RELATIVE_PATH = "libraries/cjt2/directives/passwordField.phtml";

        var SCOPE_DECLARATION = {
            name: "@?name",
            placeholder: "@?placeholder",
            caption: "@?caption",
            minimumStrength: "@minimumStrength",
            password: "=password",
            passwordStrength: "=passwordStrength",
            maximumLength: "@maximumLength",
            minimumLength: "@minimumLength",
            showMeter: "@?showMeter",
            showStrength: "@?showStrength",
            showToggleView: "@?showToggleView",
            strengthMeetsTemplate: "@?",
            strengthDoesNotMeetTemplate: "@?",
            strengthNoRequirementTemplate: "@?",
            showGenerator: "@?showGenerator",
            toggleViewButtonTitle: "@?",
            toggleViewButtonTabIndex: "@?",
            generateMinimumLength: "@?",
            generateMaximumLength: "@?",
            generateButtonText: "@?",
            generateButtonTitle: "@?",
            generateButtonTabIndex: "@?",
            generateSettingsTitle: "@?",
            generateSettingsTabIndex: "@?",
            generateSettingsLengthLabel: "@?",
            generateSettingsAlphaTitle: "@?",
            generateSettingsAlphaBothLabel: "@?",
            generateSettingsAlphaLowerLabel: "@?",
            generateSettingsAlphaUpperLabel: "@?",
            generateSettingsOtherTitle: "@?",
            generateSettingsBothNumersAndSymbolsLabel: "@?",
            generateSettingsNumbersLabel: "@?",
            generateSettingsSymbolsLabel: "@?"
        };

        var RESERVED_ATTRIBUTES = Object.keys(SCOPE_DECLARATION);
        RESERVED_ATTRIBUTES.push("id");

        var module = angular.module("cjt2.directives.password", [
            "cjt2.directives.checkPasswordStrength",
            "cjt2.directives.minimumPasswordStrength",
            "cjt2.directives.updatePasswordStrength",
            "cjt2.directives.displayPasswordStrength",
            "cjt2.directives.limitRange",
            "cjt2.decorators.dynamicName",
            "cjt2.templates"
        ]);

        /**
         * Convert the form state into the options for the generate method.
         *
         * @scope  private
         * @name   makeOptions
         * @param  {Object} scope
         * @return {Object} Password generation options.
         */
        function makeOptions(scope) {
            return {
                length: scope.passwordLength,
                lowercase: scope.alpha === "both" || scope.alpha === "lower",
                uppercase: scope.alpha === "both" || scope.alpha === "upper",
                numbers: scope.nonalpha === "both" || scope.nonalpha === "numbers",
                symbols: scope.nonalpha === "both" || scope.nonalpha === "symbols"
            };
        }

        /**
         * Setup the scope from the default password generator options.
         *
         * @scope  private
         * @name  initializeScope
         * @param  {Object} scope
         * @param  {Object} options
         */
        function initializeScope(scope, options) {
            scope.defaultLength = GENERATOR.DEFAULT_OPTIONS.length;
            scope.length = options.length;
            if (options.lowercase && options.uppercase) {
                scope.alpha = "both";
            } else if (options.lowercase) {
                scope.alpha = "lower";
            } else if (options.uppercase) {
                scope.alpha = "upper";
            }

            if (options.numbers && options.symbols) {
                scope.nonalpha = "both";
            } else if (options.numbers) {
                scope.nonalpha = "numbers";
            } else if (options.symbols) {
                scope.nonalpha = "symbols";
            }

            // make sure the generate can't produce an invalid length password.
            if (scope.minimumLength && scope.generateMinimumLength < scope.minimumLength) {
                scope.generateMinimumLength = scope.minimumLength;
            }

            if (scope.maximumLength && scope.generateMaximumLength > scope.maximumLength) {
                scope.generateMaximumLength = scope.maximumLength;
            }
        }

        /**
         * Directive that renders the a single password field with its main decorations.
         *
         * @directive password
         * @attribute {Number}  minimumStrength Minimum strength.
         * @attribute {Binding} password
         * @attribute {Binding} passwordStrength
         * @attribute {String}  [name]         optional name of the password field
         * @attribute {String}  [placeholder]  optional placeholder text for the password
         * @attribute {String}  [toggleViewButtonTitle]
         *
         * Validation specific attributes:
         * @attribute {Boolean} [showMeter]    optional if truthy, then shows the meter, otherwise hides the meter. If not provided will default to true.
         * @attribute {Boolean} [showStrength] optional if truthy, then shows the strength, otherwise hides the strength. If not provided will default to false.
         * @attribute {String}  [strengthMeetsTemplate]         optional, override the meets text template
         * @attribute {String}  [strengthDoesNotMeetTemplate]   optional, override the not meets text template
         * @attribute {String}  [strengthNoRequirementTemplate] optional, override the no requirement text template
         * @attribute {Number}  [minimumStrength]  optional, minimum strength required. Strength is returnted from a server side service.
         * @attribute {Number}  [minimumLength]    optional, minimum length for a password. 1 if not set.
         * @attribute {Number}  [maximumLength]    optional, maximum length for a password. 100 if not set.
         *
         * Generator specific attributes:
         * @attribute {Boolean} [showGenerator]  optional, if truthy, will show the generator, otherwise, with hide the generator. Hidden by default.
         * @attribute {Number} [generateMinimumLength] optional, minimum length you can generate a password. Defaults to minimumLength if not set, but minimumLength is set. Otherwise, its 1.
         * @attribute {Number} [generateMaximumLength] optional, length limit for the password generator. Defaults to maximumLength if not set, but maximumLength is set. Not enforced otherwise.
         * @attribute {String} [generateButtonText]    optional, button text on the generate button.
         * @attribute {String} [generateButtonTitle]   optional, title text on the generate button.
         * @attribute {String} [generateSettingsTitle] optional, title ont eh settings button.
         * @attribute {String} [generateSettingsLengthLabel] optional, label on the length control.
         * @attribute {String} [generateSettingsAlphaTitle]  optional, label on the alpha selector as a whole.
         * @attribute {String} [generateSettingsAlphaBothLabel] optional, label on the alpha both radio button.
         * @attribute {String} [generateSettingsAlphaLowerLabel] optional, label on the lower only radio button.
         * @attribute {String} [generateSettingsAlphaUpperLabel] optional, label on the upper only radio button.
         * @attribute {String} [generateSettingsOtherTitle]      optional, label on the other characters selector as a whole.
         * @attribute {String} [generateSettingsBothNumersAndSymbolsLabel] optional, label on the numbers and symbols both radio button.
         * @attribute {String} [generateSettingsNumbersLabel] optional, label on the numbers only radio button.
         * @attribute {String} [generateSettingsSymbolsLabel] optional, label on the symbols only radio button.
         *
         * @example
         * <input check-password-strength minimum-password-strength="10" />
         */
        module.directive("password", ["$timeout", function($timeout) {

            var _setDefault = function(attrs, field, def) {
                if (angular.isUndefined(attrs[field])) {
                    attrs[field] = def;
                }
            };

            return {
                restrict: "E",
                replace: true,
                scope: SCOPE_DECLARATION,
                templateUrl: CJT.config.debug ? CJT.buildFullPath(RELATIVE_PATH) : RELATIVE_PATH,
                compile: function(element, attrs) {

                    var inputEl = element.find("input.field");
                    var obscuredField = inputEl[0];
                    var unobscuredField = inputEl[1];

                    var settingsFirstEl = element.find("input.length-field");

                    // Copy all the attributes meant for the input
                    // control from the <span> to the <input> tag.
                    Object.keys(attrs).forEach(function(name) {
                        if (!(/^[$]/.test(name)) && RESERVED_ATTRIBUTES.indexOf(name) === -1) {

                            // Lookup the original attribute name
                            var markupAttrName = attrs.$attr[name];

                            // Move the attribute to the input tag.
                            inputEl.attr(markupAttrName, attrs[name] || "");
                            element.removeAttr(markupAttrName);
                        }
                    });

                    return {
                        pre: function(scope, element, attrs) {

                            _setDefault(attrs, "name", "txtPassword");
                            _setDefault(attrs, "placeholder", DEFAULT_PLACEHOLDER);
                            _setDefault(attrs, "caption", LOCALE.maketext("Select the length and characters to use when generating a password:"));

                            _setDefault(attrs, "showMeter", true);
                            _setDefault(attrs, "showToggleView", true);
                            _setDefault(attrs, "showStrength", true);
                            _setDefault(attrs, "strengthDoesNotMeetTemplate", DEFAULT_DOES_NOT_MEET_TEXT);
                            _setDefault(attrs, "strengthMeetsTemplate", DEFAULT_MEETS_OR_EXCEEDS_TEXT);
                            _setDefault(attrs, "strengthNoRequirementTemplate", DEFAULT_NO_REQ_TEXT);

                            _setDefault(attrs, "minimumStrength", DEFAULT_MINIMUM_STRENGTH);
                            _setDefault(attrs, "minimumLength", DEFAULT_MINIMUM_LENGTH);
                            _setDefault(attrs, "maximumLength", DEFAULT_MAXIMUM_LENGTH);

                            _setDefault(attrs, "showGenerator", false);

                            _setDefault(attrs, "toggleViewButtonTitle", DEFAULT_TOGGLE_VIEW_BUTTON_TITLE);

                            _setDefault(attrs, "generateMaximumLength", DEFAULT_GENERATOR_MAXIMUM_LENGTH);
                            _setDefault(attrs, "generateMinimumLength", DEFAULT_GENERATOR_MINIMUM_LENGTH);
                            _setDefault(attrs, "generateButtonText", DEFAULT_GENERATE_BUTTON_TEXT);
                            _setDefault(attrs, "generateButtonTitle", DEFAULT_GENERATE_BUTTON_TITLE);
                            _setDefault(attrs, "generateSettingsTitle", DEFAULT_GENERATE_SETTINGS_TITLE);

                            _setDefault(attrs, "generateSettingsLengthLabel", LOCALE.maketext("Length"));
                            _setDefault(attrs, "generateSettingsAlphaTitle", LOCALE.maketext("Letters"));
                            _setDefault(attrs, "generateSettingsAlphaBothLabel", LOCALE.maketext("Both [asis,(aBcD)]"));
                            _setDefault(attrs, "generateSettingsAlphaLowerLabel", LOCALE.maketext("Lowercase [asis,(abcd)]"));
                            _setDefault(attrs, "generateSettingsAlphaUpperLabel", LOCALE.maketext("Uppercase [asis,(ABCD)]"));
                            _setDefault(attrs, "generateSettingsOtherTitle", LOCALE.maketext("Numbers and Symbols"));
                            _setDefault(attrs, "generateSettingsBothNumersAndSymbolsLabel", LOCALE.maketext("Both [asis,(1@3$)]"));
                            _setDefault(attrs, "generateSettingsNumbersLabel", LOCALE.maketext("Numbers [asis,(123)]"));
                            _setDefault(attrs, "generateSettingsSymbolsLabel", LOCALE.maketext("Symbols [asis,(@#$)]"));

                            // this needs to be initialized on the scope at this point so we
                            // can check it in the post
                            scope.showStrength          = attrs.showStrength;
                            scope.showGenerator         = attrs.showGenerator;
                            scope.generateMinimumLength = attrs.generateMinimumLength;
                            scope.generateMaximumLength = attrs.generateMaximumLength;
                        },
                        post: function(scope, element, attrs) {
                            scope.showSettings = false;
                            scope.show = false;
                            scope.passwordLength = GENERATOR.DEFAULT_OPTIONS.length;
                            scope.defaultLength = GENERATOR.DEFAULT_OPTIONS.length;
                            initializeScope(scope, GENERATOR.DEFAULT_OPTIONS);

                            /**
                             * Toggles the password field between obscured and hidden text.
                             */
                            scope.toggle = function() {
                                scope.show = !scope.show;
                                $timeout(function() {
                                    var el = angular.element(obscuredField);
                                    if (el) {
                                        el.focus();
                                    }
                                }, 10);
                            };

                            /**
                             * Generate a new password and show it.
                             */
                            scope.generate = function() {
                                var options = makeOptions(scope);
                                var newPassword = GENERATOR.generate(options);
                                scope.password = newPassword;
                                scope.show = true;
                                $timeout(function() {
                                    var el = angular.element(unobscuredField);
                                    if (el) {
                                        el.focus();
                                    }
                                }, 10);
                            };

                            /**
                             * Toggle the setting panel to show or hide it
                             */
                            scope.toggleSettings = function() {
                                scope.showSettings = !scope.showSettings;
                                if (scope.showSettings) {
                                    $timeout(function() {
                                        var el = angular.element(settingsFirstEl);
                                        if (el) {
                                            el.focus();
                                        }
                                    }, 10);
                                }
                            };

                            /**
                             * Listen for the passwordStrengthChange event and update the currentStrengthText when fired.
                             */
                            scope.$on("passwordStrengthChange", function(event, result) {

                                // Make sure the event is for our control
                                if ( result.id === scope.name )  {
                                    scope.updateCurrentStrengthText(result.strength, result.password);
                                }
                            });

                            /**
                             * Updates the guiding strength text that shows up below the password input.
                             *
                             * @method updateCurrentStrengthText
                             * @param  {Number} strength   The strength of the current password, as
                             *                             returned from the passwordStrengthService.
                             * @param  {String} password   The current password.
                             */
                            scope.updateCurrentStrengthText = function(strength, password) {
                                if (angular.isString(scope.minimumStrength)) {
                                    scope.minimumStrength = parseInt(scope.minimumStrength, 10);
                                    if (isNaN(scope.minimumStrength)) {
                                        scope.minimumStrength = DEFAULT_MINIMUM_STRENGTH;
                                    }
                                }

                                if (scope.showStrength) {
                                    if (angular.isDefined(strength) && password) {
                                        if (scope.minimumStrength > 0) {
                                            if (strength < scope.minimumStrength) {
                                                if (angular.isDefined(scope.strengthDoesNotMeetTemplate)) {
                                                    scope.currentStrengthText = LOCALE.makevar(scope.strengthDoesNotMeetTemplate, strength, scope.minimumStrength);
                                                }
                                            } else {
                                                if (angular.isDefined(scope.strengthMeetsTemplate)) {
                                                    scope.currentStrengthText = LOCALE.makevar(scope.strengthMeetsTemplate, strength, scope.minimumStrength);
                                                }
                                            }
                                        } else {
                                            if (angular.isDefined(scope.strengthNoRequirementTemplate)) {
                                                scope.currentStrengthText = LOCALE.makevar(scope.strengthNoRequirementTemplate, strength);
                                            }
                                        }
                                    } else {

                                        // For cases where our password model isn't populated, we don't want any text.
                                        scope.currentStrengthText = "";
                                    }
                                }
                            };
                        }
                    };
                }
            };
        }]);

        return {
            DEFAULT_MINIMUM_STRENGTH: DEFAULT_MINIMUM_STRENGTH,
            DEFAULT_DOES_NOT_MEET_TEXT: DEFAULT_DOES_NOT_MEET_TEXT,
            DEFAULT_MEETS_OR_EXCEEDS_TEXT: DEFAULT_MEETS_OR_EXCEEDS_TEXT,
            DEFAULT_PLACEHOLDER: DEFAULT_PLACEHOLDER,
            RELATIVE_PATH: RELATIVE_PATH
        };
    });
