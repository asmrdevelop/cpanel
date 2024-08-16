// Copyright 2023 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

/* jshint eqeqeq:false,-W108,-W089 */
/* eslint-disable camelcase, no-use-before-define */

/**
    The validate module contains a validator class and methods used to validate user input.
    @module validate
*/
(function() {
    "use strict";

    function _log(text) {
        if (window.console && window.console.log) {
            window.console.log(arguments);
        }
    }

    function _trace() {
        if (window.console && window.console.trace) {
            window.console.trace(arguments);
        }
    }

    /**
     * Validate the local part of a username for an account.
     * Its everything before the @ symbol.
     * @private
     * @param  {String}  text             Text to validate
     * @param  {String}  spec             Name of the validation rules to use: rfc or cpanel
     * @param  {Boolean} charCheckOnly    When true, the validator ony checks the character regex
     * @return {Boolean}                  true if the text is valid, false otherwise.
     */
    function _validate_local_part(text, spec, charCheckOnly) {

        // Initialize the parameters
        spec = spec || "rfc";
        text = text || "";
        charCheckOnly = !!charCheckOnly;

        // If text is empty, it's not a valid email but
        // doesn't contain any illegal characters either
        if (text === "") {
            return charCheckOnly;
        }

        // Validate the inputs
        if (spec !== "cpanel" && spec !== "rfc") {
            throw ("CPANEL.validate.local_part_email: invalid spec argument!");
        }

        // text must contain only these characters
        var pattern;
        if (spec === "rfc") {
            pattern = new RegExp("[^.a-zA-Z0-9!#$%&'*+/=?^_`{|}~-]");
        } else {

            // This is the current set of chars allowed when creating a new cPanel email address
            pattern = new RegExp("[^.a-zA-Z0-9_-]");
        }

        if (pattern.test(text) === true) {
            return false;
        }

        if (charCheckOnly) {
            return true;
        }

        if (spec === "rfc") {

            // NOTE: These are broken out on individual pages for cpanel validators.

            // if the text has '.' as the first or last character then it's not valid
            if (text.charAt(0) === "." || text.charAt(text.length - 1) === ".") {
                return false;
            }

            // if the texting contains '..' then it's not valid
            if (/\.\./.test(text) === true) {
                return false;
            }
        }

        return true;
    }

    // check to be sure the CPANEL global object already exists
    if (typeof CPANEL === "undefined" || !CPANEL) {
        _log("You must include the CPANEL global object before including validate.js!");
    } else {

        /**
            The validate class contains the validator class and methods used to validate user input.<br />
            @class validate
            @namespace CPANEL
            @extends CPANEL
        */
        CPANEL.validate = {

            hide_validation_summary: false,

            // To be .concat()ed onto an array that already contains the context el ID.
            // This registers an Overlay instance that is intended to update with
            // various page changes.
            // NOTE: This can't run at page-load time because CJT's CLDR data is loaded
            //* after* the rest of CJT.
            get_page_overlay_context_arguments: function() {
                var overlay_anchor;
                var form_el_anchor;
                if (LOCALE.is_rtl()) {
                    overlay_anchor = "tr";
                    form_el_anchor = "tl";
                } else {
                    overlay_anchor = "tl";
                    form_el_anchor = "tr";
                }

                return [overlay_anchor, form_el_anchor, ["beforeShow", "windowResize", CPANEL.align_panels_event]];
            },
            a: "",
            form_checkers: {},

            /**
                The validator class is used to provide validation to a group of &lt;input type="text" /&gt; fields.<br /><br />
                For example: You could use one validator object per fieldset and treat each fieldset group as one validation unit,
                or you create a validator object for each &lt;input type="text" /&gt; element on the page.  The class is designed to be flexible
                enough to work in any validation situation.<br /><br />
                HTML:<br />
                <pre class="brush: xml">
                &lt;form method="post" action="myform.cgi" /&gt;
                &nbsp;&nbsp;&nbsp;&nbsp;&lt;input type="text" id="user_name" name="user_name" /&gt;
                &nbsp;&nbsp;&nbsp;&nbsp;&lt;input type="text" id="user_email" name="user_email" /&gt;
                &nbsp;&nbsp;&nbsp;&nbsp;&lt;input type="submit" id="submit_user_info" value="Submit" /&gt;
                &lt;/form&gt;
                </pre>
                JavaScript:
                <pre class="brush: js">
                // create a new a validator object for my input fields
                var my_validator = new CPANEL.validate.validator("Contact Information Input");&#13;

                // add validators to the input fields
                my_validator.add("user_name", "min_length(%input%, 5)", "User name must be at least 5 characters long.");
                my_validator.add("user_name", "standard_characters", "User name must contain standard characters.  None of the following: &lt; &gt; [ ] { } \");
                my_validator.add("user_email", "email", "That is not a valid email address.");&#13;

                // attach the validator to the input fields (this adds automatic input validation when the user types in the field)
                my_validator.attach();&#13;

                // attach an event handler to the submit button in case they try to submit with invalid data
                YAHOO.util.Event.on("submit_info", "click", validate_form);&#13;

                // this function gets called when the submit button gets pressed
                function validate_form(event) {
                &nbsp;&nbsp;&nbsp;&nbsp;if (my_validator.is_valid() == false) {
                &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;YAHOO.util.Event.preventDefault(event);     // prevent the form from being submitted
                &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;CPANEL.validate.show_modal_error( my_validator.error_messages() );  // show a modal error dialog box
                &nbsp;&nbsp;&nbsp;&nbsp;}
                &nbsp;&nbsp;&nbsp;&nbsp;else {
                &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;// the "event" function gets called and the form gets submitted (in practice you don't need the "else" clause)
                &nbsp;&nbsp;&nbsp;&nbsp;}
                };
                </pre>
                @class validator
                @namespace CPANEL.validate
                @constructor
                @param {string} title The title of the validator instance.  A human-readable title used to identify your validator against others that may be on the same page.
            */
            validator: function(title) {

                if (YAHOO.util.CustomEvent) {
                    this.validateSuccess = new YAHOO.util.CustomEvent("validateSuccess", this);
                    this.validateFailure = new YAHOO.util.CustomEvent("validateFailure", this);
                }

                /**
                    The title of the validator instance.  A human-readable title used to identify your validator against others that may be on the same page.
                    @property title
                    @type string
                    @for CPANEL.validate.validator
                */
                if (typeof (title) !== "string") {
                    _trace();
                    _log("You need to pass the title of the validator object into the constructor.\nie: var my_validator = new CPANEL.validate.validator(\"Email Account\");");
                    return;
                }
                this.title = title;

                /**
                    An array of validators.  Holds all the important information about your validator object.<br />
                    This value is public, but in practice you will probably never need to access it.  I left it public for all those cases I couldn't think of where someone might need to access it directly.
                    @property validators
                */
                this.validators = [];

                // A thin wrapper to allow addition of functions that indicate
                // invalidity by throwing an exception, where the exception
                // is the message to display.
                this.add_thrower = function(el, func) {
                    var msg;
                    var catcher = function() {
                        try {
                            func.apply(this, arguments);
                            return true;
                        } catch (err) {
                            msg = err;
                            return false;
                        }
                    };

                    return this.add(el, catcher, function() {
                        return msg;
                    });
                };

                /**
                    Adds an validator function to the validators array.<br />
                    <br />
                    example:<br />
                    <pre class="brush: js">
                    var my_validator = new CPANEL.validate.validator("My Validator");&#13;

                    // add a function literal; here I'm assuming my_custom_function is defined elsewhere
                    // remember that your custom function should return true or false
                    my_validator.add("input_element", function() { my_custom_function(DOM.get("input_element").value) }, "My custom error message.");&#13;

                    // if the second argument is a string it's assumed to be a method of CPANEL.validate, in this case CPANEL.validate.url
                    my_validator.add("input_element", "url('httq://yahoo.com')", "That is not a valid URL.");&#13;

                    // if the second argument has no parenthesis it's assumed to call the value of the input element
                    // in this case CPANEL.validate.email( YAHOO.util.Dom.get("input_element").value )
                    my_validator.add("input_element", "email", "That is not a valid email address.");&#13;

                    // use %input% to refer to the element's value: YAHOO.util.Dom.get("input_element").value
                    my_validator.add("input_element", "if_not_empty(%input%, CPANEL.validate.url)", "That is not a valid url.");
                    my_validator.add("input_element", "min_length(%input%, 5)", "Input must be at least 5 characters long.");
                    </pre>

                    NOTE: If an *_error element has a “no_panel” class, then the validation
                    messages are given as tooltips only rather than as overlays.
                    This can help to reduce clutter in the UI.

                    @method add
                    @param {DOM element} el a DOM element or id, gets passed to YAHOO.util.Dom.get
                    @param {string | function} func either a string or a function, WARNING: strings get eval'ed after some regex, see above for the syntax
                    @param {string | function} msg the error message to be shown when func returns false; should be localized already;
                */
                this.add = function(el, func, msg, conditional_func, opts) {
                    return this._do_add.apply(this, arguments);
                };

                /**
                    Add a function that will only trigger an error message on form submit.
                    The function will always fire, but if its error is the only error, then the error message
                    will not appear, and the validation is hidden. This allows avoiding telling users that
                    "you must do this before submission!!" when they may well be about to do that very thing.

                    Same interface as for this.add().
                    XXX: The flag-passing is an expedience. Ideal would be separate lists of validator items,
                    but that would require change throughout this module. This is a new feature added to
                    legacy code, so minimal change is ideal.
                */
                this.add_for_submit = function(el, func, msg, conditional_func, opts) {
                    opts = opts || {};
                    opts.submit_only = true;
                    return this._do_add(el, func, msg, conditional_func, opts);
                };

                this._do_add = function(orig_el, func, msg, conditional_func, opts) {

                    // verify that the element exists in the DOM
                    var el = YAHOO.util.Dom.get(orig_el);
                    if (!el) {
                        _trace();
                        _log("Error in CPANEL.validate.add: could not find element '" + orig_el + "' in the DOM");
                        return;
                    }

                    var error_element_id = el.id + "_error";
                    var error_el = YAHOO.util.Dom.get(error_element_id);

                    // if the id_error div/span does not exist, show an error
                    if (!error_el) {
                        _trace();
                        _log("Error in CPANEL.validate.add: could not find element '" + error_element_id + "' in the DOM");
                        return;
                    }

                    // make sure the error element is 16x16
                    if (!opts || opts && !opts.no_width_height) {
                        YAHOO.util.Dom.setStyle(error_el, "width", "16px");
                        YAHOO.util.Dom.setStyle(error_el, "height", "16px");
                    }

                    // if the error element is an image make it transparent
                    if (error_el.tagName.toLowerCase() === "img") {
                        error_el.src = CPANEL.icons.transparent_src;
                        YAHOO.util.Dom.setStyle(error_el, "vertical-align", "middle");
                    }

                    // check that the error message is either a string or a function
                    if (typeof (msg) !== "string" && typeof (msg) !== "function") {
                        _log("Error in CPANEL.validate.add: msg must be either a string or a function");
                        return;
                    }

                    // if they have not specified a conditional function, create one that evaluates to true (ie: their validator will always execute)
                    if (!conditional_func) {
                        conditional_func = function() {
                            return true;
                        };
                    } else if (typeof (conditional_func) === "string") {

                        // if the conditional function is a string assume it is a radio or checkbox
                        // TODO: add support for <select><option> elements

                        var conditional_el = YAHOO.util.Dom.get(conditional_func);
                        if (!conditional_el) {
                            _log("Error in CPANEL.validate.add: could not find element '" + conditional_func + "' in the DOM.");
                            return;
                        }

                        var attribute_type = conditional_el.getAttribute("type");
                        if (attribute_type === "radio" || attribute_type === "checkbox") {
                            conditional_func = function() {
                                return conditional_el.checked;
                            };
                        } else {
                            _log("Error in CPANEL.validate.add: conditional function argument '" + conditional_el.id + "'must be a DOM element of type \"radio\" or \"checkbox\"");
                            return;
                        }
                    }

                    // if func is a string convert it to a function
                    if (typeof (func) === "string") {

                        // if func is a string assume it's a method of CPANEL.validate
                        // example syntax: validator_object.add("my_element", "url('http://yahoo.com')", "that is not a valid url");
                        func = "CPANEL.validate." + func;

                        // TODO: check that the string is a valid CPANEL.validate function

                        // if the string does not contain any parenthesis assume it is a method that calls the input of the object passed into it
                        // example syntax: validator_object.add("my_element", "url", "that is not a valid url");
                        if (func.match(new RegExp(/[()]/)) === null) {
                            func = func + "(%input%)";
                        }

                        // replace %input% with the element value
                        // example syntax:  validator_object.add("my_element", "if_not_empty(%input%, CPANEL.validate.url)", "that is not a valid url");
                        //                  validator_object.add("my_element", "min_length(%input%, 5)", "input must be at least 5 characters long");
                        func = func.replace(/(\$input\$)|(%input%)/i, "YAHOO.util.Dom.get(\"" + el.id + "\").value");

                        // convert func to a function literal
                        // NOTE: use of eval() here; please modify this code with caution
                        try {

                            // NOTE: This has to be left in for legacy. Ick.
                            /* jshint evil:true */
                            eval("func = function() { return " + func + "; };");
                        } catch (e) {
                            _log("Error in CPANEL.validate.add: Error eval()ing your function argument");
                            return;
                        }
                    }

                    // add the validator to the array
                    this.validators.push({
                        el: el,
                        func: func,
                        msg: msg,
                        conditional_func: conditional_func,
                        submit_only: opts && opts.submit_only,
                        unique_id: opts && opts.unique_id,
                    });
                };

                /**
                    Attaches the validator functions to their respective DOM elements (ie: adds event handlers to the input fields).
                    @method attach
                */
                this.attach = function() {

                    // get a list of all unique elements
                    var elements = _get_unique_elements();

                    // loop through the elements and add event handlers and error panels
                    for (var i = 0; i < elements.length; i++) {

                        // grab the validate functions and error messages for this element
                        var element = elements[i];

                        // add the event handler if necessary
                        // if type attribute is null get the tagName to test for textarea
                        var attribute_type = element.type || element.tagName;

                        // if the input has an internal cursor:
                        if (/password|text|textarea|number/i.test(attribute_type)) {
                            if (CPANEL.dom.has_oninput) {
                                EVENT.on(element, "input", verify_element, {
                                    el: element,
                                });
                            } else { // IE9 and earlier
                                EVENT.on(element, "keyup", verify_element, {
                                    el: element,
                                });
                                EVENT.on(element, "change", verify_element, {
                                    el: element,
                                });
                                EVENT.on(element, "paste", delayed_verify_element, {
                                    el: element,
                                });
                            }

                        // Input file and select require the change event
                        } else if (/file|select/i.test(attribute_type)) {
                            EVENT.on(element, "change", verify_element, {
                                el: element,
                            });
                        }

                        // add the error panel
                        create_error_panel(element);
                    }
                };

                /**
                    Removes all validators from their respective DOM elements (ie: removes the event handlers).<br />
                    WARNING: this will remove ALL event handlers for these elements; this is a limitation of YAHOO.util.Event
                    @method detach
                */
                this.detach = function() {

                    // get a list of all unique elements
                    var elements = _get_unique_elements();

                    // loop through the elements remove the event handlers
                    for (var i = 0; i < elements.length; i++) {
                        if (CPANEL.dom.has_oninput) {
                            EVENT.purgeElement(elements[i], false, "input");
                        } else { // IE8
                            EVENT.purgeElement(elements[i], false, "keyup");
                            EVENT.purgeElement(elements[i], false, "change");
                            EVENT.purgeElement(elements[i], false, "paste");
                        }
                    }
                    this.clear_messages();
                };

                /**
                    Returns the current validation state for all the validators in the array.
                    @method is_valid
                    @return {boolean} returns true if all the validator functions return true
                */
                this.is_valid = function() {
                    for (var i = 0; i < this.validators.length; i++) {
                        if (this.validators[i].el.disabled) {
                            continue;
                        }
                        if (this.validators[i].conditional_func(this.validators[i].el, this.validators[i])) {
                            if (!this.validators[i].func(this.validators[i].el, this.validators[i])) {
                                return false;
                            }
                        }
                    }

                    return true;
                };

                /**
                    Returns an object of all the error messages for currently invalid input.<br />
                    Useful for modal error boxes.
                    @method error_messages
                    @return {object} an object of error messages in the format: <code>&#123; title:"title", errors:["error message 1","error message 2"] &#125;</code><br />false if the the input is valid
                */
                this.error_messages = function() {

                    // loop through the validators and get all the error messages
                    var error_messages = [];
                    for (var i = 0; i < this.validators.length; i++) {
                        if (this.validators[i].conditional_func(this.validators[i].el, this.validators[i])) {
                            if (!this.validators[i].func(this.validators[i].el, this.validators[i])) {
                                error_messages.push(_process_error_message(this.validators[i].msg, this.validators[i].el));
                            }
                        }
                    }

                    // no error messages, return false
                    if (error_messages.length === 0) {
                        return false;
                    }

                    return {
                        title: this.title,
                        errors: error_messages,
                    };
                };

                /**
                    Clears all validation status messages.
                    @method clear_messages
                */
                this.clear_messages = function() {
                    for (var i = 0; i < this.validators.length; i++) {
                        var error_element = YAHOO.util.Dom.get(this.validators[i].el.id + "_error");

                        if (!error_element) {
                            continue;
                        }

                        if (error_element.tagName.toLowerCase() === "img") {
                            error_element.src = CPANEL.icons.transparent_src;
                        } else {
                            error_element.innerHTML = "";
                        }
                    }
                    hide_all_panels();
                };

                /**
                    Shows validation success or errors on the page by updating the DOM.
                    Useful when initially loading a page or for showing failure on a form submit button.
                    @method verify
                */
                this.verify = function(evt) {

                    // get a list of all unique elements
                    var elements = _get_unique_elements();

                    // loop through the elements and verify each one
                    for (var i = 0; i < elements.length; i++) {
                        verify_element(null, {
                            el: elements[i],
                            "event": evt,
                        });
                    }
                };

                /**
                    Same as verify(), but this sends in a mock submit "event" that
                    will trigger display of submit-only validation messages.
                */
                this.verify_for_submit = function() {
                    return this.verify({
                        type: "submit",
                    });
                };

                /*
                    PRIVATE MEMBERS
                    Note: Yuidoc ignores private member documentation, but I included it in the same format for consistency.
                */

                /**
                    Use "that" if you need to reference "this" object.  See http://www.crockford.com/javascript/private.html for more information.
                    @property that
                    @private
                */
                var that = this;

                // private object to hold the error panels
                var panels = {};

                /**
                    Creates an error YUI panel.
                    @method create_error_panel
                    @param {DOM element} The input element the error panel is for.
                    @private
                */
                var create_error_panel = function(element) {

                    // TODO: need to check to make sure we're not creating a new panel on top of one that already exists

                    // This was originally written to use Panel, but Overlay is the better choice.
                    // Unfortunate to put "Overlay" objects into the "panels" container,
                    // and also for them to have a class of "validation_error_panel",
                    // but it's the best way forward for now.
                    var overlay_config = {
                        visible: false,
                        zindex: 1000,
                        context: [element.id + "_error"].concat(CPANEL.validate.get_page_overlay_context_arguments()),
                    };
                    DOM.addClass(element.id + "_error", "cjt_validation_error");
                    panels[element.id] = new YAHOO.widget.Overlay(element.id + "_error_panel", overlay_config);
                    panels[element.id].setBody("");

                    // Done to make sure the validations scroll with content container in whm.
                    // Currently this ID is not being used in either cPanel and/or Webmail.
                    var contentContainer = document.getElementById("contentContainer");
                    if (contentContainer) {
                        panels[element.id].render(contentContainer);
                    } else {
                        panels[element.id].render(document.body);
                    }


                    // add the "validation_error_panel" style class to the overlay
                    YAHOO.util.Dom.addClass(element.id + "_error_panel", "validation_error_panel");
                };


                /**
                 *   Clear visuals for one validator
                 *
                 *   @method clear_one_message
                 *   @param element {String | DOMNode} The element whose validation indicators we need to clear.
                 */
                var clear_one_message = function(element) {
                    var error_element = DOM.get(element.id + "_error");
                    var no_panel = DOM.hasClass(error_element, "no_panel");

                    if (error_element.tagName.toLowerCase() === "img") {
                        error_element.src = "data:image/png,";

                        if (no_panel) {
                            error_element.title = "";
                        }
                    } else {
                        error_element.innerHTML = "";
                    }

                    if (panels[element.id]) {
                        panels[element.id].hide();
                    }
                };


                var delayed_verify_element = function(e, o) {
                    setTimeout(verify_element.bind(this, e, o), 5);
                };

                /**
                    Checks an element's input against a set of functions
                    @method verify_element
                    @param {object} o object handler
                    @param {object} params object with the element to be checked, the functions to check it against, and the error messages to be displayed on failure
                    @private
                */
                var verify_element = function(e, o) {
                    if (o.el.disabled) {
                        return;
                    }

                    var submit_only_function_failed_outside_submit;

                    var this_is_a_submit;
                    if (o.event) {
                        var evt = o.event;

                        // This doesn't really fire because we don't actually attach to the "submit" event,
                        // but it's a good idea to have this listener anyway.
                        this_is_a_submit = (evt.type === "submit");

                        // We actually attach to the submit button's "click" event so that
                        // we can prevent the form's onsubmit from firing if the validation fails.
                        // That means we have to be a bit smarter about detecting whether we're in
                        // a submission, though.
                        if (!this_is_a_submit && (evt.type === "click")) {
                            var clickee = EVENT.getTarget(evt);
                            var tag_name = clickee.tagName.toLowerCase();
                            this_is_a_submit = (clickee.type === "submit") && ((tag_name === "button") || (tag_name === "input"));
                        }
                    }

                    // grab all the error messages from functions that are not valid
                    var error_messages = [];
                    var ids = [];
                    for (var i = 0; i < that.validators.length; i++) {
                        var validation_unit = that.validators[i];
                        if (validation_unit.el.id !== o.el.id) {
                            continue;
                        }

                        if (validation_unit.conditional_func(o.el, that.validators[i])) {
                            if (!validation_unit.func(o.el, that.validators[i])) {
                                if (!this_is_a_submit && validation_unit.submit_only) {
                                    submit_only_function_failed_outside_submit = true;
                                } else {
                                    error_messages.push(that.validators[i].msg);
                                    ids.push(that.validators[i].unique_id);
                                }
                            }
                        }
                    }

                    // show success or error
                    if (error_messages.length === 0) {

                        // Validation *did* fail; we just don't want to tell the user
                        // about it since we aren't in a form submission.
                        // ex.: We require a field "A" in a form to have a value.
                        // Field "A"'s validity depends on the value of field "B",
                        // so every time we change field "B"'s value we also need to
                        // fire field "A"'s validator. BUT, we don't want to complain
                        // about field "A" not having a value in this case since we can
                        // assume that the user is about to fill that field out. Only
                        // on page submission do we actually show the validation message
                        // that says, "you must fill this out".
                        if (submit_only_function_failed_outside_submit) {
                            clear_one_message(o.el);
                            that.validateFailure.fire({
                                is_submit_only_failure: true,
                            });
                        } else {
                            show_success(o.el);
                            that.validateSuccess.fire();
                        }
                    } else {
                        show_errors(o.el, error_messages, ids);
                        that.validateFailure.fire({
                            is_submit_only_failure: false,
                        });
                    }
                };

                /**
                    Show a successful input validation
                    @method show_success
                    @param {DOM element} element input element
                    @private
                */
                var show_success = function(element) {
                    var error_element = YAHOO.util.Dom.get(element.id + "_error");
                    if (YAHOO.util.Dom.getStyle(error_element, "display") !== "none") {

                        // hide the panel if it is showing
                        panels[element.id].hide();

                        // show the success icon
                        if (error_element.tagName.toLowerCase() === "img") {
                            error_element.src = CPANEL.icons.success_src;
                        } else {
                            error_element.innerHTML = CPANEL.icons.success;
                        }

                        error_element.title = "";

                        // purge the element of event handlers that pop up panels
                        YAHOO.util.Event.purgeElement(error_element, false);
                    }
                };

                // show input validation errors
                var show_errors = function(element, messages, ids) {
                    messages = messages.map(function(cur_msg) {
                        return _process_error_message(cur_msg, element);
                    });

                    // get the error element
                    var error_element = YAHOO.util.Dom.get(element.id + "_error");

                    // if the error element is hidden do not show anything
                    if (YAHOO.util.Dom.getStyle(error_element, "display") === "none") {
                        return;
                    }

                    var no_panel = YAHOO.util.Dom.hasClass(error_element, "no_panel");
                    var img_title;
                    if (no_panel) {
                        var dummy_span = document.createElement("span");
                        img_title = [];
                        for (var m = 0; m < messages.length; m++) {
                            dummy_span.innerHTML = messages[m];
                            img_title.push(dummy_span.textContent || dummy_span.innerText);
                        }
                        img_title = img_title.join("\n");
                    }

                    // show the error image
                    if (error_element.tagName.toLowerCase() === "img") {
                        error_element.src = CPANEL.icons.error_src;
                        if (no_panel) {
                            error_element.title = img_title;
                        }
                    } else {
                        error_element.innerHTML = CPANEL.icons.error;
                        if (no_panel) {
                            error_element.getElementsByTagName("img")[0].title = img_title;
                        }
                    }

                    // do not show the panel if the "no_panel" class exists
                    if (no_panel) {
                        return;
                    }

                    // add the validation errors to the panel
                    var panel_body = '<div class="validation_errors_div">';
                    panel_body += '<ul class="validation_errors_ul">';
                    for (var i = 0; i < messages.length; i++) {
                        var id = (ids[i] ? ' id="' + ids[i] + '"' : "" );
                        panel_body += '<li class="validation_errors_li"' + id + ">" + _process_error_message(messages[i], element) + "</li>";
                    }
                    panel_body += "</ul></div>";

                    // display the messages directly in the error element if the "show_inline" class exists
                    var show_inline = YAHOO.util.Dom.hasClass(error_element, "show_inline");
                    if (show_inline) {
                        error_element.innerHTML = panel_body;
                    } else {
                        panels[element.id].setBody(panel_body);
                        panels[element.id].show();
                    }

                };

                // hide all error panels
                var hide_all_panels = this.hide_all_panels = function() {
                    for (var i in panels) {
                        panels[i].hide();
                    }
                };

                // returns an array of unique elements
                var _get_unique_elements = function() {
                    return that.validators.map(function(v) {
                        return v.el;
                    }).unique();
                };

                // processes an error message
                var _process_error_message = function(msg, element) {

                    // msg is a string
                    if (typeof (msg) === "string") {
                        return msg;
                    }

                    // msg is a function
                    return msg(element);
                };

            }, // end validator object

            /**
                Shows a modal error box.<br />
                ProTip: Use the show_errors method of your validator object with this function.
                @method show_modal_error
                @for CPANEL.validate
                @param {object} messages an object of type: <code>&#123; title:"title", errors:["error message 1","error message 2"] &#125;</code> (can also be an array of this object type for when you have multiple validators on the same page)
            */
            show_modal_error: function(messages) {

                // convert messages to an array
                var temp = [];
                if (YAHOO.lang.isArray(messages) === false) {
                    temp.push(messages);
                    messages = temp;
                }

                // remove the panel if it already exists
                if (YAHOO.util.Dom.inDocument("validation_errors_modal_box") === true) {
                    var remove_me = YAHOO.util.Dom.get("validation_errors_modal_box");
                    remove_me.parentNode.removeChild(remove_me);
                }

                // create the panel
                var panel_options = {
                    width: "350px",
                    fixedcenter: true,
                    close: true,
                    draggable: false,
                    zindex: 1000,
                    modal: true,
                    visible: false,
                };
                var panel = new YAHOO.widget.Panel("validation_errors_modal_box", panel_options);

                // header
                var header = '<div class="lt"></div>';
                header += "<span>" + LOCALE.maketext("Validation Errors") + "</span>";
                header += '<div class="rt"></div>';
                panel.setHeader(header);

                // body
                var body = "";
                for (var i = 0; i < messages.length; i++) {
                    body += '<span class="validation_errors_modal_box_title">' + messages[i].title + "</span>";
                    body += '<ul class="validation_errors_modal_box_ul">';
                    var these_errors;
                    if (messages[i].errors instanceof Array) {
                        these_errors = messages[i].errors;
                    } else {
                        these_errors = [messages[i].errors];
                    }
                    for (var j = 0; j < these_errors.length; j++) {
                        body += '<li class="validation_errors_modal_box_li">' + these_errors[j] + "</li>";
                    }
                    body += "</ul>";
                }
                panel.setBody(body);

                // footer
                var footer = '<div class="lb"></div>' +
                    '<div class="validation_errors_modal_box_actions">' +
                    '<input id="validation_errors_modal_panel_close_button" type="button" class="input-button btn-primary" value="' + LOCALE.maketext("Close") + '" />' +
                    "</actions>" +
                    '<div class="rb"></div>';

                panel.setFooter(footer);

                // add the event handler and put the focus on the close button after the panel renders
                var after_show = function() {
                    YAHOO.util.Event.on("validation_errors_modal_panel_close_button", "click", function() {
                        panel.hide();
                    });
                    YAHOO.util.Dom.get("validation_errors_modal_panel_close_button").focus();
                };
                panel.showEvent.subscribe(after_show);

                // show the panel
                panel.render(document.body);
                panel.show();
            },

            /**
                Validates a form submission against validator objects.
                If the validator object(s) validate to true the form gets submitted, else the form submission is halted and a modal error box with the validation errors is shown.
                This method attaches an "onclick" event handler to the form submission element.
                @method attach_to_form
                @param {DOM element} el the id of the form submit button
                @param {object} validators a single validator object, an array of validator objects, or an object of validator objects
                // optional: If either opts.success_callback or opts is a function,
                // that function is executed upon successful validation.
            */
            attach_to_form: function(el, validators, opts) {
                var success_callback;
                if (opts) {
                    if (typeof opts === "function") {
                        success_callback = opts;
                    } else {
                        success_callback = opts.success_callback;
                    }
                } else {
                    opts = {};
                }

                var typeof_validator = function(obj) {
                    if (!obj ||
                        typeof (obj.add) !== "function" ||
                        typeof (obj.attach) !== "function" ||
                        typeof (obj.title) !== "string") {
                        return false;
                    }
                    return true;
                };

                // convert a single instance, array, or object of validators to an array
                var temp = [];
                if (typeof_validator(validators)) {
                    temp.push(validators);
                } else {
                    for (var i in validators) {
                        if (!typeof_validator(validators[i])) {
                            continue;
                        }
                        temp.push(validators[i]);
                    }
                }
                validators = temp;

                // check to see if the validator functions are valid
                CPANEL.validate.form_checkers[el] = function(event, checkonly) {
                    var messages = [],
                        topYCoord,
                        topElId;
                    var good_data = true;

                    // loop through the validators
                    for (var i = 0; i < validators.length; i++) {
                        validators[i].verify(event);
                        if (!validators[i].is_valid()) {
                            good_data = false;
                            messages.push(validators[i].error_messages());

                            var curElId;

                            for (let validator of validators[i].validators) {
                                curElId = validator.el.id;
                                let curElErrorPanel = document.getElementById(`${curElId}_error_panel`);
                                if (curElErrorPanel && curElErrorPanel.style.visibility === "visible") {
                                    curElId = `${curElId}_error`;
                                    break;
                                }
                            }

                            // An input that is hidden won't return a Y value so we have to go based on a known field.
                            var yPos = DOM.getY(curElId);
                            if (!topYCoord || yPos < topYCoord) {
                                topYCoord = yPos;
                                topElId = curElId;
                            }
                        }
                    }

                    // if the validators are not true, stop the default event and show the modal error panel
                    // also the optional callback function does not get called
                    if (good_data === false) {
                        if (event) {
                            EVENT.preventDefault(event);
                        }

                        if (!CPANEL.validate.hide_validation_summary ) {
                            if ( !opts.no_panel ) {
                                CPANEL.validate.show_modal_error(messages);
                            }
                        }

                        scrollToError:
                        if (!opts.no_animation && CPANEL.animate) {
                            let firstErrorInFormGroup = document.querySelector(`.form-group #${topElId}`);
                            let firstVisibleErrorPanel = document.querySelector("*[id$='_error_panel'][style*='visibility: visible']");

                            // Some pages don't have their error messages visually tucked within the form they apply to.
                            // For those situations, we'll just grab the actual message and scroll to it instead of the section holding it.
                            let firstErrorElement = firstErrorInFormGroup ? firstErrorInFormGroup.closest(".form-group") : firstVisibleErrorPanel;

                            // If we can't find the error, there's no need to run the rest of this block, so we break out.
                            if (!firstErrorElement) {
                                break scrollToError;
                            }

                            let viewportWidth = document.documentElement.clientWidth;
                            let pageHeader = document.querySelector("header");
                            let heightOfPageHeader = pageHeader.getBoundingClientRect().height;
                            let extraSpacing = 10;
                            let errorElVerticalDisplacement = firstErrorElement.getBoundingClientRect().top;
                            let errorElHorizontalDisplacement = firstErrorElement.getBoundingClientRect().right;
                            let verticalDisplacement = errorElVerticalDisplacement - heightOfPageHeader - extraSpacing;
                            let horizontalDisplacement =  errorElHorizontalDisplacement - viewportWidth;

                            // Using Math.abs on the horizontal displacement so we never scroll left.
                            window.scrollBy({
                                top: verticalDisplacement,
                                left: Math.abs(horizontalDisplacement),
                                behavior: "smooth",
                            });
                        }

                        return false;
                    }

                    // else the form submission event gets called inherently

                    if (!checkonly && success_callback) {
                        success_callback(event);
                    }

                    return true;
                };

                // NOTE: This fires *before* the form's submit event, and will fire
                // even if the form submits via pressing ENTER.
                // It's important that we attach to this event, NOT form "submit",
                // because if we attach to form "submit" then we can't prevent further
                // action on the submit event. Attaching here allows us to prevent
                // inline "onsubmit" events.
                YAHOO.util.Event.on(el, "click", CPANEL.validate.form_checkers[el]);
            },

            // create a validator object from a validation definition
            create: function(id, name, definition) {

                // check the id
                var el = YAHOO.util.Dom.get(id);
                if (!el) {
                    _log("Error in CPANEL.validate.create: id '" + el.id + "' does not exist in the DOM.");
                    return;
                }

                // check the definition
                if (!CPANEL.validation_definitions[definition]) {
                    _log("Error in CPANEL.validate.create: Validation definition '" + definition + "' does not exist.");
                    return;
                }

                var atoms = CPANEL.validate.util.get_atoms_from_definition(definition);
                var func = CPANEL.validate.util.create_function_from_atoms(atoms, el);
                var msg = CPANEL.validate.util.create_msg_from_atoms(atoms);

                var validator = new CPANEL.validate.validator(name);
                validator.add(id, func, msg);
                validator.attach();
                return validator;
            },

            /**
             * Validates that the text does not start with or end with a period and
             * does not contain two or more consecutive periods.
             * @param  {string} text
             * @return {boolean}     returns true if <code>text</code> is free of the
             * unsafe periods, and false if it starts with a period, or ends with a period
             * or has any two consecutive periods.
             */
            no_unsafe_periods: function(text) {

                // if the text has '.' as the first or last character then it's not valid
                if (text.charAt(0) === "." || text.charAt(text.length - 1) === ".") {
                    return false;
                }

                // if the texting contains '..' then it's not valid
                if (/\.\./.test(text) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates the local part of an email address: <u>local</u>@domain.tld<br />
                see: <a href="http://en.wikipedia.org/wiki/E-mail_address#RFC_specification">RFC spec</a>.
                @note Preserved for legacy x3 support. Use the new email_username, ftp_username and
                webmail_username in all new code.
                @method local_part_email
                @param {string} str The local part of an email address.
                @param {spec} str (optional) either "cpanel" or "rfc", defaults to rfc
                @param {Boolean} charCheckOnly (optional) When true, the validator ony checks the character regex
                @return {boolean} returns true if <code>str</code> fits the RFC spec
            */
            local_part_email: function(str, spec, charCheckOnly) {
                return _validate_local_part(str, spec, charCheckOnly);
            },

            /**
                Validates the local part of an email address: <u>local</u>@domain.tld<br />
                see: <a href="http://en.wikipedia.org/wiki/E-mail_address#RFC_specification">RFC spec</a>.
                @method email_username
                @param {string} str The local part of an email address.
                @param {spec} str (optional) either "cpanel" or "rfc", defaults to rfc
                @param  {Boolean} charCheckOnly (optional) When true, the validator ony checks the character regex
                @return {boolean} returns true if <code>str</code> fits the RFC spec
            */
            email_username: function(str, spec, charCheckOnly) {
                return _validate_local_part(str, "cpanel", charCheckOnly);
            },

            /**
                Validates a webmail username.
                @method ftp_username
                @param {string} str The username requested.
                @return {boolean} returns true if <code>str</code> fits the requested spec, false otherwise
            */
            ftp_username: function(str) {
                return _validate_local_part(str, "cpanel");
            },

            /**
                Validates a webdisk username.
                @method webdisk_username
                @param {string} str The username requested.
                @return {boolean} returns true if <code>str</code> fits the requested spec, false otherwise
            */
            webdisk_username: function(str) {
                return _validate_local_part(str, "cpanel");
            },

            /**
                This function validates a hostname: http://<u>cpanel.net</u>
                @method host
                @param {string} str A hostname.
                @return {boolean} returns true if <code>str</code> is a valid hostname
            */
            host: function(str) {
                var chunks = str.split(".");
                if (chunks.length < 2) {
                    return false;
                }

                for (var i = 0; i < chunks.length - 1; i++) {
                    if (!CPANEL.validate.domain(chunks[i])) {
                        return false;
                    }
                }

                // last chunk must be a tld
                if (!CPANEL.validate.tld("." + chunks[chunks.length - 1])) {
                    return false;
                }

                return true;
            },

            /**
                This function validates an email address to RFC spec: <u>local@domain.tld</u>
                @method email
                @param {string} str An email address.
                @return {boolean} returns true if <code>str</code> is a valid email address
            */
            email: function(str) {

                // split on the @ symbol
                var groups = str.split("@");

                // must be split into two at this point
                if (groups.length !== 2) {
                    return false;
                }

                // validate the local part
                if (!_validate_local_part(groups[0], "rfc")) {
                    return false;
                }

                // validate the rest
                return CPANEL.validate.fqdn(groups[1]);
            },

            /**
                This function validates an email address to cPanel spec: <u>local@domain.tld</u>
                @method cpanel_email
                @param {string} str An email address.
                @return {boolean} returns true if <code>str</code> is a valid cpanel email address
            */
            cpanel_email: function(str) {

                // split on the @ symbol
                var groups = str.split("@");

                // must be split into two at this point
                if (groups.length !== 2) {
                    return false;
                }

                // validate the local part
                if (!_validate_local_part(groups[0], "cpanel")) {
                    return false;
                }

                // validate the rest
                return CPANEL.validate.fqdn(groups[1]);
            },

            /**
            This function validates an image extension: 'gif', 'jpg', 'jpeg', 'png'
            @method external_check_image_extension
            @param {string} str An image extension.
            @return {boolean} returns true if <code>str</code> is a valid image extension
            */
            external_check_image_extension: function(str, fname) {

                // empty string is ok
                if (str === "") {
                    return true;
                }

                // make sure there is an extension
                if (!(/[^.]\.[^.]+$/.test(str))) {
                    return false;
                }

                var given_extension = str.split(".").pop();

                var allowed_extensions = ["gif", "jpg", "jpeg", "png"];

                return (allowed_extensions.indexOf(given_extension.toLowerCase()) !== -1);
            },

            /**
                This function validates a URL: <u>http://cpanel.net</u><br />
                The URL must include <code>http://</code> or <code>https://</code> at the beginning.
                @method url
                @param {string} str a URL
                @return {boolean} returns true if <code>str</code> is a valid URL
            */
            url: function(str) {

                // must contain 'http://' or 'https://' at the start
                if (str.substring(0, 7) !== "http://" && str.substring(0, 8) !== "https://") {
                    return false;
                }

                // grab the domain and tlds
                var front_slashes = str.search(/:\/\//);
                if (front_slashes === -1) {
                    return false;
                }
                str = str.substring(front_slashes + 3);

                // see if there is something after the last tld (path)
                var back_slash = str.search(/\//);
                if (back_slash === -1) {
                    back_slash = str.length;
                }
                var domain_and_tld = str.substring(0, back_slash);

                return CPANEL.validate.fqdn(domain_and_tld);
            },

            fqdn: function(str) {

                // check the domain and tlds
                var groups = str.split(".");

                // must have at least one domain and tld
                if (groups.length < 2) {
                    return false;
                }

                // check each group
                for (var i = 0; i < groups.length; i++) {

                    // the first entry must be a domain
                    if (i === 0) {
                        if (!CPANEL.validate.domain(groups[i])) {
                            return false;
                        }
                    }

                    // the last entry must be a tld
                    if (i === groups.length - 1) {
                        if (!CPANEL.validate.tld("." + groups[i])) {
                            return false;
                        }
                    }

                    // everything else in between must be either a domain or a tld
                    if (!CPANEL.validate.tld("." + groups[i]) && !CPANEL.validate.domain(groups[i])) {
                        return false;
                    }
                }

                return true;
            },

            /**
                Validates a top level domain (TLD): .com, .net, .org, .co.uk, etc<br />
                This function does not check against a list of TLDs.  Instead it makes sure that the TLD is formatted correctly.<br />
                TLD must begin with a period (.)
                @method tld
                @param {string} str a TLD
                @return {boolean} returns true if <code>str</code> is a valid TLD
            */
            tld: function(str) {

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z0-9-.]");
                if (pattern.test(str) === true) {
                    return false;
                }

                // string must have '.' as a first character and neither '.' nor '-' as a last character
                if (str.charAt(0) !== "." || /[.-]$/.test(str)) {
                    return false;
                }

                // string cannot contain any of: ..  .-  -.  ---
                if (/\.[.-]/.test(str) || /-\./.test(str) || /---/.test(str)) {
                    return false;
                }

                return true;
            },

            /**
                Validates a domain name: http://<u>cpanel</u>.net
                @method domain
                @param {string} str a domain
                @return {boolean} returns true if <code>str</code> is a valid domain
            */
            domain: function(str) {

                // string must contain only these characters
                var pattern = new RegExp("[^_a-zA-Z0-9-]");
                if (pattern.test(str) === true) {
                    return false;
                }

                // We're allowing underscores but only as the first character
                if (/_/.test(str.substr(1))) {
                    return false;
                }

                // string cannot have '-' as a first or last character
                if (str.charAt(0) === "-" || str.charAt(str.length - 1) === "-") {
                    return false;
                }

                // domain name cannot be longer than 63 characters
                if (str.length === 0 || str.length > 63) {
                    return false;
                }

                return true;
            },

            /**
                Validates a subdomain: http://<u>foo</u>.cpanel.net
                @method subdomain
                @param {string} str a subdomain
                @return {boolean} returns true if <code>str</code> is a valid subdomain
            */
            subdomain: function(str) {

                // string must contain only these characters
                var pattern = new RegExp("[^_a-zA-Z0-9-.]");
                if (pattern.test(str) === true) {
                    return false;
                }

                // We're allowing underscores but only as the first character
                if (/_/.test(str.substr(1))) {
                    return false;
                }

                // last character must be alphanumeric
                if (!CPANEL.validate.alphanumeric(str.charAt(str.length - 1))) {
                    return false;
                }

                // subdomain cannot be longer than 63 characters
                if (str.length === 0 || str.length > 63) {
                    return false;
                }

                // string cannot contain '..'
                pattern = new RegExp(/\.\./);
                if (pattern.test(str) === true) {
                    return false;
                }

                return true;
            },

            /**
                Validates an ISO 3166-1 alpha-2 country code: US, GB, CA, DE...
                @method country_code
                @param {string} str a country code in upper case
                @return {boolean} returns true if <code>str</code> is a valid country code
            */
            country_code: function(str) {
                var codes = ["AD", "AE", "AF", "AG", "AI", "AL", "AM", "AO", "AQ", "AR",
                    "AS", "AT", "AU", "AW", "AX", "AZ", "BA", "BB", "BD", "BE", "BF",
                    "BG", "BH", "BI", "BJ", "BL", "BM", "BN", "BO", "BQ", "BR", "BS",
                    "BT", "BV", "BW", "BY", "BZ", "CA", "CC", "CD", "CF", "CG", "CH",
                    "CI", "CK", "CL", "CM", "CN", "CO", "CR", "CU", "CV", "CW", "CX",
                    "CY", "CZ", "DE", "DJ", "DK", "DM", "DO", "DZ", "EC", "EE", "EG",
                    "EH", "ER", "ES", "ET", "FI", "FJ", "FK", "FM", "FO", "FR", "GA",
                    "GB", "GD", "GE", "GF", "GG", "GH", "GI", "GL", "GM", "GN", "GP",
                    "GQ", "GR", "GS", "GT", "GU", "GW", "GY", "HK", "HM", "HN", "HR",
                    "HT", "HU", "ID", "IE", "IL", "IM", "IN", "IO", "IQ", "IR", "IS",
                    "IT", "JE", "JM", "JO", "JP", "KE", "KG", "KH", "KI", "KM", "KN",
                    "KP", "KR", "KW", "KY", "KZ", "LA", "LB", "LC", "LI", "LK", "LR",
                    "LS", "LT", "LU", "LV", "LY", "MA", "MC", "MD", "ME", "MF", "MG",
                    "MH", "MK", "ML", "MM", "MN", "MO", "MP", "MQ", "MR", "MS", "MT",
                    "MU", "MV", "MW", "MX", "MY", "MZ", "NA", "NC", "NE", "NF", "NG",
                    "NI", "NL", "NO", "NP", "NR", "NU", "NZ", "OM", "PA", "PE", "PF",
                    "PG", "PH", "PK", "PL", "PM", "PN", "PR", "PS", "PT", "PW", "PY",
                    "QA", "RE", "RO", "RS", "RU", "RW", "SA", "SB", "SC", "SD", "SE",
                    "SG", "SH", "SI", "SJ", "SK", "SL", "SM", "SN", "SO", "SR", "SS",
                    "ST", "SV", "SX", "SY", "SZ", "TC", "TD", "TF", "TG", "TH", "TJ",
                    "TK", "TL", "TM", "TN", "TO", "TR", "TT", "TV", "TW", "TZ", "UA",
                    "UG", "UM", "US", "UY", "UZ", "VA", "VC", "VE", "VG", "VI", "VN",
                    "VU", "WF", "WS", "YE", "YT", "ZA", "ZM", "ZW",
                ];

                return codes.indexOf(str) > -1;
            },

            /**
                Validates alpha characters: a-z A-Z
                @method alpha
                @param {string} str some characters
                @return {boolean} returns true if <code>str</code> contains only alpha characters
            */
            alpha: function(str) {

                // string cannot be empty
                if (str === "") {
                    return false;
                }

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z]");
                if (pattern.test(str) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates alphanumeric characters: a-z A-Z 0-9
                @method alphanumeric
                @param {string} str some characters
                @return {boolean} returns true if <code>str</code> contains only alphanumeric characters
            */
            alphanumeric: function(str) {

                // string cannot be empty
                if (str === "") {
                    return false;
                }

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z0-9]");
                if (pattern.test(str) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates alphanumeric characters: a-z A-Z 0-9, underscore (_) and hyphen (-)
                @method sql_alphanumeric
                @param {string} str some characters
                @return {boolean} returns true if <code>str</code> contains only alphanumeric characters and or underscore
            */
            sql_alphanumeric: function(str) {

                // string cannot be empty
                if (str === "") {
                    return false;
                }

                // string cannot contain a trailing underscore
                if (/_$/.test(str)) {
                    return false;
                }

                // string must contain only these characters
                var pattern = new RegExp("[^a-zA-Z0-9_-]");
                if (pattern.test(str) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a string is a minimum length.
                @method min_length
                @param {string} str the string to check
                @param {integer} length the minimum length of the string
                @return {boolean} returns true if <code>str</code> is longer than or equal to <code>length</code>
            */
            min_length: function(str, length) {
                if (str.length >= length) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a string is not longer than a maximum length.
                @method max_length
                @param {string} str the string to check
                @param {integer} length the maximum length of the string
                @return {boolean} returns true if <code>str</code> is shorter than or equal to <code>length</code>
            */
            max_length: function(str, length) {
                if (str.length <= length) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a string is not shorter the the minimum length and not longer than a maximum length.
                @method length_check
                @param {string} str the string to check
                @param {integer} minLength the minimum length of the string
                @param {integer} maxLength the maximum length of the string
                @return {boolean} returns true if the length of <code>str</code> between <code>minLength</code> and <code>maxLength</code>.
            */
            length_check: function(str, minLength, maxLength) {
                var len = str.length;
                if (len >= minLength && len <= maxLength) {
                    return true;
                }
                return false;
            },

            /**
                Validates that two fields have the same value (useful for password input).
                @method equals
                @param {DOM element} el1 The first element.  Should be of type "text"
                @param {DOM element} el2 The second element.  Should be of type "text"
                @return {boolean} returns true if el1.value equals el2.value
            */
            equals: function(el1, el2) {
                el1 = YAHOO.util.Dom.get(el1);
                el2 = YAHOO.util.Dom.get(el2);
                if (el1.value == el2.value) {
                    return true;
                }
                return false;
            },

            /**
                Validates that two fields do not have the same value (useful for password input).
                @method equals
                @param {DOM element} el1 The first element.  Should be of type "text"
                @param {DOM element} el2 The second element.  Should be of type "text"
                @return {boolean} returns true if el1.value equals el2.value
            */
            not_equals: function(el1, el2) {
                el1 = YAHOO.util.Dom.get(el1);
                el2 = YAHOO.util.Dom.get(el2);
                if (el1.value == el2.value) {
                    return false;
                }
                return true;
            },

            /**
                Validates anything.<br />
                Useful when you want to accept any input from the user, but still give them the same visual feedback they get from input fields that actually get validated.
                @method anything
                @return {boolean} returns true
            */
            anything: function() {
                return true;
            },

            /**
                Validates a field only if it has a value.
                @method if_not_empty
                @param {string | DOM element} value If a DOM element is passed in it should be an input of type="text".  Its value will be grabbed with YAHOO.util.Dom.get(<code>value</code>).value
                @param {function} func The function to check the value against.
                @return {boolean} returns the value of <code>func(value)</code> or true if <code>value</code> is empty
            */
            if_not_empty: function(value, func) {

                // if value is not a string, assume it's an element and grab its value
                if (typeof (value) !== "string") {
                    value = YAHOO.util.Dom.get(value).value;
                }

                if (value !== "") {
                    return func(value);
                }
                return true;
            },

            /**
                Validates that a field contains a positive integer.
                @method positive_integer
                @param {string} value the value to check
                @returns {boolean} returns true if the string is a positive integer
            */
            positive_integer: function(value) {

                // convert value to a string
                value = value + "";

                if (value === "") {
                    return false;
                }
                var pattern = new RegExp("[^0-9]");
                if (pattern.test(value) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a field contains a negative integer.
                @method negative_integer
                @param {string} value the value to check
                @returns {boolean} returns true if the string is a negative integer
            */
            negative_integer: function(value) {

                // convert value to a string
                value = value + "";

                // first character must a minus sign
                if (value.charAt(0) !== "-") {
                    return false;
                }

                // get the rest of the string
                value = value.substr(1);

                var pattern = new RegExp("[^0-9]");
                if (pattern.test(value) === true) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a field contains a integer.
                @method integer
                @param {string} value the value to check
                @returns {boolean} returns true if the string is an integer
            */
            integer: function(value) {
                if (CPANEL.validate.negative_integer(value) ||
                    CPANEL.validate.positive_integer(value)) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a field contains an integer less than a <code>value</code>
                @method max_value
                @param {integer} value the value to check
                @param {integer} max the maximum value
                @returns {boolean} returns true if <code>value</code> is an integer less than <code>max</code>
            */
            max_value: function(value, max) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }

                // convert types to integers for the test
                value = parseInt(value, 10);
                max = parseInt(max, 10);

                if (value > max) {
                    return false;
                }
                return true;
            },

            /**
                Validates that a field contains an integer greater than a <code>value</code>
                @method min_value
                @param {integer} value the value to check
                @param {integer} min the minimum value
                @returns {boolean} returns true if <code>value</code> is an integer greater than <code>max</code>
            */
            min_value: function(value, min) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }
                value = parseInt(value, 10);
                min = parseInt(min, 10);

                if (value < min) {
                    return false;
                }
                return true;
            },

            less_than: function(value, less_than) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }
                value = parseInt(value, 10);
                less_than = parseInt(less_than, 10);

                if (value < less_than) {
                    return true;
                }
                return false;
            },

            greater_than: function(value, greater_than) {
                if (!CPANEL.validate.integer(value)) {
                    return false;
                }
                value = parseInt(value, 10);
                greater_than = parseInt(greater_than, 10);

                if (value > greater_than) {
                    return true;
                }
                return false;
            },

            /**
                Validates that a field does not contain a set of characters.
                @method no_chars
                @param {string} str The string to check against.
                @param {char | Array} chars Either a single character or an array of characters to check against.
                @return {boolean} returns true if none of the characters in <code>chars</code> exist in <code>str</code>.
            */
            no_chars: function(str, chars) {

                // convert chars into an array if it is not
                if (typeof (chars) === "string") {
                    var chars2 = chars.split("");
                    chars = chars2;
                }

                for (var i = 0; i < chars.length; i++) {
                    if (str.indexOf(chars[i]) !== -1) {
                        return false;
                    }
                }

                return true;
            },

            not_string: function(str, notstr) {
                if (str == notstr) {
                    return false;
                }
                return true;
            },

            // directory paths cannot contain the following characters: \ ? % * : | " < >
            dir_path: function(str) {

                // string cannot contain these characters: \ ? % * : | " < >
                var chars = "\\?%*:|\"<>";
                return CPANEL.validate.no_chars(str, chars);
            },

            // user web directories cannot be one of the cpanel reserved directories
            reserved_directory: function(str) {

                // Prevent weird no-op directory-spec to avoid this check
                if (str.indexOf("/") === 0) {
                    str = str.substr(1);
                }
                while (str.indexOf("./") === 0) {
                    str = str.substr(2);
                }

                var DisallowedDirectories = [ "",
                    ".cpanel", ".htpasswds", ".spamassassin", ".ssh", ".trash",
                    "cgi-bin", "etc", "logs", "mail", "perl5", "ssl", "tmp", "var" ];
                if ( DisallowedDirectories.indexOf(str) > -1) {
                    return false;
                }
                return true;
            },

            // quotas must be either a number or "unlimited"
            quota: function(str) {
                if (!CPANEL.validate.positive_integer(str) && (str !== LOCALE.maketext("unlimited"))) {
                    return false;
                }
                return true;
            },

            // MIME type
            mime: function(str) {

                // cannot have spaces
                if (!CPANEL.validate.no_chars(str, " ")) {
                    return false;
                }

                // must contain only one forward slash
                var names = str.split("/");
                if (names.length !== 2) {
                    return false;
                }

                // use same rule as Cpanel::Mime::_is_valid_mime_type
                var pattern = /^[a-zA-Z0-9!#$&.+^_-]+$/;
                for (var i = 0; i < names.length; i++) {
                    if (!names[i] || names[i].length > 127 || !pattern.test(names[i])) {
                        return false;
                    }
                }

                return true;
            },

            // MIME extension
            mime_extension: function(str) {

                // must be a minimum of one alpha-numeric character
                var pattern = new RegExp(/\w/g);
                if (pattern.test(str) === false) {
                    return false;
                }

                // cannot contain special filename characters
                return CPANEL.validate.no_chars(str, "/&?\\");
            },

            apache_handler: function(str) {

                // cannot have spaces
                if (!CPANEL.validate.no_chars(str, " ")) {
                    return false;
                }

                // forward slash /
                var hyphen1 = str.indexOf("-");
                var hyphen2 = str.lastIndexOf("-");
                if (hyphen1 === -1) {
                    return false; // must contain at least one hyphen
                }
                if (hyphen1 === 0 || hyphen2 === (str.length - 1)) {
                    return false; // hyphen cannot be first or last character
                }

                return true;
            },

            // validates an IP address
            ip: function(str) {
                var chunks = str.split(".");
                if (chunks.length !== 4) {
                    return false;
                }

                for (var i = 0; i < chunks.length; i++) {
                    if (!CPANEL.validate.positive_integer(chunks[i])) {
                        return false;
                    }
                    if (chunks[i] > 255) {
                        return false;
                    }
                }

                return true;
            },

            // A port of the logic in Cpanel::Validate::IP
            ipv6: function(str) {
                if (!str) {
                    return false;
                }

                return CPANEL.inet6.isValid(str);
            },

            // returns false if they enter a local IP address, 127.0.0.1, 0.0.0.0
            no_local_ips: function(str) {
                return !(str === "127.0.0.1" || str === "0.0.0.0");
            },

            // validates a filename
            filename: function(str) {
                if (str.indexOf("/") !== -1) {
                    return false; // cannot be a directory path (forward slash)
                }

                if (!CPANEL.validate.dir_path(str)) {
                    return false;
                }
                return true;
            },

            // str==source, allowed is an array of possible endings (returns true on match), case insensitive
            end_of_string: function(str, allowed) {

                // convert "allowed" to an array if it's not otherwise so
                if (!YAHOO.lang.isArray(allowed)) {
                    allowed = [allowed];
                }

                // Compare each element of allowed against str
                for (var i = 0;
                    (i < allowed.length); i++) {
                    if (str.substr(str.length - allowed[i].length).toLowerCase() === allowed[i].toLowerCase()) {
                        return true;
                    }
                }
                return false;
            },

            // must end and begin with an alphanumeric character, many logins require this
            alphanumeric_bookends: function(str) {
                if (str === "") {
                    return true;
                }

                if (!CPANEL.validate.alphanumeric(str.charAt(0))) {
                    return false;
                }

                if (!CPANEL.validate.alphanumeric(str.charAt(str.length - 1))) {
                    return false;
                }

                return true;
            },

            zone_name: function(str) {
                if (str === "") {
                    return false;
                }

                // cut off the trailing period if it's there
                if (str.charAt(str.length - 1) === ".") {
                    str = str.substr(0, str.length - 1);
                }

                var chunks = str.split(".");
                if (chunks.length < 1) {
                    return false;
                }

                for (var i = 0; i < chunks.length; i++) {
                    if ((!CPANEL.validate.domain(chunks[i])) && (chunks[i] !== "*")) {
                        return false;
                    }
                }

                return true;
            },

            // Verify the case-insensitive value is not present in str
            not_present: function(str, value) {
                return !CPANEL.validate.present(str, value);
            },

            // Verify the case-insensitive value is present in str
            present: function(str, value) {

                // Convert everything to lower case for case insensitivity.
                var lower_str = str.toLowerCase();
                var lower_value = value.toLowerCase();
                if (lower_str.indexOf(lower_value) >= 0) {
                    return true;
                }
                return false;
            },

            // Verify that the string is not the domain or one of its subdomains.
            not_in_domain: function(str, domain) {
                return !CPANEL.validate.in_domain(str, domain);
            },

            // Verify that the string is the domain or one of its subdomains.
            in_domain: function(str, domain) {

                // Convert everything to lower case for case insensitivity.
                var lower_str = str.toLowerCase();
                var lower_domain = domain.toLowerCase();
                var domain_pat = lower_domain.replace(/\./g, "\\.");
                if (lower_str === lower_domain) {
                    return true;
                }
                var subdomain_pat = new RegExp("\\." + domain_pat + "$");
                if (subdomain_pat.test(lower_str)) {
                    return true;
                }

                return false;
            },
        };

        CPANEL.validate.validator.prototype = {};
    }
})();
