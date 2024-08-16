(function()  {
    "use strict";

    /**
     * Setup common globals
     */
    var CPANEL = window.CPANEL;
    var EVENT = window.EVENT;
    var LOCALE = window.LOCALE;
    var DOM = window.YAHOO.util.Dom;
    var VALIDATORS = {};

    EVENT.onDOMReady(function() {
        EVENT.addListener("rLimitMemEnabled", "click", function(e) {
            var textbox = document.getElementById("newRLimitMemValue");
            if (textbox) {
                textbox.disabled = false;
                textbox.focus();
            }
        });

        EVENT.addListener("rLimitMemDisabled", "click", function(e) {
            var textbox = document.getElementById("newRLimitMemValue");
            if (textbox) {
                textbox.disabled = true;
            }
        });

        // Setup validator for rlimitmem
        var textbox = document.getElementById("newRLimitMemValue");
        if (textbox) {
            VALIDATORS.rlimit = new CPANEL.validate.validator(LOCALE.maketext("New [asis,RLimitMEM]"));
            VALIDATORS.rlimit.add(
                "newRLimitMemValue",
                "greater_than(%input%, 0)",
                LOCALE.maketext("The [asis,RLimitMEM] must be a positive integer greater than 1."),
                function() {
                    return DOM.get("rLimitMemEnabled").checked;
                }
            );
            VALIDATORS.rlimit.add(
                "newRLimitMemValue",
                "max_value(%input%, window.PAGE.max_mem)",
                LOCALE.maketext("The [asis,RLimitMEM] setting must not exceed the amount of memory on the system."),
                function() {
                    return DOM.get("rLimitMemEnabled").checked;
                }
            );

            VALIDATORS.rlimit.attach();
        }

        // Hookup the validators to the form
        CPANEL.validate.attach_to_form("btnSave", VALIDATORS);
    });

})(window);
