/**
 * Page-specific Javascript for Spamd Startup Config page.
 * @class SpamdConf
 */


(function() {
    var EVENT = YAHOO.util.Event,
        DOM = YAHOO.util.Dom,
        lastNotice = null;

    /*
     * Called when spamd configuration successfully saved.
     *
     * @method updateSpamdConfigSuccess
     * @param {Object} o result data
     */
    var updateSpamdConfigSuccess = function(o) {
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Spamd startup configuration successfully updated."),
            level: "success"
        });
    };

    /*
     * Called when spamd configuration save is unsuccessful.
     *
     * @method updateSpamdConfigFailure
     * @param {Object} o result data
     */
    var updateSpamdConfigFailure = function(o) {
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Spamd startup configuration not updated: [_1]", o.cpanel_error.html_encode() ),
            level: "error"
        });
    };

    /*
     * Update spamd configuration.
     *
     * @method updateSpamdConfig
     * @param MouseEvent click event information
     * @param Object extra data to be determined
     */
    var updateSpamdConfig = function(mouseEvt, data) {
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Attempting to save Spamd startup configuration."),
            level: "info"
        });
        var allowedIpsValue = DOM.get("allowedips").value;
        var maxconnperchildValue = DOM.get("maxconnperchild").value;
        var maxchildrenValue = DOM.get("maxchildren").value;
        var timeouttcpValue = DOM.get("timeouttcp").value;
        var timeoutchildValue = DOM.get("timeoutchild").value;

        CPANEL.api({
            application: "whm",
            func: "save_spamd_config",
            data: {
                allowedips: allowedIpsValue,
                maxconnperchild: maxconnperchildValue,
                maxchildren: maxchildrenValue,
                timeouttcp: timeouttcpValue,
                timeoutchild: timeoutchildValue
            },
            callback: {
                success: updateSpamdConfigSuccess,
                failure: updateSpamdConfigFailure
            }
        });
    };

    /*
     * Initializes page-specific object.
     *
     * @method initialize
     */
    var initialize = function() {
        EVENT.addListener("saveButton", "click", updateSpamdConfig, {});
    };

    EVENT.onDOMReady(initialize);
}());
