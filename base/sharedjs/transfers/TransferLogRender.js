/*
# base/sharedjs/transfers/TransferLogRender.js    Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global console:false */
/* jshint -W116, -W089 */

(function(window) {

    "use strict";

    var YAHOO = window.YAHOO;

    var item_types = {
        warnings: {
            itemclass: "warningmsg",
            maketext_string: "Warning: [_1]" //  ## no extract maketext
        },
        skipped_items: {
            itemclass: "warningmsg",
            maketext_string: "Skipped: [_1]"  //  ## no extract maketext
        },
        dangerous_items: {
            itemclass: "errormsg",
            maketext_string: "Dangerous: [_1]"  //  ## no extract maketext
        },
        altered_items: {
            itemclass: "warningmsg",
            maketext_string: "Altered: [_1]"  //  ## no extract maketext
        },
    };

    var TransferLogRender = function(tailWindow, queueWindow) {
        this._tailWindow = tailWindow;
        this._queueWindow = queueWindow;
        this._tailWindowUI = tailWindow.ui;
        this._realTargetEl = this._tailWindowUI.bodyElement;

        var targetEl = document.createDocumentFragment();

        this._targetEl = targetEl;
        this._targetList = [targetEl];
        this._currentTarget = targetEl;
        this._summaryEl = this._tailWindowUI.summaryElement || this._tailWindowUI.bodyElement;

        this._allMsgs = 0;

        this._isCaughtUp = 0;
        this._lastMessageTime = 0;
        this._waitCount = 0;

        this._waitForCatchUp = window.setInterval(function() {
            var now = (new Date().getTime() / 1000);
            if (this._lastMessageTime && (++this._waitCount > 5 || (now - this._lastMessageTime) > 0.15)) {
                this._isCaughtUp = 1;
                window.clearInterval(this._waitForCatchUp);
            }
        }.bind(this), 1000);
        this._fragmentRenderer = window.setInterval(function() {
            if (this._isCaughtUp) {
                this._realTargetEl.appendChild(this._targetEl);
                window.clearInterval(this._fragmentRenderer);
                this._realTargetEl.scrollTop = this._realTargetEl.scrollHeight;

                /* If the current target is the fragement, replace it with the real target */
                if (this._currentTarget === this._targetEl) {
                    this._currentTarget = this._realTargetEl;
                }

                /* If the fragment is in the list, replace it with the real target */
                var newTargetList = [];
                for (var i = 0; i < this._targetList.length; i++) {
                    if (this._targetList[i] == this._targetEl) {
                        newTargetList.push(this._realTargetEl);
                    } else {
                        newTargetList.push(this._targetList[i]);
                    }
                }
                this._targetList = newTargetList;

                /* Set the target to the real only (not the fragement) */
                this._targetEl = this._realTargetEl;
            }
        }.bind(this), 1000);

    };

    YAHOO.lang.augmentObject(TransferLogRender.prototype, {
        renderMessage: function(msg, logfile) {
            this._lastMessageTime = (new Date().getTime() / 1000);

            var msg_contents = msg.contents;
            var was_at_end = 1;
            if (this._isCaughtUp) {
                was_at_end = (this._realTargetEl.scrollTop + this._realTargetEl.offsetHeight + 1 >= this._realTargetEl.scrollHeight) || (this._realTargetEl.scrollHeight <= this._realTargetEl.offsetHeight) ? 1 : 0;
            }

            if (!msg_contents) {
                console.log("Unexpected message.");
                console.log(msg);
                return;
            } else if (msg_contents.msg) {
                if (msg_contents.action) {
                    if (msg_contents.action.match(/^start_/)) {
                        var startDiv = document.createElement("div");
                        startDiv.className = msg_contents.action;

                        var headerDiv = document.createElement("div");
                        headerDiv.className = msg_contents.action + "_header";
                        headerDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = msg.contents.msg.join(" ") + "\n";
                        startDiv.appendChild(headerDiv);

                        var containerDiv = document.createElement("div");
                        containerDiv.className = msg_contents.action + "_container";
                        startDiv.appendChild(containerDiv);

                        this._currentTarget.appendChild(startDiv);

                        this._targetList.push(containerDiv);
                        this._currentTarget = this._targetList[this._targetList.length - 1];
                    } else if (msg_contents.action.match(/^end_/)) {
                        if (this._targetList.length > 1) {
                            this._targetList.pop();
                            this._currentTarget = this._targetList[this._targetList.length - 1];
                        }
                    }
                } else {
                    var textContent = msg.contents.msg.join(" ");
                    var set_text_content = 0;
                    /* Replace ..1.., ..2.. with the last # */
                    if (textContent.match(/^(?:…+|\.\.+)[ ]?[0-9]+.*?(?:…+|\.\.+)/) && this._currentTarget.lastChild) {
                        var previousTextContent = this._currentTarget.lastChild[CPANEL.has_text_content ? "textContent" : "innerText"];
                        if (previousTextContent.match(/^(?:…+|\.\.+)[ ]?[0-9]+.*?[ ]?(?:…+|\.\.+)/)) {
                            this._currentTarget.lastChild[CPANEL.has_text_content ? "textContent" : "innerText"] = textContent;
                            set_text_content = 1;
                        }
                    }
                    if (!set_text_content) {
                        var msgDiv = document.createElement("div");
                        msgDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = textContent;
                        if (msg.source) {
                            if (msg.type === "error" || textContent.match(/^ERROR:/)) {
                                msgDiv.className = "error_source_remote";
                            } else if (msg.type === "warn" || textContent.match(/warn \[[^\]]*\]/)) {
                                msgDiv.className = "warn_source_remote";
                            } else {
                                msgDiv.className = "source_remote";
                            }
                        } else {
                            if (msg.type === "warn") {
                                msgDiv.className = "warn";
                            } else if (msg.type === "error") {
                                msgDiv.className = "error";
                            } else if (msg.type === "failed") {
                                msgDiv.className = "failed";
                            } else if (msg.type === "success") {
                                msgDiv.className = "success";
                            }
                        }
                        this._currentTarget.appendChild(msgDiv);
                    }
                }
            } else if (msg.type === "modulestatus") {
                var moduleStatusDiv = document.createElement("div");
                moduleStatusDiv.className = "modulestatus modulestatus_" + msg_contents.status;

                var moduleDiv = document.createElement("div");
                moduleDiv.className = "module";
                moduleDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = msg_contents.module;

                var moduleStatusContentsDiv = document.createElement("div");
                moduleStatusContentsDiv.className = "modulestatus_contents";
                moduleStatusContentsDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = (msg.contents.statusmsg || "");

                moduleStatusDiv.appendChild(moduleDiv);
                moduleStatusDiv.appendChild(moduleStatusContentsDiv);

                this._currentTarget.appendChild(moduleStatusDiv);
            } else if (msg.type === "control") {
                if (msg_contents.action === "percentage") {
                    var pct = parseInt(msg_contents.percentage, 10);
                    this._tailWindowUI.setProgressBarPercentage(pct);
                    if (this._queueWindow) {
                        this._queueWindow.setItemPercentage(logfile, pct);
                    }
                } else if (msg_contents.action === "summary") {
                    for (var item_type in item_types) {
                        var items = msg_contents[item_type];
                        if (items) {
                            for (var i = 0; i < items.length; i++) {
                                /* TODO: this logic exists in TransferMasterLogProcessor.js as well */
                                var module = items[i][0][0];
                                var func = items[i][0][1];
                                var line = items[i][0][2];

                                var selfmsg = items[i][1];

                                var action_url = items[i][2];

                                var displayDiv = document.createElement("div");
                                displayDiv.className = "summarymsg " + item_types[item_type].itemclass;
                                displayDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = LOCALE.maketext(item_types[item_type].maketext_string, selfmsg, module, func, line);  //  ## no extract maketext
                                this._summaryEl.appendChild(displayDiv);

                                if (action_url) {
                                    displayDiv.innerHTML += " ";
                                    var link = document.createElement("a");
                                    link.href = ".." + action_url[1] + "?" + CPANEL.util.make_query_string(action_url[2]);
                                    link.innerHTML = action_url[0];
                                    link.target = "_blank";
                                    displayDiv.appendChild(link);
                                }
                            }
                        }
                    }
                    if (!this._isCaughtUp) {
                        this._isCaughtUp = 1;
                        was_at_end = 1;
                    }
                } else if (msg_contents.action === "start-item") {
                    var item = msg_contents.item;
                    var item_name = msg_contents.item_name;
                    var transferItemDiv = document.createElement("div");
                    transferItemDiv.className = "transfer_item";
                    transferItemDiv[CPANEL.has_text_content ? "textContent" : "innerText"] = LOCALE.maketext("[_1]: [_2][comment,## no extract maketext (will be done via task 32670)]", item_name, item);
                    this._summaryEl.appendChild(transferItemDiv);
                } else {
                    /* unhandled action */
                    console.log(msg);
                }
            } else {
                /* unhandled message */
                console.log(msg);
            }

            if (was_at_end) {
                this._realTargetEl.scrollTop = this._realTargetEl.scrollHeight;
            }
        }
    });

    window.TransferLogRender = TransferLogRender;

}(window));
