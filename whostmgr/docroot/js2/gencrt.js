(function() {

    // Imports
    var DOM = YAHOO.util.Dom;
    var EVENT = YAHOO.util.Event;
    var CPVALIDATE = CPANEL.validate;

    // Access page globals
    var PAGE = window["PAGE"];

    var sendEmailValidator;

    /**
     * Contains the list of the validators for the CSR form
     * @type {Array}
     */
    var VALIDATORS = [];

    /**
     * Returns true if the value is defined, false otherwise, allowing
     * validation rules to be defined for optional fields.
     * @method  isOptionalIfUndefined
     * @param  {HTMLElement}  el Element to check.
     * @return {Boolean}    Returns true if the element has a value, false otherwise.
     */

    function isOptionalIfUndefined(el) {
        if (el && el.value !== "") {
            return true;
        }
        return false;
    }

    /**
     * Test the element to see if it contains only ASCII alpha,
     * and spaces and dashes.
     * @method  isAlphaOrWhitespace
     * @param  {[type]}  el [description]
     * @return {Boolean}    [description]
     */

    function isAlphaOrWhitespace(el) {
        if (el && el.value !== "") {
            return (/^[\-A-Za-z ]+$/).test(el.value);
        }
        return false;
    }

    /**
     * Event listener for fields that should trigger warnings on
     * "special" characters.
     *
     * @method warnOnSpecialCharacters
     * @param evt {Event} the YUI Event that tracks the DOM event
     * @param notice {Module} the YUI Module to show/hide for the warning
     */

    function warnOnSpecialCharacters(evt, notice) {
        if (this.value.match(/[^0-9a-zA-Z-,. ]/)) {
            notice.show();
        } else {
            notice.hide();
        }
    }

    /**
     * [registerValidators description]
     * @method registerValidators
     */

    function registerValidators() {

        var i, l;

        var validation = new CPVALIDATE.validator(LOCALE.maketext("Contact Email Address"));
        validation.add("xemail", "min_length(%input%, 1)", LOCALE.maketext("You must enter an email address."));
        validation.add("xemail", "email(%input%)", LOCALE.maketext("The email address provided is not valid. This address must start with the mailbox name, then the “@” sign, then the mail domain name."));
        VALIDATORS.push(validation);

        sendEmailValidator = validation;

        validation = new CPVALIDATE.validator(LOCALE.maketext("Domain"));
        validation.add("domains", CPANEL.Applications.SSL.areValidSSLDomains, LOCALE.maketext("You can only enter valid domains."));
        VALIDATORS.push(validation);

        validation = new CPVALIDATE.validator(LOCALE.maketext("City"));
        validation.add("city", "min_length(%input%, 1)", LOCALE.maketext("You must enter a city."), isOptionalIfUndefined);
        VALIDATORS.push(validation);

        validation = new CPVALIDATE.validator(LOCALE.maketext("State"));
        validation.add("state", "min_length(%input%, 1)", LOCALE.maketext("You must enter a state."), isOptionalIfUndefined);
        VALIDATORS.push(validation);

        validation = new CPVALIDATE.validator(LOCALE.maketext("Country"));
        validation.add("country", "min_length(%input%, 2)", LOCALE.maketext("Choose a country."), isOptionalIfUndefined);
        VALIDATORS.push(validation);

        validation = new CPVALIDATE.validator(LOCALE.maketext("Company"));
        validation.add("co", "min_length(%input%, 1)", LOCALE.maketext("You must enter a company."), isOptionalIfUndefined);
        validation.add("co", "max_length(%input%, 64)", LOCALE.maketext("The company name must be no longer than [quant,_1,character,characters].", 64));
        VALIDATORS.push(validation);

        validation = new CPVALIDATE.validator(LOCALE.maketext("Company Division"));
        validation.add("cod", "min_length(%input%, 1)", LOCALE.maketext("The “[_1]” field must be at least [quant,_2,character,characters] long.", LOCALE.maketext("Company Division"), 2), isOptionalIfUndefined);
        validation.add("cod", "max_length(%input%, 64)", LOCALE.maketext("The company division must be no longer than [quant,_1,character,characters].", 64), isOptionalIfUndefined);
        VALIDATORS.push(validation);

        validation = new CPVALIDATE.validator(LOCALE.maketext("Certificate Email Address"));
        validation.add("email", "min_length(%input%, 1)", LOCALE.maketext("You must enter an email address."), isOptionalIfUndefined);
        validation.add("email", "email(%input%)", LOCALE.maketext("The email address provided is not valid. This address must start with the mailbox name, then the “@” sign, then the mail domain name."), isOptionalIfUndefined);
        VALIDATORS.push(validation);


        validation = new CPVALIDATE.validator(LOCALE.maketext("Passphrase"));
        validation.add("pass", "min_length(%input%, 4)", LOCALE.maketext("The passphrase must be at least [quant,_1,character,characters] long.", 4), isOptionalIfUndefined);
        validation.add("pass", "max_length(%input%, 20)", LOCALE.maketext("The passphrase must be no longer than [quant,_1,character,characters].", 20), isOptionalIfUndefined);
        validation.add("pass", "alphanumeric", LOCALE.maketext("You entered an invalid character. The passphrase may contain only letters and numbers."), isOptionalIfUndefined);
        VALIDATORS.push(validation);

        // Attach the validators.
        for (i = 0, l = VALIDATORS.length; i < l; i++) {
            VALIDATORS[i].attach();
        }

        // Attach the set to the submit button.
        CPVALIDATE.attach_to_form("submit-button", VALIDATORS, {
            success_callback: handle_single_submission_lockout
        });

        var companyNotice = new CPANEL.widgets.Page_Notice({
            container: "co_warning",
            level: "warn",
            content: LOCALE.maketext("This field contains characters that some certificate authorities may not accept. Contact your certificate authority to confirm that they accept these characters."),
            visible: false
        });

        var divisionNotice = new CPANEL.widgets.Page_Notice({
            container: "cod_warning",
            level: "warn",
            content: LOCALE.maketext("This field contains characters that some certificate authorities may not accept. Contact your certificate authority to confirm that they accept these characters."),
            visible: false
        });

        var events_to_listen = CPANEL.dom.has_oninput ? ["input"] : ["paste", "keyup", "change"];
        events_to_listen.forEach(function(evt) {
            EVENT.on("co", evt, warnOnSpecialCharacters, companyNotice);
            EVENT.on("cod", evt, warnOnSpecialCharacters, divisionNotice);
        });
    }

    /**
     * Toggles the enable-disable state of the xemail
     * field and related validators.
     * @method toggleSendToEmail
     */

    function toggleSendToEmail(e) {

        var xemailEl = DOM.get("xemail");

        if (this.checked) {
            xemailEl.disabled = false;
            xemailEl.focus();
            if (sendEmailValidator) {
                sendEmailValidator.verify();
            }
        } else {
            xemailEl.disabled = true;
            if (sendEmailValidator) {
                sendEmailValidator.clear_messages();
            }
        }
    }

    /**
     * Moves the selection to the end of the input fields text.
     * @method moveCaretToEnd
     * @param [] el Input Element to move the selection in.
     * @source http://stackoverflow.com/questions/511088/use-javascript-to-place-cursor-at-end-of-text-in-text-input-element
     */
    var moveCaretToEnd = function(el) {
        if (el.createTextRange) {

            // IE
            var fieldRange = el.createTextRange();
            fieldRange.moveStart("character", el.value.length);
            fieldRange.collapse();
            fieldRange.select();
        } else {

            // Firefox and Opera
            el.focus();
            var length = el.value.length;
            el.setSelectionRange(length, length);
        }
    };

    /**
     * Moves the selection to the end of the input fields text after a delay.
     * @method moveCaretToEnd
     * @param {HTMLElement} el Input Element to move the selection in.
     * @param {Number} delay Number of milliseconds to delay the move focus.
     */
    var delayedMoveCaretToEnd = function(el, delay) {
        if (typeof (delay) === "undefined") {
            delay = 0;
        }

        setTimeout(function() {
            moveCaretToEnd(el);
        }, delay);
    };


    /**
     * Initialize the form on load.
     * @method initialize
     */

    function initialize() {
        EVENT.on("sendemail", "click", toggleSendToEmail);

        registerValidators();

        var sendemail = DOM.get("sendemail");
        sendemail.focus();
        if (sendemail.checked) {
            var xemailEl = DOM.get("xemail");
            xemailEl.disabled = false;
            if (sendEmailValidator) {
                sendEmailValidator.verify();
            }
        }
    }

    EVENT.addListener(window, "load", initialize);

}());
