(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;

    var TransferSessionUI = function(queuesEl, pauseButtonEl, abortButtonEl, stateEl, summaryHeaderEl, spinnerHTML) {
        this._queuesEl = queuesEl;
        this._pauseButtonEl = pauseButtonEl;
        this._abortButtonEl = abortButtonEl;
        this._stateEl = stateEl;
        this._summaryHeaderEl = summaryHeaderEl;
        this._spinnerHTML = spinnerHTML;
        this._progressBarAnimate = 1;
    };

    YAHOO.lang.augmentObject(TransferSessionUI.prototype, {
        get_spinner_html: function() {
            return this._spinnerHTML;
        },

        set_spinner_html: function(html) {
            this._spinnerHTML = html;
            return 1;
        },

        get_should_animate: function() {
            return this._progressBarAnimate;
        },

        set_should_animate: function(shouldAnim) {
            this._progressBarAnimate = shouldAnim;
            return 1;
        },

        set_app_name_element: function(el) {
            this._app_name_element = el;
            return 1;
        },

        get_app_name_element: function() {
            return this._app_name_element;
        },

        set_source: function(source) {
            this._summaryHeaderEl[CPANEL.has_text_content ? "textContent" : "innerText"] = source ? LOCALE.maketext("Transfer from “[_1]” Summary", source) : LOCALE.maketext("Local Restore Summary");
        },

        get_queue_el: function() {
            return this._queuesEl;
        },

        _show_spinners: function() {
            var spinnerEls = YAHOO.util.Dom.getElementsByClassName("spinner");
            for (var i = 0; i < spinnerEls.length; i++) {
                spinnerEls[i].style.display = "";
            }
        },

        _hide_spinners: function() {
            var spinnerEls = YAHOO.util.Dom.getElementsByClassName("spinner");
            for (var i = 0; i < spinnerEls.length; i++) {
                spinnerEls[i].style.display = "none";
            }
        },

        _showState_COMPLETED: function() {
            this._hide_spinners();
            this._pauseButtonEl.style.display = "none";
            this._abortButtonEl.style.display = "none";
            this._stateEl.innerHTML = LOCALE.maketext("Completed");
        },

        _showState_FAILED: function() {
            this._hide_spinners();
            this._pauseButtonEl.style.display = "none";
            this._abortButtonEl.style.display = "none";
            this._stateEl.innerHTML = LOCALE.maketext("Failed");
        },

        _showState_RUNNING: function() {
            this.set_spinner_html(this.get_spinner_html());
            this._show_spinners();
            this._pauseButtonEl.style.display = "";
            this._pauseButtonEl.disabled = false;
            this._abortButtonEl.style.display = "";
            this._abortButtonEl.disabled = false;
            (this._pauseButtonEl.getElementsByTagName("div"))[0].innerHTML = LOCALE.maketext("Pause Queue");
            (this._abortButtonEl.getElementsByTagName("div"))[0].innerHTML = LOCALE.maketext("Abort");
            this._stateEl.innerHTML = LOCALE.maketext("Processing");
        },

        _showState_ABORTED: function() {
            this._hide_spinners();
            this._pauseButtonEl.style.display = "none";
            this._abortButtonEl.style.display = "none";
            this._stateEl.innerHTML = LOCALE.maketext("Aborted");
        },

        _showState_ABORTING: function() {
            this.set_spinner_html(this.get_spinner_html());
            this._show_spinners();
            (this._abortButtonEl.getElementsByTagName("div"))[0].innerHTML = "<i class='glyphicon glyphicon-refresh animate-spin'></i> " + LOCALE.maketext("Aborting …");
            this._abortButtonEl.disabled = true;
            this._pauseButtonEl.style.display = "none";
            this._abortButtonEl.style.display = "";
            this._stateEl.innerHTML = LOCALE.maketext("Aborting …");
        },

        _showState_PAUSED: function() {
            this._hide_spinners();
            (this._pauseButtonEl.getElementsByTagName("div"))[0].innerHTML = LOCALE.maketext("Resume Queue");
            (this._abortButtonEl.getElementsByTagName("div"))[0].innerHTML = LOCALE.maketext("Abort");
            this._pauseButtonEl.disabled = false;
            this._abortButtonEl.disabled = false;
            this._pauseButtonEl.style.display = "";
            this._abortButtonEl.style.display = "";
            this._stateEl.innerHTML = LOCALE.maketext("Paused");
        },

        _showState_PAUSING: function() {
            this.set_spinner_html(this.get_spinner_html());
            this._show_spinners();
            (this._pauseButtonEl.getElementsByTagName("div"))[0].innerHTML = "<i class='glyphicon glyphicon-refresh animate-spin'></i> " + LOCALE.maketext("Pausing …");
            this._pauseButtonEl.disabled = true;
            this._pauseButtonEl.style.display = "";
            this._abortButtonEl.style.display = "none";
            this._stateEl.innerHTML = LOCALE.maketext("Pausing");
        },

        _showState_PENDING: function() {
            this._pauseButtonEl.style.display = "none";
            this._abortButtonEl.style.display = "none";
            this._stateEl.innerHTML = LOCALE.maketext("Pending");
        },

        hideStateButton: function() {
            this._pauseButtonEl.disabled = true;
            this._abortButtonEl.disabled = true;
            this._pauseButtonEl.style.display = "none";
            this._abortButtonEl.style.display = "none";
        },

        setUIState: function(state) {

            if (state === "PENDING") {
                this._showState_PENDING();
            } else if (state === "RUNNING") {
                this._showState_RUNNING();
            } else if (state === "PAUSED") {
                this._showState_PAUSED();
            } else if (state === "ABORTED") {
                this._showState_ABORTED();
            } else if (state === "PAUSING") {
                this._showState_PAUSING();
            } else if (state === "ABORTING") {
                this._showState_ABORTING();
            } else if (state === "COMPLETED") {
                this._showState_COMPLETED();
            } else if (state === "FAILED") {
                this._showState_FAILED();
            } else {
                alert("TransferSessionUI cannot display state: " + state);
            }
        }
    });

    window.TransferSessionUI = TransferSessionUI;

}(window));
