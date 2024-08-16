/*
# cpanel - whostmgr/docroot/templates/banners/banner.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global BANNER */

(function() {
    "use strict";

    /**
     * Hide the banner views.
     *
     * @private
     */
    function hideBanner() {
        document.getElementById(BANNER.id).style.display = "none";
    }

    /**
     * Show the main banner view.
     *
     * @private
     */
    function showBanner() {
        document.getElementById(BANNER.id).style.display = "block";
    }

    /**
     * Show the trouble dialog
     *
     * @private
     */
    function showProblems() {
        document.getElementById("troubleModal").style.display = "block";
    }

    /**
     * Generate the key used to store the dismissed flag.
     *
     * @private
     * @param {string} id
     * @returns string
     */
    function dismissedId( id ) {
        return "dismissed_" + id;
    }

    /**
     * Dismiss the banner ad. This will set the date the banner was dismissed so we can
     * calculate the retry period that will allow the banner to be shown again in a few
     * days according to the configured showItAgain period in seconds.
     *
     * @private
     * @param {string} bannerId
     * @returns
     */
    function dismissBanner(bannerId) {
        hideBanner();
        localStorage.setItem(dismissedId(bannerId), new Date().toISOString());
        return;
    }

    /**
     * Retrieve the last time the banner was dismissed.
     *
     * @param {string} bannerId
     * @returns
     */
    function lastTimeDismissed(bannerId) {
        return localStorage.getItem(dismissedId(bannerId));
    }

    /**
     * Open the purchase link in a new window.
     * @method purchaseAnyway
     */
    function purchaseAnyway() {
        var url = BANNER.token + "/" + BANNER.info.purchaselink;
        window.open(url);
    }

    /**
     * Initialized the banner ad.
     */
    function init() {
        if (BANNER.info.dismissible) {

            var dismissed = lastTimeDismissed(BANNER.id);
            if (dismissed) {
                if (typeof BANNER.info.show_again_in === "number") {
                    var nowDate = new Date();
                    var dismissedDate = new Date(dismissed);
                    var elapsed = nowDate - dismissedDate;
                    if (elapsed > BANNER.info.show_again_in) {
                        showBanner();
                    } else {
                        hideBanner();
                    }
                } else {
                    hideBanner();
                }
            } else {
                showBanner();
            }

            var proceedBtn = document.querySelector("#" + BANNER.id + " .proceed_to_purchase");
            if (proceedBtn) {
                proceedBtn.addEventListener( "click", function(ev) {
                    hideBanner();
                    purchaseAnyway();
                });
            }

            document.querySelectorAll("#" + BANNER.id + " .dismiss_banner").forEach(
                function(el) {
                    el.addEventListener( "click", function(ev) {
                        dismissBanner(BANNER.id);
                    });
                }
            );

            var link = document.getElementById("purchaseLink");
            if (link) {
                link.addEventListener( "click", function(ev) {
                    hideBanner(BANNER.id);
                } );
            }
        } else {
            showBanner();
        }

        if (BANNER.info.show_insufficiencies_when_detected && BANNER.info.insufficiencies.length) {
            showProblems();
        }
    }

    // Initialize the banner
    document.addEventListener( "DOMContentLoaded", init );
})();
