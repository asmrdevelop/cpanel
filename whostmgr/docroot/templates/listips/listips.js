/**
 * Page-specific Javascript for ListIps page.
 * @class ListIps
 */


(function() {
    var EVENT = YAHOO.util.Event,
        DOM = YAHOO.util.Dom,
        lastNotice = null,
        DEFAULT_FADE_OUT = 5000,
        MESSAGE_TYPE_ERROR = "error",
        rowBeingEdited = false,
        rowBeingDeleted = false,
        SKIP_TABLE_SORTING_INIT = true,
        FORCE_TABLE_SORTING_INIT = false;

    /**
     * Clears the status icon in a given table row.
     *
     * @method clearStatus
     * @param {String} rowId The id for the row to be modified.
     */
    var clearStatus = function(rowId) {
        var statusCell = DOM.get(rowId + "Status");
        statusCell.className = "natStatus";
    };

    /**
     * Causes a context-specific message to be displayed. This message replaces
     * the default informational message until the context message is
     * dismissed.
     *
     * @method showContextMessage
     * @param {String} messageType The type of message type to be displayed (only "error" is currently supported)
     * @param {String} message The message to be displayed
     */
    var showContextNotice = function(messageType, message) {
        var contextNoticeContent = DOM.get("contextNoticeContent");
        contextNoticeContent.innerHTML = message;
        if (messageType === MESSAGE_TYPE_ERROR) {
            DOM.addClass("contextNotice", "notice-error");
        } else {
            DOM.removeClass("contextNotice", "notice-error");
        }
        DOM.addClass("defaultNotice", "notice-hidden");
        DOM.removeClass("contextNotice", "notice-hidden");
    };

    /**
     * Hides the context-specific message box. Restores the default informational message.
     *
     * @method hideContextNotice
     */
    var hideContextNotice = function() {
        DOM.addClass("contextNotice", "notice-hidden");
        DOM.removeClass("contextNotice", "notice-error");
        DOM.removeClass("defaultNotice", "notice-hidden");
    };

    /*
     * Calculates the sort key for an IP address.
     * Used when the public ip address is updated.
     *
     * @method calculateIpSortKey
     * @param ipAddress {String} The ip address for the search key
     */
    var calculateIpSortKey = function(ipAddress) {

        // check to see if value passed is actually an
        // ip address

        if (!CPANEL.validate.ip(ipAddress)) {
            return ipAddress;
        }

        var ipSegments = ipAddress.split(".");

        for (var i = 0, length = ipSegments.length; i < length; i++) {
            while (ipSegments[i].length < 3) {
                ipSegments[i] = "0" + ipSegments[i];
            }
        }

        return ipSegments.join("");
    };

    /*
     * Determines whether sorting should be enabled or disabled for the
     * ip list table. If an error condition exists, sorting is disabled;
     * otherwise sorting is allowed.
     *
     * @param {Boolean} skipInit Do not reinitialize the sorting data structures
     */
    var fixTableSorting = function(skipInit) {
        var errorConditions = DOM.getElementsByClassName("dupError", "tr", "natlist");

        var headers = DOM.getElementsBy(function(el) {
            return el.tagName.toUpperCase() === "TH" && !DOM.hasClass(el, "status");
        }, "th", "natlist");

        // if there is at least one error condition
        if (errorConditions.length > 0) {

            for (var i = 0, length = headers.length; i < length; i++) {
                DOM.removeClass(headers[i], "clickable");
                DOM.addClass(headers[i], "sorttable_nosort");
            }
        } else {
            for (var ix = 0, len = headers.length; ix < len; ix++) {
                DOM.removeClass(headers[ix], "sorttable_nosort");
            }
            if (!skipInit) {
                DOM.removeClass(headers, "clickable");
                sorttable.makeSortable(DOM.get("natlist"));
            }
        }
    };

    /*
     * Changes the pubic ip sort key for a given table row. Called
     * after an action (i.e. validate or edit) has changed the row's public
     * ip address.
     *
     * @method updatePublicIpSortKey
     * @param {String} rowId The row containing the changed public ip address.
     */
    var updatePublicIpSortKey = function(rowId) {
        var publicIpCell = DOM.get(rowId + "PublicIp");
        var publicIp = publicIpCell.innerHTML.trim();

        DOM.setAttribute(publicIpCell, "sorttable_customkey", calculateIpSortKey(publicIp));
        DOM.setAttribute(publicIpCell, "title", LOCALE.maketext("Edit “[_1]”", publicIp));

        fixTableSorting(FORCE_TABLE_SORTING_INIT);
    };

    /*
     * Checks to see if there are any remaining error conditions in the ip list.
     * Clears the error status icons and inline error messages for errors that have
     * been resolved. Regroups rows with related error conditions.
     *
     * @method checkForDuplicateEntries
     */
    var checkForDuplicateEntries = function() {

        // get a list of rows with duplicate error messages

        var errorMessageRows = DOM.getElementsBy(function(el) {
            return DOM.hasClass(el, "dupError");
        }, "tr", "natlist");

        var errorMessagesToClear = [];

        var errorRowPublicIp = "";

        var getMatchingPublicIpRows = function(el) {
            var publicIpCell = DOM.get(el.id + "PublicIp");
            if (publicIpCell && publicIpCell.innerHTML.trim() === errorRowPublicIp) {
                return true;
            }
            return false;
        };

        for (var i = 0, length = errorMessageRows.length; i < length; i++) {

            errorRowPublicIp = DOM.getAttribute(errorMessageRows[i], "data-publicip");
            var matchingPublicIpRows = DOM.getElementsBy(getMatchingPublicIpRows, "tr", "natlist");
            var len = matchingPublicIpRows.length;

            // now we have a list of table rows that match the error row,
            // if there's only one row that matches clear the error message
            // otherwise, restore the error status
            if (len === 1) {
                clearStatus(matchingPublicIpRows[0].id);
                errorMessagesToClear.push(errorMessageRows[i]);
            } else {
                for (var ix = 0; ix < len; ix++) {

                    var currentRow = matchingPublicIpRows[ix];

                    // reset the error indicator
                    clearStatus(currentRow.id);
                    DOM.addClass(currentRow.id + "Status", "natError");

                    // if this is the first one in the list, skip to the
                    // next iteration
                    if (ix === 0) {
                        continue;
                    }

                    // do this here so we don't get an array
                    // out of bounds exception
                    var previousRow = matchingPublicIpRows[ix - 1];

                    // ensure that rows with matching public ips are contiguous
                    if (DOM.getNextSibling(previousRow) !== currentRow) {
                        var disorderlyRow = currentRow.parentNode.removeChild(currentRow);
                        DOM.insertAfter(disorderlyRow, previousRow);
                    }
                }

                // TODO: use temp variables? Not sure about this one. Happens once.
                if (errorMessageRows[i] !== DOM.getNextSibling(matchingPublicIpRows[ix - 1])) {
                    var disorderlyErrorRow = errorMessageRows[i].parentNode.removeChild(errorMessageRows[i]);
                    DOM.insertAfter(disorderlyErrorRow, matchingPublicIpRows[ix - 1]);
                }
                restripeNatTable();
            }
        }

        for (i = 0, length = errorMessagesToClear.length; i < length; i++) {
            errorMessagesToClear[i].parentNode.removeChild(errorMessagesToClear[i]);
        }

        fixTableSorting(FORCE_TABLE_SORTING_INIT);
    };

    /*
     * Called automatically when an attempt to validate an ip
     * address mapping is successful.This routine should not be called directly.
     * Updates the user interface appropriately.
     *
     * @method validateIpSuccess
     * @param {Object} o The data returned from the check_ip API call.
     */
    var validateIpSuccess = function(o) {
        var rowId = o.argument.rowId;
        var publicIpCell = DOM.get(rowId + "PublicIp");
        var localIp = o.argument.localIp;
        var checkedIp = o.cpanel_raw.data.checked_ip;

        if (typeof checkedIp !== "undefined" && checkedIp !== "") {
            lastNotice = new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("Address successfully validated."),
                level: "success"
            });

            // replace public ip address in table if it is incorrect
            if (publicIpCell.innerHTML.trim() !== checkedIp) {
                publicIpCell.innerHTML = checkedIp;
            }

            clearStatus(rowId);
            DOM.addClass(rowId + "Status", "natSuccess");

            setTimeout(function() {
                clearStatus(rowId);
                checkForDuplicateEntries();
            }, DEFAULT_FADE_OUT);

            updatePublicIpSortKey(rowId);
        } else {
            lastNotice = new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("“[_1]” cannot be routed.", localIp.html_encode()),
                level: "warn"
            });
            clearStatus(rowId);
            DOM.addClass(rowId + "Status", "natWarning");

            // replace IP address with not routable message
            publicIpCell.innerHTML = LOCALE.maketext("Not Routable");
        }
    };

    /*
     * Called automatically when an attempt to validate an ip
     * address mapping fails.This routine should not be called directly.
     * Updates the user interface appropriately.
     *
     * @method validateIpFailure
     * @param {Object} o The data returned from the check_ip API call.
     */
    var validateIpFailure = function(o) {

        // extract information useful to end user from diagnostic message
        var extractor = /^exit level \[die\]\s+\[pid=\d+\]\s+\((.+)\)\n*$/i;
        if (o.cpanel_error) {
            var matchResults = o.cpanel_error.match(extractor);
            var errorString = matchResults[1];
            lastNotice = new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("Cannot determine public IP address. Unable to connect to myip service."),
                level: "error",
                closable: false
            });
            showContextNotice(MESSAGE_TYPE_ERROR, LOCALE.maketext("An error has occurred: [_1]", errorString.html_encode()));
        } else {
            lastNotice = new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("Public address for “[_1]” is invalid.", o.argument.localIp.html_encode()),
                level: "error",
                closable: false
            });
        }

        if (!DOM.hasClass(o.argument.rowId + "Status", "natError")) {
            clearStatus(o.argument.rowId);
            DOM.addClass(o.argument.rowId + "Status", "natError");
            setTimeout(function() {
                clearStatus(o.argument.rowId);
            }, DEFAULT_FADE_OUT);
        }
    };

    /*
     * Checks to see if the local ip address is correctly mapped to a
     * public ip address.
     *
     * @method validateIp
     * @param {MouseEvent} The mouse event that triggered the function
     * @param {Object} rowData Row-specific data used by function (localIp, rowId)
     */
    var validateIp = function(mouseEvt, rowData) {
        var localIp = rowData.localIp;
        var row = rowData.rowId;
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Validating “[_1]”.", localIp.html_encode()),
            level: "info"
        });

        CPANEL.api({
            application: "whm",
            func: "nat_checkip",
            data: {
                ip: localIp
            },
            callback: {
                success: validateIpSuccess,
                failure: validateIpFailure,
                argument: {
                    rowId: row,
                    localIp: localIp
                }
            }
        });
    };

    /*
     * Moves the confirm/delete inline form to the
     * form dry dock, awaiting its next use.
     *
     * @method dryDockConfirmDeleteForm
     * @param {String} rowId The id for the row which contains the confirm delete form
     */
    var dryDockConfirmDeleteForm = function(rowId) {
        var editorDryDock = DOM.get("formDryDock");
        var actionsCell = DOM.get(rowId + "Actions");
        var confirmDeleteForm = actionsCell.removeChild(DOM.get("natConfirmDelete"));
        editorDryDock.appendChild(confirmDeleteForm);
        EVENT.removeListener("cancelNatEntryDelete", "click");
        EVENT.removeListener("deleteNatEntry", "click");
    };

    /*
     * Moves the edit public ip inline form to the
     * form dry dock, awaiting its next use.
     *
     * @method dryDockEditPublicIpForm
     * @param {String} rowId The id for the row which contains the edit ip form
     */
    var dryDockEditPublicIpForm = function(rowId) {
        var editorDryDock = DOM.get("formDryDock");
        var actionsCell = DOM.get(rowId + "Actions");
        var localIpSaveForm = actionsCell.removeChild(DOM.get("natPublicIpEdit"));
        editorDryDock.appendChild(localIpSaveForm);
        EVENT.removeListener("cancelIpEdit", "click");
        EVENT.removeListener("savePublicIp", "click");
    };

    /*
     * Restripes the nat list when the table's contents change.
     *
     * @method restripeNatTable
     */
    var restripeNatTable = function() {
        var tableRows = DOM.getElementsBy(function(el) {
            return !DOM.hasClass(el, "dupError");
        }, "tr", "natlist");

        for (var i = 0; i < tableRows.length; i++) {
            if (i % 2 === 0) {
                DOM.addClass(tableRows[i], "evenRow");
            } else {
                DOM.removeClass(tableRows[i], "evenRow");
            }
        }
    };

    /*
     * Called automatically when an attempt to delete an ip
     * address mapping succeeds. This routine should not be called directly.
     * Updates the user interface appropriately.
     *
     * @method ipDeleteSuccess
     * @param {Object} o The data returned from the delete ip call.
     */
    var ipDeleteSuccess = function(o) {

        var rowId = o.argument.rowId;

        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Entry for “[_1]” successfully deleted.", o.argument.localIp.html_encode()),
            level: "success"
        });

        // hide row
        DOM.addClass(rowId, "hidden");

        // remove row completely
        var row = DOM.get(rowId);
        row.parentNode.removeChild(row);

        checkForDuplicateEntries();
        restripeNatTable();
        fixTableSorting(FORCE_TABLE_SORTING_INIT);
    };

    /*
     * Called automatically when an attempt to delete an ip
     * address mapping fails. This routine should not be called directly.
     * Updates the user interface appropriately.
     *
     * @method ipDeleteFailure
     * @param {Object} o The data returned from the delete ip call.
     */
    var ipDeleteFailure = function(o) {
        var msgContent = o.cpanel_messages[0].content;
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Entry for “[_1]” not deleted.", o.argument.localIp.html_encode()),
            level: "error"
        });
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("The reported error message was: “[_1]”", msgContent.html_encode()),
            level: "error"
        });
    };

    /*
     * Attempts to delete a local ip address and the local ip mapping,
     * if in NAT mode.
     *
     * @method confirmIpDelete
     * @param {MouseEvent} mouseEvt Click event data for anchor click
     * @param {Object} rowData Row-specific data
     */
    var confirmIpDelete = function(mouseEvt, rowData) {
        var rowId = rowData.rowId;
        var localIp = rowData.localIp;
        var etherIF = rowData.etherIF;

        dryDockConfirmDeleteForm(rowId);
        showHideNatActionButtons(rowId, true);

        CPANEL.api({
            application: "whm",
            func: "delip",
            data: {
                ip: localIp,
                ethernetdev: etherIF,
                skipifshutdown: 0
            },
            callback: {
                success: ipDeleteSuccess,
                failure: ipDeleteFailure,
                argument: {
                    rowId: rowId,
                    localIp: localIp
                }
            }
        });

        rowBeingDeleted = false;
    };

    /*
     * Cancels a delete ip operation before it is actually started.
     *
     * @method cancelIpDelete
     * @param {MouseEvent} mouseEvt Click event data
     * @param {Object} rowData Row-specific data
     */
    var cancelIpDelete = function(mouseEvt, rowData) {
        var rowId = rowData.rowId;
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Operation canceled. Entry for “[_1]” not deleted.", arguments[1].localIp.html_encode()),
            level: "warn"
        });
        dryDockConfirmDeleteForm(rowId);
        showHideNatActionButtons(rowId, true);
        rowBeingDeleted = false;
    };

    /*
     * Displays the inline delete ip confirmation dialog.
     *
     * @method deleteIp
     * @param {String} localIp The local ip address to be deleted
     * @param {String} rowId The id of the table list containing the ip address
     * @param {String} etherIF The ethernet interface id
     */
    var deleteIp = function(mouseEvt, rowData) {

        var localIp = rowData.localIp;
        var rowId = rowData.rowId;
        var etherIF = rowData.etherIF;

        if (rowBeingDeleted) {
            lastNotice = new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("You are already attempting to delete an IP address in a different row. Please complete that operation before proceeding."),
                level: "warn"
            });
            return;
        } else {
            rowBeingDeleted = true;
        }
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Confirm that entry for “[_1]” should be deleted.", localIp.html_encode()),
            level: "info"
        });

        showHideNatActionButtons(rowId, false);
        var editorDryDock = DOM.get("formDryDock");
        var inlineForm = editorDryDock.removeChild(DOM.get("natConfirmDelete"));
        var actionsCell = DOM.get(rowId + "Actions");
        actionsCell.appendChild(inlineForm);

        EVENT.addListener("cancelNatEntryDelete", "click", cancelIpDelete, {
            rowId: rowId,
            localIp: localIp
        });
        EVENT.addListener("deleteNatEntry", "click", confirmIpDelete, {
            rowId: rowId,
            localIp: localIp,
            etherIF: etherIF
        });
    };

    /*
     * Toggles the visibility of the action buttons.
     *
     * @method showHideNatActionButtons
     * @param {String} rowId The id of the row containing the buttons
     * @param {Boolean} show Show (true) or hide (false) the buttons
     */
    var showHideNatActionButtons = function(rowId, show) {
        var rowActionButtons = DOM.get(rowId + "Actions");
        var buttonList = DOM.getFirstChild(rowActionButtons);
        if (show) {
            DOM.setStyle(buttonList, "display", "block");
        } else {
            DOM.setStyle(buttonList, "display", "none");
        }
    };

    /*
     * Cancels an potential ip address change before saving is attempted.
     *
     * @method cancelPublicIpChange
     * @param {MouseEvent} mouseEvt Click data for the anchor
     * @param {Object} rowData Row-specific data
     */
    var cancelPublicIpChange = function(mouseEvt, rowData) {
        var rowId = rowData.rowId;
        var savedPublicIp = rowData.savedPublicIp;

        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Operation canceled. Public IP change not saved."),
            level: "warn"
        });
        dryDockEditPublicIpForm(rowId);
        showHideNatActionButtons(rowId, true);
        var publicIpCell = DOM.get(rowId + "PublicIp");
        publicIpCell.removeChild(publicIpCell.firstChild);
        publicIpCell.innerHTML = savedPublicIp;
        rowBeingEdited = false;
    };

    /*
     * Called automatically when an attempt to save a public ip
     * address mapping succeeds. This routine should not be called directly.
     * Updates the user interface appropriately.
     *
     * @method savePublicIpChangeSuccess
     * @param {Object} o Data returned by save ip API call
     */
    var savePublicIpChangeSuccess = function(o) {
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Public IP for “[_1]” successfully changed.", o.argument.localIp.html_encode()),
            level: "success"
        });

        var rowId = o.argument.rowId;

        clearStatus(rowId);
        checkForDuplicateEntries();
        updatePublicIpSortKey(rowId);
    };

    /*
     * Called automatically when an attempt to save a public ip
     * address mapping fails. This routine should not be called directly.
     * Displays a growl-style alert.
     *
     * @method savePublicIpChangeSuccess
     * @param {Object} o Data returned by save ip API call
     */
    var savePublicIpChangeFailure = function(o) {
        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Public IP for “[_1]” not changed.", o.argument.localIp.html_encode()),
            level: "error"
        });
    };

    /*
     * Attempts to save a public ip change after it has been
     * edited in the inline editor.
     *
     * @method savePublicIpChange
     * @param {MouseEvent} mouseEvt Event data from anchor click
     * @param {Object} Row-specific data
     */
    var savePublicIpChange = function(mouseEvt, rowData) {
        var rowId = rowData.rowId;
        var localIpCell = DOM.get(rowId + "PublicIp");
        var editor = DOM.getFirstChild(localIpCell);
        var newIpValue = editor.value;
        var savedPublicIp = rowData.savedPublicIp;
        var localIp = rowData.localIp;

        localIpCell.removeChild(editor);
        EVENT.removeListener("cancelIpEdit", "click");
        EVENT.removeListener("saveEditedIp", "click");
        var actionsCell = DOM.get(rowId + "Actions");
        var doneForm = actionsCell.removeChild(DOM.get("natPublicIpEdit"));
        var editorDryDock = DOM.get("formDryDock");

        editorDryDock.appendChild(doneForm);
        showHideNatActionButtons(rowId, true);

        if (CPANEL.validate.ip(newIpValue)) {

            // check to see if there's already a mapping with
            // the edited newIpValue

            var duplicateMappingElement = DOM.getElementBy(function(el) {
                if (DOM.hasClass(el, "pubIp") && el.innerHTML.trim() === newIpValue) {
                    return true;
                }
                return false;
            }, "td", "natlist");

            if (duplicateMappingElement !== null) {

                // error notification
                lastNotice = new CPANEL.ajax.Dynamic_Notice({
                    content: LOCALE.maketext("A mapping with the public address “[_1]” already exists.", newIpValue.html_encode()),
                    level: "error"
                });
                lastNotice = new CPANEL.ajax.Dynamic_Notice({
                    content: LOCALE.maketext("Restoring previous value: [_1]", savedPublicIp.html_encode()),
                    level: "info"
                });

                // put back old ip address
                localIpCell.innerHTML = savedPublicIp;
            } else {
                localIpCell.innerHTML = newIpValue;
                CPANEL.api({
                    application: "whm",
                    func: "nat_set_public_ip",
                    data: {
                        local_ip: localIp,
                        public_ip: newIpValue
                    },
                    callback: {
                        success: savePublicIpChangeSuccess,
                        failure: savePublicIpChangeFailure,
                        argument: {
                            savedPublicIp: savedPublicIp,
                            localIp: localIp,
                            rowId: rowId
                        }
                    }
                });
            }

        } else {

            // error notification
            lastNotice = new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("“[_1]” is not a valid IP address.", newIpValue.html_encode()),
                level: "error"
            });

            // put back old ip address
            localIpCell.innerHTML = savedPublicIp;
        }
        rowBeingEdited = false;
    };

    /*
     * Displays the inline public ip address editor.
     *
     * @method editPublicIp
     * @param {MouseEvent} mouseEvt The mouse click that triggered the method
     * @param {Object} rowData Row-specific data (rowId, localIp)
     */
    var editPublicIp = function(mouseEvt, rowData) { // localIp, rowId) {
        var rowId = rowData.rowId;
        var localIp = rowData.localIp;
        if (rowBeingEdited) {
            lastNotice = new CPANEL.ajax.Dynamic_Notice({
                content: LOCALE.maketext("You are already editing a public IP address in a different row. Please complete that operation before proceeding."),
                level: "warn"
            });
            return;
        } else {
            rowBeingEdited = true;
        }

        lastNotice = new CPANEL.ajax.Dynamic_Notice({
            content: LOCALE.maketext("Editing public IP for “[_1]”.", localIp.html_encode()),
            level: "info"
        });

        var publicIpCell = DOM.get(rowId + "PublicIp");
        var publicIpValue = publicIpCell.innerHTML.trim();
        publicIpCell.innerHTML = "";

        // TODO: add generic editor to form dry dock instead of this
        var editor = document.createElement("input");
        editor.setAttribute("type", "text");
        editor.setAttribute("value", publicIpValue);
        editor.setAttribute("size", "16");
        editor.setAttribute("maxlength", "16");
        publicIpCell.appendChild(editor);
        editor.focus();
        editor.select();

        // switch out the actions for the
        // editor buttons
        showHideNatActionButtons(rowId, false);
        var editorDryDock = DOM.get("formDryDock");
        var publicIpSaveForm = editorDryDock.removeChild(DOM.get("natPublicIpEdit"));
        DOM.get(rowId + "Actions").appendChild(publicIpSaveForm);
        EVENT.addListener("cancelIpEdit", "click", cancelPublicIpChange, {
            savedPublicIp: publicIpValue,
            rowId: rowId
        });
        EVENT.addListener("saveEditedIp", "click", savePublicIpChange, {
            localIp: localIp,
            savedPublicIp: publicIpValue,
            rowId: rowId
        });
    };

    /**
     * Sets up button listeners so the proper functions get called.
     *
     * @method addButtonListeners
     */
    var addButtonListeners = function() {

        // get a list of non header table rows
        // also skip over dup error rows
        var tableRows = DOM.getElementsBy(function(el) {
            return el.tagName === "TR" && DOM.getFirstChild(el).tagName !== "TH" && !DOM.hasClass(el, "dupError");
        }, "tr", "natlist");

        // the following three functions find the
        // correct "button" to which to attach the
        // respective listener
        var findValidateButton = function(el) {
            return DOM.hasClass(el, "validateMappingBtn");
        };

        var findEditButton = function(el) {
            return DOM.hasClass(el, "editMappingBtn");
        };

        var findDeleteButton = function(el) {
            return DOM.hasClass(el, "deleteMappingBtn");
        };

        for (var i = 0, length = tableRows.length; i < length; i++) {
            var rowId = tableRows[i].id;

            // var publicIp = DOM.get(rowId + "PublicIp").innerHTML.trim();
            var localIp = DOM.get(rowId + "LocalIp").innerHTML.trim();
            var etherIF = DOM.get(rowId + "If").innerHTML.trim();

            var validateBtn = DOM.getElementBy(findValidateButton, "a", tableRows[i]);
            if (validateBtn) {
                EVENT.addListener(validateBtn, "click", validateIp, {
                    rowId: rowId,
                    localIp: localIp
                });
            }

            var editBtn = DOM.getElementBy(findEditButton, "a", tableRows[i]);
            if (editBtn) {
                EVENT.addListener(editBtn, "click", editPublicIp, {
                    rowId: rowId,
                    localIp: localIp
                });
            }

            var deleteBtn = DOM.getElementBy(findDeleteButton, "a", tableRows[i]);
            if (deleteBtn) {
                EVENT.addListener(deleteBtn, "click", deleteIp, {
                    rowId: rowId,
                    localIp: localIp,
                    etherIF: etherIF
                });
            }
        }
    };

    /*
     * Initializes page-specific object.
     *
     * @method initialize
     */
    var initialize = function() {
        EVENT.addListener("contextNoticeClose", "click", hideContextNotice);
        var tableDimensions = DOM.getRegion("natlist");

        // set the size of the notices box to match the width of the ip
        // list table (looks better that way)
        DOM.setStyle("ipnotices", "width", tableDimensions.width + "px");
        EVENT.addListener("tableHeader", "click", restripeNatTable);
        fixTableSorting(SKIP_TABLE_SORTING_INIT);
        addButtonListeners();
    };

    EVENT.onDOMReady(initialize);

}());
