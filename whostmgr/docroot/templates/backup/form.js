CPANEL.namespace("CPANEL");

/* jshint -W079 */
var EVENT = EVENT || YAHOO.util.Event,
    DOM = DOM || YAHOO.util.Dom;

/**
 * The Form module provides common methods of working with form data and behavior
 *
 * @module Form
 *
 */
CPANEL.Form = {

    /**
     * Removes all children from the supplied container.
     *
     * @method purgeContainer
     * @param {String | HTMLElement} container The id of an element or element to be emptied
     */
    purgeContainer: function(container) {
        container = DOM.get(container);
        EVENT.purgeElement(container, true); // remove action listeners
        container.innerHTML = "";
    },

    /**
     * A helper method to ensure that IE 7 & 8 fire the change event.
     *
     * @method fireChanged
     * @param {Event} e The event object
     */
    fireChanged: function(e) {
        var target = e.target || e.srcElement;
        target.blur();
        target.focus();
    },

    /**
     * A helper method to manage error states of form fields.
     *
     * @method checkPolicy
     * @param {HTMLElement} container A container for the field to be checked
     * @param {Boolean} policy A statement when true will remove errors from the field
     * @param {HTMLElement} error The Page Notice to show if policy is false
     */
    checkPolicy: function(container, policy, error) {
        if (policy) {
            DOM.addClass(container, "hidden");
            DOM.removeClass(error, "active");
            DOM.removeClass(error, "error");
        } else {
            DOM.removeClass(container, "hidden");
            DOM.addClass(error, "active");
            DOM.addClass(error, "error");
        }
    },

    /**
     * Loops over the supplied form's elements array and adds key value pairs for each
     * set of form values associated with a name. Element values are pushed into an array
     * which is then stored as the value of the key with the element name as follows:
     *
     * { elementName: valueArray }
     *
     * @method getData
     * @param {HTMLElement} form The form element to get data from
     * @return {Object} A structure containing key value pairs of form names and their values
     */
    getData: function(form) {

        // ensure the form exists before attempting to retrieve data from it
        if ((form = DOM.get(form))) {
            var elements = form.elements,
                data = {},
                valueArray = [],
                valueCounter = 0,
                fieldLength;

            for (var i = 0, length = elements.length; i < length; i++) {
                var currentElement = elements[i];

                // skip form elements that do not have a name
                if (typeof currentElement.name === "undefined" || currentElement.name === "") {
                    continue;
                }

                // set the field length when looking at a new set of form elements
                if (typeof fieldLength === "undefined") {
                    if (typeof form[currentElement.name].length !== "undefined") {
                        fieldLength = form[currentElement.name].length;
                    } else {
                        fieldLength = 0;
                    }
                }

                // skip disabled form elements and remove them from the length counter
                if (currentElement.disabled) {
                    if (fieldLength-- === 0) {
                        fieldLength = undefined;
                    }
                } else {

                    // push values from checked inputs in checkbox group and radio fields
                    if (fieldLength > 0 && currentElement.type !== "select-one") {
                        if (currentElement.checked) {
                            valueArray.push(currentElement.value);
                        }
                        valueCounter++;
                    } else if (currentElement.type === "checkbox") {

                        // push value of a single checked checkbox or 0 if it is unchecked
                        if (currentElement.checked) {
                            valueArray.push(currentElement.value);
                        } else {
                            valueArray.push("0");
                        }
                    } else if (typeof currentElement.value !== "undefined" &&
                        currentElement.value !== "") {

                        // push value of text, textarea, password, hidden, and select fields
                        valueArray.push(currentElement.value);
                    }
                }

                // add value array to the data object
                if (valueCounter === 0 || valueCounter === fieldLength) {
                    if (valueArray.length > 0) {
                        data[currentElement.name] = valueArray.toString();
                    }
                    valueArray = [];
                    valueCounter = 0;
                    fieldLength = undefined;
                }
            }
            return data;
        } else {
            return null;
        }
    },

    /**
     * Toggles the active state of dependent options and their containers
     *
     * @method toggleDependentOptions
     * @param {Event} e The event object
     * @param {String} [enabledValue="1"] The value of a dependent input that enables dependent options
     */
    toggleDependentOptions: function(e, enabledValue) {
        enabledValue = typeof enabledValue !== "undefined" ? enabledValue : "1";
        var target = e.target || e.srcElement,
            checkbox = target.type === "checkbox" ? true : false,
            container = target.id.replace(/_[^_]+(?![\s\S])/, "_options"),
            inputs = DOM.getElementsByClassName("advanced-option", "input", container),
            errors = DOM.getElementsByClassName("error", "span", container),
            alternateContainer = DOM.getElementsByClassName(container + "-alternate", "div"),
            alternateInputs = [],
            alternateErrors;
        if (alternateContainer.length > 0) {
            alternateInputs = DOM.getElementsByClassName("advanced-option", "input", alternateContainer[0]);
            alternateErrors = DOM.getElementsByClassName("error", "span", alternateContainer[0]);
        }
        if ((checkbox && target.checked) || (!checkbox && target.value === enabledValue)) {
            if (alternateInputs.length > 0) {
                DOM.addClass(alternateContainer[0], "collapsed");
                DOM.addClass(alternateContainer[0], "inactive");

                // avoid error handling for inactive alternates
                DOM.removeClass(alternateErrors, "active");
            }
            DOM.removeClass(container, "collapsed");
            DOM.removeClass(container, "inactive");
            DOM.addClass(errors, "active");
        } else {
            if (alternateInputs.length > 0) {
                DOM.removeClass(alternateContainer[0], "collapsed");
                DOM.removeClass(alternateContainer[0], "inactive");

                // activate error handling for alternates
                DOM.addClass(alternateErrors, "active");
            }
            DOM.addClass(container, "collapsed");
            DOM.addClass(container, "inactive");
            DOM.removeClass(errors, "active");
        }

        for (var i = 0, length = inputs.length; i < length; i++) {
            inputs[i].disabled = inputs[i].disabled ? false : true;
        }
        for (i = 0, length = alternateInputs.length; i < length; i++) {
            alternateInputs[i].disabled = alternateInputs[i].disabled ? false : true;
        }
    },

    /**
     * Toggles the loading and enabled states of a button
     *
     * @method toggleLoadingButton
     * @param {String | HTMLElement} action The button to set a loading state on
     */
    toggleLoadingButton: function(action) {
        if (typeof action === "string") {
            action = DOM.get(action);
        }
        var spinner = DOM.getElementsByClassName("spinner", "div", action)[0];
        if (!spinner) {
            action = action.parentNode;
            spinner = DOM.getElementsByClassName("spinner", "div", action)[0];
        } // Chrome focus is on the button text instead of the button
        if (DOM.hasClass(action, "loading")) {

            // remove loading state
            DOM.removeClass(action, "loading");
            DOM.removeClass(action.parentNode, "disabled");
            action.disabled = false;
        } else {

            // set loading state
            action.disabled = true;
            DOM.addClass(action.parentNode, "disabled");
            spinner.style.width = action.offsetWidth + "px";
            DOM.addClass(action, "loading");
        }
    },

    /**
     * Adds a mask that prevents user actions except for the area of the supplied focus
     *
     * @method setFocusMask
     * @param {String | HTMLElement} focus The input, fieldset, or form to focus
     */
    setFocusMask: function(focus) {
        var mask = DOM.get("focus_mask");
        focus = DOM.get(focus);
        if (typeof (focus) !== "undefined") {
            if (focus.tagName === "INPUT" && focus.checked) {
                var node = DOM.getAncestorByClassName(focus, "form-group").parentNode,
                    elements = focus.form.elements;
                DOM.addClass(node, "focus");

                // disable fields from the same form that are outside of the focus
                for (var i = 0, length = elements.length; i < length; i++) {
                    var advancedOptionContainer = DOM.getAncestorByClassName(elements[i], "advanced-options-container");
                    if (DOM.hasClass(advancedOptionContainer, "inactive")) {

                        // skip inactive advanced option sections as they are already disabled
                        continue;
                    }
                    if ((elements[i].tagName === "BUTTON" || elements[i].tagName === "INPUT" || elements[i].tagName === "SELECT") && elements[i].name !== focus.name) {
                        elements[i].disabled = true;
                        DOM.addClass(elements[i], "out-of-focus");
                    }
                }
            } else if (focus.tagName === "FORM" || focus.tagName === "FIELDSET") {
                DOM.addClass(focus, "focus");
            }
            CPANEL.Form.resizeFocusMask();
            DOM.removeClass(mask, "hidden");
        }
    },

    /**
     * Resizes the focus mask to the appropriate dimensions
     *
     * @method resizeFocusMask
     */
    resizeFocusMask: function() {
        var mask = DOM.get("focus_mask"),
            focus = DOM.getElementsByClassName("focus")[0],
            parentForm,
            region,
            height,
            width;
        if (focus.tagName === "FORM" || focus.tagName === "FIELDSET") {
            parentForm = YAHOO.util.Selector.query("form", "content", true);
            region = DOM.getRegion(focus);
            width = region.width + "px";
            height = region.top - DOM.getRegion(parentForm).top + 2 + "px";
        } else {
            parentForm = DOM.getAncestorByTagName(focus, "FORM");
            region = DOM.getRegion(parentForm);
            width = region.width + "px";
            height = region.bottom - region.top + "px";
        }
        DOM.setStyle(mask, "height", height);
        DOM.setStyle(mask, "width", width);
    },

    /**
     * Slides the focus mask up out of view and removes the focus class
     *
     * @method clearFocusMask
     */
    clearFocusMask: function() {
        var outOfFocus = DOM.getElementsByClassName("out-of-focus");
        for (var i = 0, length = outOfFocus.length; i < length; i++) {
            outOfFocus[i].disabled = false;
            DOM.removeClass(outOfFocus[i], "out-of-focus");
        }
        DOM.addClass("focus_mask", "hidden");
        DOM.removeClass(DOM.getElementsByClassName("focus")[0], "focus");
    },

    /**
     * A class that provides input validation based on class names that match defined functions of the validator
     *
     * @class Validator
     */
    Validator: function() {
        var validators = [];

        /**
         * Adds matching validation rules from the input element's classes
         *
         * @method register
         * @param {String|HTMLElement} field The input element to attach validators to
         * @param {String|Function} callback The method to be called on input
         */
        this.register = function(field, callback) {
            field = DOM.get(field);
            callback = typeof callback !== "function" ? this.callback : callback;
            var delay = function() {
                    setTimeout(callback.bind(this, field), 5);
                },
                tests = field.className.replace("validate", "").trim().split(" "),
                field_container = DOM.getAncestorByClassName(field, "form-group"),
                field_test = {};
            for (var i = 0, length = tests.length; i < length; i++) {
                field_test = {
                    field: field,
                    validator: this[tests[i]],
                    field_container: field_container,
                    error_container: DOM.getElementsByClassName(tests[i], "span", field_container)[0]
                };
                if (typeof field_test.validator === "function") {
                    validators.push(field_test);
                    if (CPANEL.dom.has_oninput) {
                        EVENT.on(field, "input", callback, field);
                    } else {
                        EVENT.on(field, "keyup", callback, field);
                        EVENT.on(field, "change", callback, field);
                        EVENT.on(field, "paste", delay, field);
                    }
                }
            }
        };

        /**
         * The default callback method for field input events
         *
         * @method callback
         * @param {Event} e The event object
         * @param {String|HTMLElement} field The input element that fired the event
         */
        this.callback = function(e, field) {

            // skip validation if the field is disabled
            if (field.disabled) {
                return;
            }

            var field_container = DOM.getAncestorByClassName(field, "field");
            var failed = 0;

            // loop over the validators for this instance to find ones matching this field
            for (var i = 0, length = validators.length; i < length; i++) {
                var currentValidator = validators[i];

                // skip to the next validator if the current one is not for this field
                if (currentValidator.field.id !== field.id) {
                    continue;
                }

                // Manage error classes for the validation message depending on validator result.
                // No need to check if it is disabled here since we do that at the beginning of
                // the callback.
                if (currentValidator.validator(currentValidator.field)) {
                    DOM.removeClass(currentValidator.error_container, "active");
                    DOM.removeClass(currentValidator.error_container, "error");
                } else {
                    DOM.addClass(currentValidator.error_container, "active");
                    DOM.addClass(currentValidator.error_container, "error");
                    failed++;
                }
            }

            // if there was a failure, mark the field container as invalid
            if (failed > 0) {
                DOM.addClass(field_container, "error");
            } else {
                DOM.removeClass(field_container, "error");
            }
        };

        /**
         * A method to validate all the registered fields
         *
         * @method verify
         */
        this.verify = function() {
            for (var i = 0, length = validators.length; i < length; i++) {
                this.callback(null, validators[i].field);
            }
        };

        /**
         * Validates a field if it has a value
         *
         * @method required
         * @param {String|HTMLElement} field The input element to test
         */
        this.required = function(field) {
            return !(typeof field.value.length !== "undefined" && field.value.length === 0);
        };

        /**
         * Validates a field does not contain slashes
         *
         * @method noslashes
         * @param {String|HTMLElement} field The input element to test
         */
        this.noslashes = function(field) {
            if (field.value.indexOf("/") < 0 && field.value.indexOf("\\") < 0) {
                return true;
            }

            return false;
        };

        /**
         * Validates a field is within a range specified by it's min and max values
         *
         * @method range
         * @param {String|HTMLElement} field The input element to test
         */
        this.range = function(field) {
            if (!CPANEL.validate.positive_integer(field.value)) {
                return false;
            }
            var value = parseInt(field.value, 10),
                min = parseInt(DOM.getAttribute(field, "min"), 10),
                max = parseInt(DOM.getAttribute(field, "max"), 10);
            return (value >= min && value <= max);
        };

        /**
         * Validates a field is greater than a minimum specified by it's min value
         *
         * @method minimum
         * @param {String|HTMLElement} field The input element to test
         */
        this.minimum = function(field) {
            if (!CPANEL.validate.positive_integer(field.value)) {
                return false;
            }
            var value = parseInt(field.value, 10),
                min = parseInt(DOM.getAttribute(field, "min"), 10);
            return (value >= min);
        };

        /**
         * Validates a field is less than a maximum percentage specified by it's max value
         *
         * @method maximum_percent
         * @param {String|HTMLElement} field The input element to test
         */
        this.maximum_percent = function(field) {
            var value = parseInt(field.value, 10),
                max = parseInt(DOM.getAttribute(field, "max"), 10),
                units = document.getElementById(DOM.getAttribute(field, "id") + "_unit");
            if (units.value == "MB") {
                return true;
            }
            return (value <= max);
        };

        /**
         * Validates a field is a valid absolute path
         *
         * @method path
         * @param {String|HTMLElement} field The input element to test
         */
        this.path = function(field) {
            if (field.value.indexOf("/") !== 0) {
                return false;
            }
            return CPANEL.validate.dir_path(field.value);
        };

        /**
         * Validates a field is a valid relative path
         *
         * @method relative
         * @param {String|HTMLElement} field The input element to test
         */
        this.relative = function(field) {

            // allow optional field to be empty
            if (field.value.length === 0) {
                return true;
            }
            if (field.value.indexOf("/") === 0) {
                return false;
            }
            if (field.value.substring(0, 3) === "../") {
                return false;
            }
            return CPANEL.validate.dir_path(field.value);
        };

        /**
         * Validates a field is a valid remote path
         *
         * @method remote
         * @param {String|HTMLElement} field The input element to test
         */
        this.remote = function(field) {

            // allow optional field to be empty
            if (field.value.length === 0) {
                return true;
            }
            if (field.value.substring(0, 3) === "../") {
                return false;
            }
            return CPANEL.validate.dir_path(field.value);
        };

        /**
         * Validates a field is a valid key filename with no spaces
         *
         * @method keyname
         * @param {String|HTMLElement} field The input element to test
         */
        this.keyname = function(field) {

            // allow optional field to be empty
            if (field.value.length === 0) {
                return true;
            }
            if (!CPANEL.validate.no_chars(field.value, " ")) {
                return false;
            }
            return CPANEL.validate.filename(field.value);
        };

        /**
         * Validates a field is a valid host while disallowing leading protocols
         * and trailing posts.
         *
         * @method host
         * @param {String|HTMLElement} field The input element to test
         */
        this.host = function(field) {

            // remote destination should not be a loopback, see local destination
            if (/^(127(\.\d+){1,3}|[0:]+1|localhost)$/i.test(field.value)) {
                return false;
            }

            // otherwise just light hostname checking and let the
            // backend do the majority of the heavy lifting.
            // Allow a-z, 0-9, . and -
            // require at least 1 character.
            return (/^[a-z0-9.\-]{1,}$/i.test(field.value));
        };

        /**
         * Validates a field is empty or the appropriate length for a passphrase
         *
         * @method passphrase
         * @param {String|HTMLElement} field The input element to test
         */
        this.passphrase = function(field) {
            if (field.value === "") {
                return true;
            }
            var min = parseInt(DOM.getAttribute(field, "minlength"), 10),
                max = parseInt(DOM.getAttribute(field, "maxlength"), 10),
                length = field.value.length;
            return (typeof length !== "undefined" && length >= min && length <= max);
        };

        /**
         * Validates a field is the appropriate length for a required name
         *
         * @method name_length
         * @param {String|HTMLElement} field The input element to test
         */
        this.name_length = function(field) {

            // Does not check for empty input because required method will
            // reject input validation
            var min = parseInt(DOM.getAttribute(field, "minlength"), 10),
                max = parseInt(DOM.getAttribute(field, "maxlength"), 10),
                length = field.value.length;

            return (typeof length !== "undefined" && length >= min && length <= max);
        };
    }
};
