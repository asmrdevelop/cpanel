/* jshint -W035 */
/* jshint -W116 */
(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;

    var QUEUE_TIMER_INTERVAL = 250;
    var MAX_TAIL_ERRORS = 10; // cpsrvd may send a 307 or 301 so we need to be able to reconnect
    var MAX_ERROR_COUNT = 150;
    var IE_READY_STATE_MAP = {
        "uninitialized": 0,
        "loading": 1,
        "loaded": 2,
        "interactive": 3,
        "complete": 4
    };

    var LogTail = function(systemId, sessionId, tail_name, masterErrorProcessorObj) {
        this._systemId = systemId;
        this._sessionId = sessionId;
        this._logs = {};
        this._termination_integer = Math.floor(Math.random() * (10000000000));
        this._termination_sequence = "[tail_end:" + this._termination_integer + "]";
        this._tail_name = tail_name;
        this._tail_errors = 0;
        this._deletedLogs = {};
        this._string_position = 0;
        this._reached_end = 0;
        this._logsChanged = 0;
        this._masterErrorProcessorObj = masterErrorProcessorObj;
    };

    YAHOO.lang.augmentObject(LogTail.prototype, {
        start: function() {
            alert("Please use .addLog and .delLog");
        },

        abort: function() {
            console.trace("failed to create abort object");
        },

        delLog: function(logFile) {
            delete this._logs[logFile];
            this._deletedLogs[logFile] = 1;
            if (!this.hasLogs()) {
                this._logsChanged = 0;
                if (this._queue_timer) {
                    window.clearInterval(this._queue_timer);
                    this._queue_timer = null;
                }
            }
        },

        processLogQueue: function() {
            if (this._logsChanged) {
                if (this.hasLogs()) {
                    this._send_request();
                }
                this._logsChanged = 0;
            }
            if (!this._reached_end) {
                this._process_request();
            }
        },

        addRawLog: function(logFile, logProcessorFunc) {
            this.addLog(logFile, logProcessorFunc);
            this._logs[logFile]["raw"] = 1;
        },

        addLog: function(logFile, logProcessorFunc) {
            if (!this.hasLogs()) {
                if (this._queue_timer) {
                    window.clearInterval(this._queue_timer);
                    this._queue_timer = null;
                }
                this._queue_timer = window.setInterval(this.processLogQueue.bind(this), QUEUE_TIMER_INTERVAL);
            }
            this._logs[logFile] = {
                "bytes_processed": 0,
                "raw": 0,
                "err_count": 0,
                "logProcessorFunc": logProcessorFunc
            };
            this._logsChanged = 1;
        },

        hasLogs: function() {
            for (var k in this._logs) {
                if (this._logs.hasOwnProperty(k)) {
                    return true;
                }
            }
        },

        logCount: function() {
            return Object.keys(this._logs).length;
        },

        _send_request: function() {
            if (this._request && YAHOO.util.Connect.isCallInProgress(this._request)) {
                YAHOO.util.Connect.abort(this._request);
            }
            this._string_position = 0;
            this._reached_end = 0;
            this._deletedLogs = {};

            var query = {
                system_id: this._systemId,
                session_id: this._sessionId,
                "termination_integer": this._termination_integer
            };
            var file_count = 0;
            for (var logFile in this._logs) {
                if (this._logs.hasOwnProperty(logFile)) {
                    file_count++;
                    query["log_file" + file_count] = logFile;
                    query["log_file_position" + file_count] = this._logs[logFile].bytes_processed;
                }
            }

            var target_url = "../cgi/live_tail_log.cgi" + "?" + CPANEL.util.make_query_string(query);

            if (YAHOO.env.ua.ie && YAHOO.env.ua.ie < 9) {
                if (this._iframeEl) {
                    this._iframeEl.parentNode.removeChild(this._iframeEl);
                }
                this._iframeEl = document.createElement("iframe");
                this._iframeEl.style.display = "none";
                DOM.get("content").appendChild(this._iframeEl);
                this._iframeEl.contentWindow.location.href = target_url;
            } else {
                this._request = YAHOO.util.Connect.asyncRequest(
                    "GET",
                    target_url, {
                        "success": this._process_request.bind(this),
                        "failure": this._handle_tail_failure.bind(this),
                    }
                );
            }
            this.abort = function() {
                this._reached_end = 1;
                if (this._iframeEl) {
                    this._iframeEl.contentWindow.location.href = "about:blank";
                }
                if (this._request) {
                    YAHOO.util.Connect.abort(this._request);
                }
            };
            this.abort.bind(this);

            return 1;
        },

        // YUI 2 assigns values of 0 for non-HTTP responses and -1 for aborted
        // transactions. In either of these cases, we should NOT print an error.
        _handle_tail_failure: function(o) {
            if ((o.status > 0) && (o.status !== 200)) {
                ++this._tail_errors;
                var errmsg = LOCALE.maketext("[asis,live_tail_log] encountered an internal error: [_1]", o.statusText);
                if (o.status !== 301 && o.status !== 307 && this._masterErrorProcessorObj) {
                    this._masterErrorProcessorObj.renderMessage(errmsg);
                }
                if ( this._tail_errors >= MAX_TAIL_ERRORS) {
                    var finalmsg = LOCALE.maketext("[asis,live_tail_log] encountered the maximum allowed errors ([numf,_1]) and will not continue.", this._tail_errors);
                    if (this._masterErrorProcessorObj) {
                        this._masterErrorProcessorObj.renderMessage(finalmsg);
                    } else {
                        alert(o.statusText);
                        alert(finalmsg);
                    }
                    this.abort();
                    return 0;
                }
            }
            this._logsChanged = 1; /* force request to be resent */
        },

        _process_request: function(o) {
            var xhr;

            if (o) { /* yuiCallback */
                xhr = o;
                xhr.readyState = 4;
            } else if (this._request && this._request.conn) { /* poll */
                xhr = this._request.conn;
            } else if (this._iframeEl) {
                if (!this._iframeEl.contentWindow.document.body) {
                    return; /* not loaded yet */
                }
                xhr = {
                    "readyState": IE_READY_STATE_MAP[this._iframeEl.readyState],
                    "responseText": this._iframeEl.contentWindow.document.body.innerText ? this._iframeEl.contentWindow.document.body.innerText : this._iframeEl.contentWindow.document.body.textContent
                };

                /* IE work around */
                if (xhr.readyState === 4) {
                    xhr.responseText += this._newline;
                }
            } else {
                return;
            }

            var rawdata;
            try {
                rawdata = xhr.responseText.substr(this._string_position);
            } catch (e) {
                return;
            }

            var lastEndofLine = rawdata.lastIndexOf(this._newline);
            if (lastEndofLine > -1) {
                this._string_position += (lastEndofLine + this._newline.length);
                var newdata = rawdata.substr(0, lastEndofLine);
                var log_data_arr = newdata.split(this._newline);

                for (var i = 0; i < log_data_arr.length; i++) {
                    if (log_data_arr[i] === ".") {
                        this._tail_errors = 0;

                        /* keep alive */
                        continue;
                    } else if (log_data_arr[i] === this._termination_sequence) {

                        /* end of stream */
                        this._reached_end = 1;
                        continue;
                    } else if ( log_data_arr[i] === "" ) {
                        continue;
                    } else if (log_data_arr[i].indexOf("|") === -1) {
                        this._handle_tail_failure({ "status": 500, "statusText": log_data_arr[i] });
                        continue;
                    }

                    var demultiplexedData = log_data_arr[i].split("|");
                    var logFile = demultiplexedData.shift();
                    var server_length = parseInt(demultiplexedData.shift());
                    var data = demultiplexedData.join("|");

                    if (data) {
                        if (this._deletedLogs[logFile]) {

                            // console.log("deleted log: " + log_data_arr[i]);
                        } else if (!this._logs[logFile]) {

                            // console.log("unknown log: " + log_data_arr[i]);
                        } else {
                            this._tail_errors = 0;
                            this._logs[logFile].bytes_processed += server_length;
                            this._log_processor(logFile, data);
                        }
                    } else {

                        // If there is no data we don't want to log it - this allows us to ignore empty lines
                    }

                }
            }
            if (xhr.readyState === 4) {
                if (this._reached_end) {
                    this._logs = {};
                    if (this._queue_timer) {
                        window.clearInterval(this._queue_timer);
                        this._queue_timer = null;
                    }
                } else {
                    this._logsChanged = 1;
                }
            }

            return 1;
        },

        _log_processor: function(logFile, data) {
            if (this._logs[logFile].raw) {
                return this._logs[logFile].logProcessorFunc(data, logFile);
            }

            var msg = "";
            try {
                if (data.indexOf("{") !== 0) {
                    throw "Non JSON data passed to parser.";
                }
                msg = JSON.parse(data);
            } catch (e) {
                this._logs[logFile].err_count++;
                if (this._logs[logFile].err_count === MAX_ERROR_COUNT) {
                    data = LOCALE.maketext("Too many errors from “[_1]”. Future errors will be suppressed.", logFile);
                }
                if (this._logs[logFile].err_count <= MAX_ERROR_COUNT) {
                    msg = {
                        "type": "error",
                        "contents": {
                            "msg": [data]
                        }
                    };
                }
            }
            if (msg) {
                return this._logs[logFile].logProcessorFunc(msg, logFile);
            }
        },

        _newline: ((YAHOO.env.ua.ie && YAHOO.env.ua.ie < 9) ? "\r\n" : "\n")
    });

    window.LogTail = LogTail;

}(window));