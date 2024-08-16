(function(window) {
    "use strict";

    var YAHOO = window.YAHOO;
    var CPANEL = window.CPANEL;
    var LOCALE = window.LOCALE;

    var has_submitted_once = false;

    /**
* Enables all "submit"-type buttons (<input> or <button>) on the page.
* Runs on window load.
*/
    function enable_all_submit_buttons() {
        var buttonEls = CPANEL.Y.all("input[type=submit], button[type=submit]");
        for (var i = 0; i < buttonEls.length; i++) {
            buttonEls[i].disabled = false;
        }
        return true;
    }

    /**
* "Locks" the form after the first submit so that it can't be resubmitted.
* If this is the first submission, it will create a Progress_Panel instance
* that should prevent any further submissions.
* NOTE: This assumes that there is only one form on the page and that that
* form submits via regular HTTP form submission. Do NOT use this with AJAX
* form submissions!
*
* @method handle_single_submission_lockout
* @param {object} e The event object, either from a YUI or pure DOM listener.
* @return {boolean} Whether to allow the form submission or not.
*/
    function handle_single_submission_lockout(e) {
        if (has_submitted_once) {
            if (e) {
                YAHOO.util.Event.preventDefault(e);
            }
            return false;
        } else {
            has_submitted_once = true;

            var pp = new CPANEL.ajax.Progress_Panel( null, {
                status_html: LOCALE.maketext("Processing …"),
                effect: CPANEL.ajax.FADE_MODAL
            } );

            var target;
            if (e) {
                target = YAHOO.util.Event.getTarget(e);
            }

            if (target) {
                pp.show_from_source(target);
            } else {
                pp.show();
            }

            return true;
        }
    }

    YAHOO.util.Event.addListener(window, "load", enable_all_submit_buttons );

    YAHOO.lang.augmentObject( window, {
        handle_single_submission_lockout: handle_single_submission_lockout
    } );
})(window);
