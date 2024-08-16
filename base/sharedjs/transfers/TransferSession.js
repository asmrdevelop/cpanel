/* global action,TransferSessionUI,TransferMasterErrorLogProcessor,TransferMasterLogProcessor,TransferLogTail,confirm */
/* jshint -W098 */
(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;

    /**
     * AlertHandler function serves as an overridable wrapper
     * for confirm and alert functions
     * @class TransferSessionAlertHandler
     */

    var TransferSessionAlertHandler = function() {
        /**
         * alert function wrapper
         * @method alert
         * @param header - prompt title (not used by this, but expanded AlertHandlers will use it)
         * @param body - main copy for prompt box
         */
        this.alert = function(header, body) {
            return alert(body);
        };
        /**
         * confirm behaves differently than browser confirm()
         * requires async callback function
         * @method confirm
         * @param header (not used by this, but expanded AlertHandlers will use it)
         * @param body main copy for prompt box
         * @param confirmFunction async callback function
         * @param confirmFunctionContext represents the 'this' in the callbackFunction
         */
        this.confirm = function(header, body, confirmFunction, confirmFunctionContext) {
            if (confirm(body)) {
                confirmFunction.call(confirmFunctionContext);
            }
        };
    };

    var TransferSession = function(opts) {
        this._action = opts.action;
        this._state = opts.state;

        this._appNameEl = opts.appNameEl;
        this._windowsEl = opts.windowsEl;
        this._pauseEl = opts.pauseEl;
        this._abortEl = opts.abortEl;
        this._stateEl = opts.stateEl;
        this._summaryHeaderEl = opts.summaryHeaderEl;
        this._spinnerHTML = opts.spinnerHTML;
        this._transfer_session_id = opts.transfer_session_id;
        this._errorEl = opts.errorEl;
        this._errorMessage = opts.errorMessage;
        this._errorContent = opts.errorContent;

        this._masterLogTailRunning = 0;


        this._sessionUIObj = new TransferSessionUI(this._windowsEl, this._pauseEl, this._abortEl, this._stateEl, this._summaryHeaderEl, this._spinnerHTML);
        this._sessionUIObj.set_spinner_html(this._spinnerHTML);
        this._sessionUIObj.set_app_name_element(this._appNameEl);

        this._masterErrorProcessorObj = new TransferMasterErrorLogProcessor(this._transfer_session_id, this._sessionUIObj, this._errorEl, this._errorMessage, this._errorContent);

        this._masterProcessorObj = new TransferMasterLogProcessor(this._transfer_session_id, this._sessionUIObj, this._masterErrorProcessorObj);
        this._set_session_state(this._state || "PENDING");


        this._masterLogTail = new TransferLogTail(this._masterProcessorObj.getTransferSessionId(), "master", this._masterErrorProcessorObj);
    };

    YAHOO.lang.augmentObject(TransferSession.prototype, {
        _start_log_tail: function(progressBarAnimate) {
            this._sessionUIObj.set_should_animate(progressBarAnimate);
            if (this._masterLogTailRunning === 0) {
                this._masterLogTailRunning = 1;
                this._masterLogTail.addLog("master.log", this._masterProcessorObj.renderMessage.bind(this._masterProcessorObj));
                this._masterLogTail.addRawLog("master.error_log", this._masterErrorProcessorObj.renderMessage.bind(this._masterErrorProcessorObj));
            }
        },
        /**
         * Sets the session state on the _masterProcessorObj
         * created as a wrapper to allow _session_state_changed to be called in parallel
         * @method _set_session_state
         * @param {state} new state to set the _masterProcessorObj to
         */
        _set_session_state: function(state) {
            var current_state = this._masterProcessorObj.getSessionState();
            this._masterProcessorObj.setSessionState(state);
            this._session_state_changed(state, current_state);
        },
        /**
         * Dispatches state change event to all added listeners
         * @method _session_state_changed
         * @param {state} new state the _masterProcessorObj was set to
         * @param {oldState} old state the _masterProcessorObj was previously set to
         */
        _session_state_changed: function(state, oldState) {
            var context, listener;
            for (var i = 0; i < this.state_change_listeners.length; i++) {
                context = this.state_change_listeners[i].context;
                listener = this.state_change_listeners[i].listener;
                listener.call(context, state, oldState);
            }
        },
        /**
         * Shows confirm message to user and aborts if they click proceed.
         * @method _confirm_abort
         */
        _confirm_abort: function() {
            var self = this;
            var header = LOCALE.maketext("Abort Session Processing");
            var body = LOCALE.maketext("The system will abort any transfer processes as soon as possible. In order to prevent data loss, the system will complete ongoing restore operations before the entire session aborts.");
            body += "<hr>" + LOCALE.maketext("Are you sure you want to abort this transfer?");
            window.AlertHandler.confirm(header, body, function() {
                self.abort_session.call(self);
            }, this);
        },
        /**
         * Shows confirm message to user and aborts if they click proceed.
         * @method _confirm_pause
         */
        _confirm_pause: function() {
            var self = this;
            var header = LOCALE.maketext("Pausing queue processing …");
            var body = LOCALE.maketext("The system will not add new items to the queue until you choose to resume. In order to prevent data loss, the system will complete ongoing operations.");
            body += "<hr>" + LOCALE.maketext("Are you sure you want to pause this transfer?");
            window.AlertHandler.confirm(header, body, function() {
                self.pause_session.call(self);
            }, this);
        },
        /**
         * Storage of added listeners
         */
        state_change_listeners: [],
        /**
         * Add listener to track state change outside this scope
         * @method add_state_change_listener
         * @param {object} context The context the function should be called from (this)
         * @param {function} listener The callback function to be called on change
         */
        add_state_change_listener: function(context, listener) {
            this.state_change_listeners.push({
                context: context,
                listener: listener
            });
        },
        start_session: function() {
            var that = this;

            CPANEL.api({
                "func": "start_transfer_session",
                "data": {
                    "transfer_session_id": this._masterProcessorObj.getTransferSessionId()
                },
                "callback": {
                    "success": function(o) {
                        var response = o.cpanel_data;

                        var pid = response.pid;
                        if (pid) {
                            that._start_log_tail(true);
                            that._set_session_state("RUNNING");
                        } else {
                            window.AlertHandler.alert(null, LOCALE.maketext("Failed to start transfer."));
                        }
                    },
                    "failure": function(o) {
                        window.AlertHandler.alert(null, LOCALE.maketext("Failed to start transfer."));
                    },
                }
            });
        },

        abort_session: function() {
            var tsession = this;

            this._set_session_state("ABORTING");
            CPANEL.api({
                "func": "abort_transfer_session",
                "data": {
                    "transfer_session_id": this._masterProcessorObj.getTransferSessionId()
                },
                "callback": {
                    failure: function() {
                        window.AlertHandler.alert(null, LOCALE.maketext("Failed to abort the session."));
                        tsession._set_session_state("RUNNING");
                    }
                }
            });
        },


        pause_session: function() {
            var tsession = this;

            this._set_session_state("PAUSING");
            CPANEL.api({
                "func": "pause_transfer_session",
                "data": {
                    "transfer_session_id": this._masterProcessorObj.getTransferSessionId()
                },
                "callback": {
                    failure: function() {
                        window.AlertHandler.alert(null, LOCALE.maketext("Failed to pause the session."));
                        tsession._set_session_state("RUNNING");
                    }
                }
            });
        },

        state: function() {
            return this._masterProcessorObj.getSessionState();
        },

        init: function() {
            var that = this;

            YAHOO.util.Event.on(this._pauseEl, "click", function(e) {
                var sessionState = that.state();
                if (sessionState === "RUNNING") {
                    that._confirm_pause();
                } else if (sessionState === "PAUSED") {
                    that.start_session();
                } else {
                    window.AlertHandler.alert(null, LOCALE.maketext("There is no handler for [asis,sessionState]: [_1]", sessionState));
                }
            });

            YAHOO.util.Event.on(this._abortEl, "click", function(e) {
                var sessionState = that.state();
                if (sessionState === "RUNNING" || sessionState === "PAUSING" || sessionState === "PAUSED") {
                    that._confirm_abort();
                } else {
                    alert(LOCALE.maketext("There is no handler for [asis,sessionState]: [_1]", sessionState));
                }
            });

            var sessionState = this.state();
            var finished = 0;
            var action = that._action;

            if (sessionState === "COMPLETED" || sessionState === "FAILED" || sessionState === "ABORTED") {
                this._start_log_tail(false);
                finished = 1;
            } else if (sessionState === "ABORTING") {
                this._start_log_tail(true);
                this._set_session_state("ABORTING");
            } else if (sessionState === "PAUSING") {
                this._start_log_tail(true);
                this._set_session_state("PAUSING");
            } else if (sessionState === "PAUSED") {
                if (action === "resume") {
                    this.start_session();
                } else {
                    this._start_log_tail(false);
                    this._set_session_state("PAUSED");
                }
            } else if (action === "start" || action === "resume") {
                this.start_session();
            } else {
                this._start_log_tail(true);
            }

            if (!finished && action === "abort") {
                this._confirm_abort();
            }
        },
    });

    window.TransferSession = TransferSession;

    /* uses default browser alert and confirm if no other AlertHandler is set */
    if (!window.AlertHandler) {
        window.AlertHandler = new TransferSessionAlertHandler();
    }

}(window));
