// -----------------------------------------------------------------------------
// Publish public properties into the global scope for backwards compatability
// -----------------------------------------------------------------------------

/**
 * Handle to the wait panel.
 * @property waitpanel
 * @type {YAHOO.widget.Panel}
 * @public
 * @global
 */
var waitpanel;

/**
 * Global switch to determin if the statusbox shows as a modal or not. Set
 * to 1 to make it modal and 0 to make it modeless. Defaults to modal.
 * @property statusbox_model
 * @type {Boolean (0|1)}
 * @public
 * @global
 */
var statusbox_modal;


(function() {

    // -----------------------
    //  Shortcuts
    // -----------------------
    var DOM = YAHOO.util.Dom;
    var EVENT = YAHOO.util.Event;

    /**
     * @property pending_ui_status
     * @type {Boolean (0|1)}
     * @private
     */
    var pending_ui_status = null;

    /**
     * Initialize the state of the user interface
     * @method initialize_ui_state
     * @static
     */

    function initialize_ui_state() {
        if (!statusbox_modal) {
            statusbox_modal = 1;
        }
    }


    /**
     * Updates the status string in the processing popup
     * @method update_ui_status
     * @public
     * @static
     */

    function update_ui_status(newstatus) {
        if (waitpanel) {
            show_loading(whmappname, newstatus);
        } else {
            pending_ui_status = newstatus;
        }
    }

    /**
     * Clears the processing popup
     * @method clear_ui_status
     * @public
     * @static
     */

    function clear_ui_status() {
        if (!waitpanel) {
            pending_ui_status = undefined;
            return;
        }
        waitpanel.hide();
    }

    /**
     *
     * @method
     * @param
     * @static
     */

    function dowait() {
        if (waitpanel) {
            return;
        }

        var effect_func = statusbox_modal ?
            CPANEL.animate.ContainerEffect.FADE_MODAL :
            YAHOO.widget.ContainerEffect.FADE;

        waitpanel = new YAHOO.widget.Panel("waitpanel", {
            width: "252px",
            fixedcenter: true,
            close: false,
            draggable: false,
            modal: (statusbox_modal ? true : false),
            visible: false,
            effect: {
                effect: effect_func,
                duration: 0.25
            }
        });

        if (pending_ui_status) {
            update_ui_status(pending_ui_status);
        }

        if (document.images) {
            var preloadImg = new Image();
            preloadImg.src = "/img/yui/rel_interstitial_loading.gif";
        }
    }

    /**
     * Shows the loading panel
     * @method show_loading
     * @param action {String} Title for the loading panel.
     * @param body {String} Text content in the body of the loading panel.
     * @param onHideMask {function} Handler called after the mask is removed.
     * @public
     * @static
     */

    function show_loading(action, body, onHideMask) {
        if (action === null) {
            action = "Processing...";
        }

        waitpanel.setHeader('<div class="lt"></div><span>' + action + '</span><div class="rt"></div>');
        var loadingimg = '<img src="/img/yui/rel_interstitial_loading.gif" />';
        if (body) {
            waitpanel.setBody(body + "<br />" + loadingimg);
        } else {
            waitpanel.setBody(loadingimg);
        }

        if (onHideMask) {
            waitpanel.hideMaskEvent.subscribe(onHideMask);
        }

        waitpanel.render(document.body);

        // case 49380 (fix for Safari 5)
        waitpanel.innerElement.style.overflow = "visible";


        waitpanel.show();
        waitpanel.render(); /* Safari Fix */
    }

    initialize_ui_state();

    // Handlers
    EVENT.onDOMReady(dowait);
    EVENT.onAvailable("sdiv", dowait);

    // Publish public function into the global scope
    window["clear_ui_status"] = clear_ui_status;
    window["show_loading"] = show_loading;
    window["update_ui_status"] = update_ui_status;
}());
