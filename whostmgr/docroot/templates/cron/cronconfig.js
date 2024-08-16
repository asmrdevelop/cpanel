/**
 * Page-specific Javascript for Cron Config page.
 * @class CronConfig
 */


(function() {
    var EVENT = YAHOO.util.Event,
        DOM = YAHOO.util.Dom;

    /*
     * Initializes page-specific object.
     *
     * @method initialize
     */
    var initialize = function() {

        var notices = DOM.getElementsByClassName("noticeClose", "div", "cronNotices");

        var removeNoticeContainer = function() {
            var noticesContainer = DOM.get("cronNotices");
            noticesContainer.parentNode.removeChild(noticesContainer);
        };

        for (var i = 0; i < notices.length; i++) {
            EVENT.addListener(notices[i], "click", removeNoticeContainer);
        }
    };

    EVENT.onDOMReady(initialize);
}());
