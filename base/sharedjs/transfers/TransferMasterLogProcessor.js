/*global console:true, alert:true, TransferTailWindowUI:false, TransferLogTail:false, TransferLogRender:false, TransferQueueWindowUI:false */
/*jshint -W116, -W035 */
/* eslint camelcase: 0 */
(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;
    var DOM = window.DOM;
    var EVENT = window.EVENT;

    var ENABLE_SUBITEMS = 0;

    //TODO: This needs to be redone in a localizable way.
    var ITEM_TYPES = {
        failure: {
            className: "subitem_status",
            maketext_string: "[_1]", //  ## no extract maketext
        },
        warnings: {
            className: "warningmsg",
            maketext_string: "[quant,_1,warning,warnings]", //  ## no extract maketext
        },
        skipped_items: {
            className: "warningmsg",
            maketext_string: "[quant,_1,skipped item,skipped items]", //  ## no extract maketext
        },
        dangerous_items: {
            className: "errormsg",
            maketext_string: "[quant,_1,dangerous item,dangerous items]", //  ## no extract maketext
        },
        altered_items: {
            className: "warningmsg",
            maketext_string: "[quant,_1,altered item,altered items]", //  ## no extract maketext
        }
    };

    var TransferMasterLogProcessor = function(transfer_session_id, sessionUIObj, masterErrorProcessorObj) {
        this._queue_windows = {};
        this._logfiles = {};
        this._childTailObj = new TransferLogTail(transfer_session_id, "child", masterErrorProcessorObj);
        this._sessionUIObj = sessionUIObj;
        this._sessionState = "UNKNOWN";
        this._transfer_session_id = transfer_session_id;
    };

    YAHOO.lang.augmentObject(TransferMasterLogProcessor.prototype, {
        getTransferSessionId: function() {
            return this._transfer_session_id;
        },

        getSessionState: function() {
            return this._sessionState;
        },

        setSessionState: function(newState) {
            this._sessionState = newState;
            this._sessionUIObj.setUIState(newState);
            return 1;
        },

        renderMessage: function(msg) {
            if (msg.type == "control") {
                if (msg.contents.action === "process-item") {
                    this._start_item_tail(msg.contents);
                } else if (msg.contents.action === "initiator") {
                    // do nothing
                    // new TransferLogName(this._sessionUIObj.get_app_name_element(), msg.contents.msg);
                } else if (msg.contents.action === "start") {
                    //do nothing
                } else if (msg.contents.action === "remotehost") {
                    this._sessionUIObj.set_source(msg.contents.msg);
                } else if (msg.contents.action === "version") {
                    //do nothing
                } else if (msg.contents.action === "pause") {
                    this.setSessionState("PAUSED");
                } else if (msg.contents.action === "pausing") {
                    this.setSessionState("PAUSING");
                } else if (msg.contents.action === "aborting") {
                    this.setSessionState("ABORTING");
                } else if (msg.contents.action === "resume") {
                    this.setSessionState("RUNNING");
                } else if (msg.contents.action === "child-failed") {
                    // do nothing
                } else if (msg.contents.action === "complete" || msg.contents.action === "abort" || msg.contents.action === "fail") {
                    this._complete_queue(msg.contents);
                    if (!msg.contents.child_number) {
                        if (msg.contents.action === "complete") {
                            this.setSessionState("COMPLETED");
                        } else if (msg.contents.action === "abort") {
                            this.setSessionState("ABORTED");
                        } else {
                            this.setSessionState("FAILED");
                        }
                    }
                } else if (msg.contents.action === "queue_count") {
                    //Start a new queue window group
                    this._setup_queue(msg.contents);
                } else if (msg.contents.action === "queue_size") {
                    this._track_queue_size(msg.contents);
                } else if (msg.contents.action === "start-item") {
                    this._start_item(msg.contents);
                } else if (msg.contents.action === "success-item" || msg.contents.action === "warning-item" || msg.contents.action === "failed-item") {
                    this._finish_item(msg.contents.action, msg.contents);
                } else {
                    console.log("Unhandled message");
                    console.log(msg.contents);
                }
            }
        },

        _getQueueTailWindow: function(queue, windownum) {
            if (!this._queue_windows[queue]) {
                alert("Message out of order for queue: " + queue);
                console.trace();
                return;
            }
            if (!this._queue_windows[queue].tail_windows["w_" + windownum]) {
                this._queue_windows[queue].tail_windows["w_" + windownum] = {
                    logFile: null,
                    ui: new TransferTailWindowUI(queue, windownum, this._sessionUIObj)
                };
                this._queue_windows[queue].ui.addWindow(this._queue_windows[queue].tail_windows["w_" + windownum].ui.containerElement);
                this._queue_windows[queue].tail_windows["w_" + windownum].ui.render();
            }
            return this._queue_windows[queue].tail_windows["w_" + windownum];
        },

        _start_item_tail: function(item_message) {
            var logfile = item_message.msg;
            var queue = item_message.queue;
            var tail_window = this._getQueueTailWindow(queue, item_message.child_number);

            if (tail_window.logFile) {
                this._childTailObj.delLog(tail_window.logFile);
            }
            this._logfiles[logfile] = {
                //FIXME: digging in the tail_window object
                renderer: new TransferLogRender(tail_window, this._queue_windows[queue])
            };

            if (item_message.local_item && item_message.local_item !== item_message.item) {
                tail_window.ui.set_item(LOCALE.maketext("[_1]: “[_2]” → “[_3]”", item_message.item_name, item_message.item, item_message.local_item));
            } else {
                tail_window.ui.set_item(LOCALE.maketext("[_1]: “[_2]”", item_message.item_name, item_message.item));
            }
            tail_window.ui.setProgressBarPercentage(0);
            tail_window.logFile = logfile;

            //FIXME this is a hack
            if (this.getSessionState() === "PAUSED" || this.getSessionState() === "ABORTED") {
                this._sessionUIObj._hide_spinners();
            }

            this._childTailObj.addLog(
                logfile,
                this._logfiles[logfile].renderer.renderMessage.bind(this._logfiles[logfile].renderer)
            );
        },

        _setup_queue: function(item_message) {
            var itemcount = parseInt(item_message.msg, 10);
            var queue = item_message.queue;

            this._setup_queue_window_group(queue, itemcount);
        },

        _track_queue_size: function(item_message) {
            var size = parseInt(item_message.msg, 10);
            var queue = item_message.queue;

            this._queue_windows[queue].relative_item_size = {
                completed: 0,
                total: size
            };
        },

        _setup_queue_window_group: function(queue, itemcount) {
            if (this._queue_windows[queue]) {
                //replay on resume so no need to set it up again
                return;
            }

            this._queue_windows[queue] = {
                tail_windows: {},
                items: {},
                itemcount: itemcount,
                itemstatus: {
                    success: 0,
                    warnings: 0,
                    failed: 0,
                },
                processedcount: 0,
                relative_item_size: {
                    completed: 0,
                    total: 0,
                },
                ui: new TransferQueueWindowUI(queue, this._sessionUIObj)
            };
            var self = this;
            this._queue_windows[queue].setItemPercentage = function(logfile, pct) {
                self._update_progress(queue, logfile, pct);
            };
        },

        _update_progress: function(queue, logfile, pct) {
            var pctQueue;
            var queue_window = this._queue_windows[queue];

            if (!queue_window.items[logfile]) {
                /* already reached 100% from the master.log */
                return;
            }

            var previous_percent = queue_window.items[logfile].percent;
            var size = queue_window.items[logfile].size;
            var newly_completed_percent = (pct - previous_percent);
            var additional_relative_size_completed = (newly_completed_percent / 100) * size;

            queue_window.items[logfile].percent = pct;
            queue_window.items[logfile].completed += additional_relative_size_completed;
            queue_window.relative_item_size.completed += additional_relative_size_completed;

            if (pct >= 99.9999) {
                var epsilon = 0;
                if (queue_window.items[logfile].completed > size) {
                    epsilon = queue_window.items[logfile].completed - size;
                }
                queue_window.relative_item_size.completed -= epsilon;
                delete queue_window.items[logfile];
            }

            // http://en.wikipedia.org/wiki/Machine_epsilon
            if (Math.abs(queue_window.relative_item_size.completed - queue_window.relative_item_size.total) < 0.0001) {
                pctQueue = 1;
            } else {
                pctQueue = queue_window.relative_item_size.completed / queue_window.relative_item_size.total;
            }

            queue_window.ui.setProgressBarPercentage(parseInt(pctQueue * 100, 10));

        },

        _start_item: function(item_message) {
            var queue = item_message.queue;
            var queue_window = this._queue_windows[queue];
            var this_message = item_message.msg;
            var size = parseInt(this_message.size, 10);

            queue_window.items[item_message.logfile] = {
                size: size,
                completed: 0,
                percent: 0
            };
        },

        _finish_item: function(item_type, item_message) {
            var queue = item_message.queue;
            var queue_window = this._queue_windows[queue];
            var this_message = item_message.msg;
            var was_at_end = (queue_window.ui.outputEl.scrollTop + queue_window.ui.outputEl.offsetHeight + 1 >= queue_window.ui.outputEl.scrollHeight) || (queue_window.ui.outputEl.scrollHeight <= queue_window.ui.outputEl.offsetHeight) ? 1 : 0;

            queue_window.processedcount++;

            // on the last item disable the state button
            if (queue === "RESTORE" && queue_window.processedcount >= queue_window.itemcount - 1) {
                this._sessionUIObj.hideStateButton();
            }

            //Update progressbar
            this._update_progress(queue, item_message.logfile, 100);

            var report_item_in_summary = 0;

            /* Add each item to the report */
            var div_html;
            var itemClass;
            var fallback_msg;
            if (item_type === "success-item") {
                fallback_msg = LOCALE.maketext("Success");
                itemClass = "okmsg";
                this._queue_windows[queue]["itemstatus"]["success"]++;
            } else if (item_type === "warning-item") {
                fallback_msg = LOCALE.maketext("Warnings");
                itemClass = "warningmsg";
                report_item_in_summary = 1;
                this._queue_windows[queue]["itemstatus"]["warnings"]++;
            } else {
                fallback_msg = LOCALE.maketext("Failed");
                itemClass = "errormsg";
                report_item_in_summary = 1;
                this._queue_windows[queue]["itemstatus"]["failed"]++;
            }

            /* TODO: THIS SHOULD ALL BE IN THE UI OBJECT */
            var summary_msg = this_message.failure || this_message.message || fallback_msg;
            if (item_message.local_item && item_message.local_item !== item_message.item) {
                div_html = LOCALE.maketext("[_1] “[_2]” → “[_3]”: [_4][comment,## no extract maketext (will be done via task 32670)]", item_message.item_name, item_message.item, item_message.local_item, summary_msg);
            } else {
                div_html = LOCALE.maketext("[_1] “[_2]”: [_3][comment,## no extract maketext (will be done via task 32670)]", item_message.item_name, item_message.item, summary_msg);
            }

            var link;
            var statusDiv = document.createElement("div");
            if (item_message.logfile) {
                link = this._create_log_link(queue, div_html, this._transfer_session_id, item_message.logfile);
                statusDiv.appendChild(link);
            } else {
                statusDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = div_html;
            }
            statusDiv.className = itemClass;
            queue_window.ui.outputEl.appendChild(statusDiv);

            var item;
            if (ENABLE_SUBITEMS) {
                /* Now build any subitems that go under the item
                 * for exmaple 12 Warnings
                 * 3 Dangerous Item */
                for (item in this_message) {
                    if (ITEM_TYPES[item] && this_message[item]) {
                        var newDiv = document.createElement("div");
                        newDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = LOCALE.maketext(ITEM_TYPES[item].maketext_string, this_message[item]); //  ## no extract maketext
                        newDiv.className = ITEM_TYPES[item].className + " subitem_status";
                        queue_window.ui.outputEl.appendChild(newDiv);
                    }
                }
            }

            if (report_item_in_summary) {
                var report = DOM.get("report"); // FIXME use UI object
                var actual_items = this_message.contents;
                var masterDiv = document.createElement("div");
                masterDiv.className = itemClass;

                if (item_message.local_item && item_message.local_item !== item_message.item) {
                    div_html = LOCALE.maketext("[_1]: [_2] “[_3]” → “[_4]”: [_5][comment,## no extract maketext (will be done via task 32670)]", queue, item_message.item_name, item_message.item, item_message.local_item, summary_msg);
                } else {
                    div_html = LOCALE.maketext("[_1]: [_2] “[_3]”: [_4][comment,## no extract maketext (will be done via task 32670)]", queue, item_message.item_name, item_message.item, summary_msg);
                }

                if (item_message.logfile) {
                    link = this._create_log_link(queue, div_html, this._transfer_session_id, item_message.logfile);
                    masterDiv.appendChild(link);
                } else {
                    masterDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = div_html;
                }

                report.appendChild(masterDiv);

                var logEntryDiv = document.createElement("div");
                report.appendChild(logEntryDiv);

                for (item in actual_items) {
                    if (ITEM_TYPES[item] && actual_items[item] && actual_items[item].length) {
                        for (var logindex = 0; logindex < actual_items[item].length; logindex++) {
                            /* TODO: this logic exists in TransferLogRender.js as well */
                            var log_message_to_display = actual_items[item][logindex];

                            //This doesn’t seem to get the actual message.
                            var log_text = log_message_to_display[1];

                            //This is where the message seems to be.
                            //Leaving it as fallback logic to avoid
                            //inadvertent breakage.
                            if (!log_text && log_message_to_display.msg) {
                                log_text = log_message_to_display.msg[0];
                            }

                            var msg_div = document.createElement("div");
                            msg_div.className = ITEM_TYPES[item].className + " subitem_status";
                            msg_div[CPANEL.has_text_content ? "textContent" : "innerText"] = log_text;
                            logEntryDiv.appendChild(msg_div);

                            var action_url = log_message_to_display[2];
                            if (action_url) {
                                msg_div.innerHTML += " ";
                                link = document.createElement("a");
                                link.href = ".." + action_url[1] + "?" + CPANEL.util.make_query_string(action_url[2]);
                                link[CPANEL.has_text_content ? "textContent" : "innerText"] = action_url[0];
                                link.target = "_blank";
                                msg_div.appendChild(link);
                            }
                        }
                    }
                }
            }

            if (was_at_end) {
                queue_window.ui.outputEl.scrollTop = queue_window.ui.outputEl.scrollHeight;
            }
        },

        _addLogReviewAction: function(el, logfile) {
            EVENT.on(el, "click", function() {
                window.open("render_transfer_log?transfer_session_id=" + encodeURIComponent(this._transfer_session_id) + "&log_file=" + encodeURIComponent(logfile));
            });
        },

        _create_log_link: function(queue, text_content, transfer_session_id, logfile) {
            var link = document.createElement("a");
            link.href = "render_transfer_log?" + CPANEL.util.make_query_string({
                transfer_session_id: transfer_session_id,
                log_file: logfile
            });
            link[CPANEL.has_text_content ? "textContent" : "innerText"] = text_content;
            link.target = "_blank";
            if (queue === "TRANSFER") {
                link.title = LOCALE.maketext("View this transfer’s log.");
                link.id = "transfer_log_for_" + transfer_session_id;

            } else {
                link.title = LOCALE.maketext("View this restoration’s log.");
                link.id = "restoration_log_for_" + transfer_session_id;
            }
            var spacer = document.createElement("span");
            spacer[CPANEL.has_text_content ? "textContent" : "innerText"] = " ";
            link.appendChild(spacer);
            var icon = document.createElement("span");
            icon.className = "glyphicon glyphicon-expand";
            link.appendChild(icon);
            return link;
        },

        _completeSummary: function() {
            /* TODO: THIS SHOULD ALL BE IN THE UI OBJECT */
            var queue;
            var queues = [];
            for (queue in this._queue_windows) {
                if (this._queue_windows.hasOwnProperty(queue)) {
                    queues.push(queue);
                }
            }
            queues = queues.sort();
            for (var i = 0; i < queues.length; i++) {
                queue = queues[i];
                var itemstatus = this._queue_windows[queue]["itemstatus"];
                var summaryDiv = document.createElement("h5");
                summaryDiv.className = "summary_of_summary";
                summaryDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = LOCALE.maketext("[_1]: [_2] completed, [_3] had warnings, and [_4] failed.[comment,## no extract maketext (will be done via task 32670)]", queue, (itemstatus["success"] + itemstatus["warnings"]), itemstatus["warnings"], itemstatus["failed"]);
                var report = DOM.get("report"); // FIXME use UI object
                if (report.firstChild) {
                    report.insertBefore(summaryDiv, report.firstChild);
                } else {
                    report.appendChild(summaryDiv);
                }
            }

        },

        _complete_queue: function(item_message) {
            if (item_message.child_number) {
                var tail_window = this._getQueueTailWindow(item_message.queue, item_message.child_number);

                if (tail_window) {
                    if (tail_window.logFile) {
                        this._childTailObj.delLog(tail_window.logFile);
                    }
                    tail_window.ui.set_item(LOCALE.maketext(item_message.action)); //  ## no extract maketext
                    CPANEL.animate.slide_up(tail_window.ui.containerElement);
                }
            } else {
                this._completeSummary();
            }
        }
    });

    window.TransferMasterLogProcessor = TransferMasterLogProcessor;

}(window));
