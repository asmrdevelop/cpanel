CPANEL.namespace("CPANEL.App");

/**
 * The Restore module provides methods to restore accounts by username and date
 *
 * NOTE: Inherited from previous developer. Due to time constraints addressed TODO items
 * that caused functional breaks or fatal problems. Remaining TODO items should be
 * evaluated and reworked when possible.
 *
 * @module Restore
 *
 */
CPANEL.App.Restore = (function() {

    // workaround for a datetime fix that's going in with the ssl improvements
    // 11.36 -- this does not expect a UTC date.  Ref: Felipe Gasper
    if (!("local_datetime" in LOCALE)) {
        LOCALE.local_datetime = LOCALE.datetime;
    }

    /* Define variables global to this scope -- assigned in the init method */
    var SELECTOR = YAHOO.util.Selector,
        EVENT = YAHOO.util.Event,
        DOM = YAHOO.util.Dom,
        PAGE = CPANEL.PAGE,
        POLL_INTERVAL = 5000,
        pollQueue = false,
        callbackCounter = 0,
        checkQueueOnceMore = false,
        restoreButton,
        dateListArray,
        userSelection,
        restoreUser,
        restoreUserList,
        restorePoint,
        restoreCalendar,
        restoreForm,
        userFilter,
        addUserButton,
        clearFilterEl,
        restoreTable,
        rowContainerTemplate,
        noItemsTemplate,
        statusTemplate,
        rowTemplate,
        selectingByUser,
        dateListArr,
        dateListShort,
        userListArray,
        userListSize,
        validSet,
        calendar,
        userListEls,
        lastFocusMenu,
        lastFocusUser,
        noticeArea;

    /**
     * Sets a notice in the notification area
     *
     * @method setNotice
     * @param level text (error, info, warn, success)
     * @param msg string notice text -- remember to localize first!
     */

    function setNotice(level, msg) {
        CPANEL.Form.purgeContainer(noticeArea);
        noticeArea.innerHTML = YAHOO.lang.substitute(statusTemplate, {
            type: level,
            message: msg
        });
        EVENT.addListener("close_notice", "click", function() {
            CPANEL.Form.purgeContainer(noticeArea);
        });
    }

    /**
     * Validate a valid user selection and date selection
     * set the disabled state of the "add to queue" button accordingly
     *
     * @method validateQueueButton
     */

    function validateQueueButton() {
        var validUser = restoreUser.value !== "",
            validDate = restorePoint.value !== "";
        addUserButton.disabled = (validUser && validDate) ? false : true;
    }

    /**
     * Put the user list first (select by account)
     *
     * @method selectByAccount
     */

    function selectByAccount(e) {
        if (e) {
            EVENT.preventDefault(e);
        }
        if (!selectingByUser) {
            var parentDiv = DOM.get("tab_area");
            var restoreSelection = DOM.get("restore_selection");
            var userSelection = DOM.get("user_selection");
            var restoreOptions = DOM.get("restore_options");
            DOM.addClass("select-by-account", "active");
            DOM.removeClass("select-by-date", "active");
            parentDiv.removeChild(restoreSelection);
            parentDiv.removeChild(userSelection);
            parentDiv.insertBefore(userSelection, restoreOptions);
            parentDiv.insertBefore(restoreSelection, restoreOptions);
            selectingByUser = true;
            buildCalendar(calendar);
            filterUserList();
            validateQueueButton();
            DOM.removeClass(restoreCalendar, "workflow-focus");
            DOM.addClass(userSelection, "workflow-focus");
            userFilter.focus();
        }
    }

    /**
     * Put the date list first (select by date)
     *
     * @method selectByDate
     */

    function selectByDate(e) {
        if (e) {
            EVENT.preventDefault(e);
        }
        if (selectingByUser) {
            var parentDiv = DOM.get("tab_area");
            var restoreSelection = DOM.get("restore_selection");
            var userSelection = DOM.get("user_selection");
            var restoreOptions = DOM.get("restore_options");
            DOM.removeClass("select-by-account", "active");
            DOM.addClass("select-by-date", "active");
            parentDiv.removeChild(restoreSelection);
            parentDiv.removeChild(userSelection);
            parentDiv.insertBefore(restoreSelection, restoreOptions);
            parentDiv.insertBefore(userSelection, restoreOptions);
            selectingByUser = false;
            buildCalendar(calendar, dateListShort);
            focusLastSelectableDay();
            DOM.addClass(restoreCalendar, "workflow-focus");
            DOM.removeClass(userSelection, "workflow-focus");
            filterUserList();
            clearRestoreFromMenu();
        }
    }

    /**
     * Prepares for and sets focus on the next step after user selection
     *
     * @method nextWorkflowStep
     * @param {Event} e The event object
     */

    function nextWorkflowStep(e) {

        // check form values before proceeding
        validateQueueButton();

        DOM.removeClass(userSelection, "workflow-focus");
        if (selectingByUser) {
            var target = e.target || e.srcElement,
                userArrayIndex = getUserIndex(target.id);
            if (userArrayIndex >= 0) {

                // with a large number of destinations, the
                // list of backup dates becomes very large, which
                // seems to confuse the calendar widget, so pass
                // a list of unique dates to the calendar instead
                var dateList = userListArray[userArrayIndex].backup_date;
                var uniqueDateList = dateList.filter(function(item, idx, ar) {
                    return ar.indexOf(item) === idx;
                });
                buildCalendar(calendar, uniqueDateList);
                DOM.addClass(restoreCalendar, "workflow-focus");
                focusLastSelectableDay();
            }
        } else {
            addUserButton.focus();
        }
    }

    /**
     * Returns the array index of the user from the userListArray
     *
     * @method getUserIndex
     * @param {string} id The id of the user to retrieve an array index for
     */

    function getUserIndex(id) {
        for (var i = 0, length = userListArray.length; i < length; i++) {
            if (id === userListArray[i].user) {
                return i;
            }
        }
        return -1; // no user was found
    }

    /**
     * Determines if the supplied user item is active and not hidden
     *
     * @method isActive
     * @param {HTMLElement} user The user element to test
     * @return {Boolean} returns false if the user is disabled or is hidden
     */

    function isActive(user) {
        if (DOM.hasClass(user, "disabled-list") || DOM.hasClass(user, "hidden")) {
            return false;
        }
        return true;
    }

    /**
     * Handles user selection from the user list and sets the form value for user
     *
     * @method selectUser
     * @param {event} e event object
     */

    function selectUser(e) {
        var target = e.target || e.srcElement,
            keySelect = e.keySelect || false;
        if (isActive(target)) {
            var currentlySelected = DOM.getElementsByClassName("selected-list", "span", restoreUserList);

            // make the new user selection
            restoreUser.value = target.id;
            DOM.removeClass(currentlySelected, "selected-list");
            DOM.addClass(target, "selected-list");

            // clear the restore date if user changes when
            // selecting by user

            if (selectingByUser) {
                restorePoint.value = "";
            }

            // update the restore from menu when the user changes
            updateRestoreFromMenu(restorePoint.value);

            // only fire nextWorkflowStep if this is a mouse event
            if (!keySelect) {
                nextWorkflowStep(e);
            }
        }
    }

    /**
     * Handles user selection via keyboard and calls selectUser with the new selection
     *
     * @method keyboardSelectUser
     * @param {string} e event name
     * @param {array} key key listener array containing key pressed and event information
     */

    function keyboardSelectUser(e, key) {
        var selected = DOM.getElementsByClassName("selected-list", "span", restoreUserList)[0],
            newSelection,
            keyPressed = key[0],
            keyEvent = key[1];
        if (selected) {
            if (keyPressed === 40) {

                // scroll user list down
                newSelection = DOM.getNextSiblingBy(selected, isActive);
                if (!newSelection) {
                    newSelection = DOM.getFirstChildBy(restoreUserList, isActive);
                }
                newSelection.scrollIntoView(false);
            } else if (keyPressed === 38) {

                // scroll user list up
                newSelection = DOM.getPreviousSiblingBy(selected, isActive);
                if (!newSelection) {
                    newSelection = DOM.getLastChildBy(restoreUserList, isActive);
                }
                newSelection.scrollIntoView(false);
            } else {

                // on any other key action with a selected item focus the next step
                EVENT.preventDefault(keyEvent);
                nextWorkflowStep({
                    target: selected
                });
            }
        } else {
            if (keyPressed === 40) {

                // select first user in the list
                newSelection = DOM.getFirstChildBy(restoreUserList, isActive);
                if (newSelection) {
                    newSelection.scrollIntoView(false);
                }
            } else if (keyPressed === 38) {

                // select last user in the list
                newSelection = DOM.getLastChildBy(restoreUserList, isActive);
                if (newSelection) {
                    newSelection.scrollIntoView(false);
                }
            }
        }
        if (newSelection) {
            selectUser({
                target: newSelection,
                keySelect: true
            });
        }
    }

    /**
     * Focus the most recent selectable date on the calendar
     *
     * @method focusLastSelectableDay
     */

    function focusLastSelectableDay() {
        var i,
            userListArrLength = userListArray.length,
            selectedUser = -1,
            user = restoreUser.value,
            selectableDates = {},
            selectableDatesLength;

        for (i = 0; i < userListArrLength; i++) {
            if (userListArray[i].user === user) {
                selectedUser = i;
                break;
            }
        }

        if (selectedUser >= 0) {
            validateQueueButton();
            selectableDates = DOM.getElementsByClassName("selector", "a", "restore_calendar");
            selectableDatesLength = selectableDates.length;
            if (selectableDatesLength > 0) {
                selectableDates[selectableDatesLength - 1].focus();
            }
        }
    }

    /**
     * Filter the user select element using the expression defined in the filter element
     *
     * @method filterUserList
     * @param {boolean} doNotClearSelect (will not clear a selected item)
     */

    function filterUserList(doNotClearSelect) {

        // todo: if only 1 match, automatically select it. (testing required)
        if (userFilter.value) {
            DOM.addClass("clear_user_filter", "inline-block");
        } else {
            DOM.removeClass("clear_user_filter", "inline-block");
        }
        var activeQueue = DOM.getElementsByClassName("delete-queue", "BUTTON", "table_data"),
            activeQueueSize = activeQueue.length,
            filterStr = new RegExp(userFilter.value, "i"),
            userListShort = [],
            queueIterator,
            length,
            i;
        if (!selectingByUser) {
            for (i = 0, length = dateListArray.length; i < length; i++) {
                if (dateListArray[i].backup_date === restorePoint.value) {
                    userListShort = dateListArray[i].user;
                    break;
                }
            }
        }
        for (i = 0; i < userListSize; i++) {
            var currentListElement = userListEls[i];
            if (!doNotClearSelect) {
                DOM.removeClass(currentListElement, "selected-list");
                restoreUser.value = "";
            }
            if (!filterStr.test(userListArray[i].user)) {
                DOM.addClass(currentListElement, "hidden");
            } else {
                DOM.removeClass(currentListElement, "hidden");
            }
            DOM.removeClass(currentListElement, "disabled-list");
            if (!selectingByUser && userListShort.indexOf(userListArray[i].user) < 0) {
                DOM.addClass(currentListElement, "disabled-list");
                continue;
            }
            for (queueIterator = 0; queueIterator < activeQueueSize; queueIterator++) {
                if (userListArray[i].user === activeQueue[queueIterator].id.replace(/^remove_/i, "")) {
                    DOM.addClass(currentListElement, "disabled-list");
                }
            }
        }
    }

    /**
     * Custom calendar rendering for days for which a backup is available.
     *
     * @method availableBackupDay
     * @param {String} workingDate The numerical day to be rendered
     * @param {HTMLElement} cell The table cell that holds the selectable day to be rendered
     */

    function availableBackupDay(workingDate, cell) {
        var availableDay = document.createElement("a");
        DOM.setAttribute(availableDay, "href", "");
        DOM.addClass(availableDay, this.Style.CSS_CELL_SELECTOR);
        availableDay.innerHTML = this.buildDayLabel(workingDate);
        cell.innerHTML = ""; // remove the non-breaking space already in the cell
        cell.appendChild(availableDay);
        DOM.addClass(cell, "selectable");
        return YAHOO.widget.Calendar.STOP_RENDER;
    }

    /**
     * Clear any extra items in the restore from menu, leaving menu with one
     * item ("Local") and disabled.
     *
     * @method clearRestoreFromMenu
     */

    function clearRestoreFromMenu() {
        var destinationsMenu = document.getElementById("destination_select");

        // remove all menu items except the first one from the menu

        var localOption = destinationsMenu.options[0];
        destinationsMenu.options.length = 0;
        destinationsMenu.add(localOption);
        localOption.selected = true;

        localOption.disabled = true;
        localOption.className = "disabled";

        destinationsMenu.disabled = true;
        DOM.addClass(destinationsMenu, "disabled");
    }

    /**
     * Update restore from menu to include available backups for a given user
     * and date.
     * @method updateRestoreFromMenu
     */

    function updateRestoreFromMenu(selectedDate) {

        /* You clicked on something other than a user.
         * Also, I know what you are about to say, and no, you can't name a
         * user 'restore_user_list'.
         * 1) it is too long
         * 2) can't use dashes.
         * */
        if ( typeof restoreUser.value === "undefined" || restoreUser.value === "restore_user_list" ) {
            return;
        }

        var remoteBackupsForSelectedUser = CPANEL.PAGE.users[restoreUser.value].filter(function(element) {
            return element.when === selectedDate;
        });

        clearRestoreFromMenu();

        if (remoteBackupsForSelectedUser.length === 0) {
            return;
        }

        var destinationsMenu = document.getElementById("destination_select");

        // add any existing remote backups to the menu

        var backupsForSelectedDay = 0;
        var localBackupExists = false;

        var sortedMenuItems = [];

        for (var i = 0; i < remoteBackupsForSelectedUser.length; i++) {
            if (remoteBackupsForSelectedUser[i].when === selectedDate) {
                backupsForSelectedDay++;

                if (remoteBackupsForSelectedUser[i].where === "local") {
                    localBackupExists = true;
                    continue;
                }

                var newMenuItem = document.createElement("option");
                var remoteBackup = PAGE.destinations[remoteBackupsForSelectedUser[i].where];
                newMenuItem.value = remoteBackupsForSelectedUser[i].where;
                newMenuItem.text = remoteBackup.name + " (" + remoteBackup.type + ")";
                sortedMenuItems.push(newMenuItem);
            }
        }

        sortedMenuItems.sort(function(menuItemA, menuItemB) {
            return menuItemA.text.localeCompare(menuItemB.text);
        });

        sortedMenuItems.forEach(function(menuItemToAdd) {
            destinationsMenu.add(menuItemToAdd);
        });

        if (backupsForSelectedDay > 0) {
            destinationsMenu.disabled = false;
            DOM.removeClass(destinationsMenu, "disabled");
            if (localBackupExists) {
                destinationsMenu.options[0].selected = true;
                destinationsMenu.options[0].disabled = false;
                destinationsMenu.options[0].className = "";
            } else {
                destinationsMenu.options[1].selected = true;
            }
        }
    }

    /**
     * Select handler for YUI calendar to populate the hidden restore_point field
     *
     * @method selectAvailableBackup
     */

    function selectAvailableBackup(type, args) {
        restorePoint.value = apiDate(args[0][0]);
        validateQueueButton();
        if (selectingByUser) {
            DOM.removeClass(restoreCalendar, "workflow-focus");
            addUserButton.focus();
            updateRestoreFromMenu(restorePoint.value);
        } else {
            DOM.removeClass(restoreCalendar, "workflow-focus");
            DOM.addClass(userSelection, "workflow-focus");

            // clear selected user and restore from
            // menu when date changes
            restoreUser.value = "";
            clearRestoreFromMenu();
            filterUserList();
            userFilter.focus();
        }
        validateQueueButton();
    }

    /**
     * Populates a calendar with the dates supplied
     *
     * @method buildCalendar
     * @param {Object} calendar The YUI calendar object to build
     * @param {Array} [dateArray=[]] The list of selectable dates for the calendar
     */

    function buildCalendar(calendar, dateArray) {
        dateArray = typeof dateArray !== "undefined" ? dateArray : [];
        var dateArrayLength = dateArray.length,
            lastAvailableIndex = 0, // when selecting by date most recent backup is first
            lastAvailableDay,
            i;

        // reset the value of the hidden field when calendar is rebuilt
        restorePoint.value = "";

        if (dateArrayLength > 0) {
            lastAvailableIndex = dateArrayLength - 1; // most recent backup is last
            lastAvailableDay = dateArray[lastAvailableIndex].split("-");
            calendar.cfg.setProperty("pagedate", lastAvailableDay[1] + "/" + lastAvailableDay[0]);
        }

        for (i = 1; i < 8; i++) {
            calendar.addWeekdayRenderer(i, calendar.renderOutOfBoundsDate);
        }

        for (i = 0; i < dateArrayLength; i++) {
            calendar.addRenderer(yuiCalendarDate(dateArray[i]), availableBackupDay);
        }

        calendar.cfg.setProperty("navigator", true);
        calendar.render();

        if (selectingByUser) {
            DOM.removeClass(restoreCalendar, "workflow-focus");
        } else {
            DOM.addClass(restoreCalendar, "workflow-focus");
        }
    }

    /**
     * Convert data returned by new API call to legacy format so
     * calendar works.
     *
     * @method buildUserListArray
     */

    function buildUserListArray() {
        var justUsers = Object.keys(PAGE.users).sort();
        var massagedUserList = [];

        justUsers.forEach(function(userName) {
            var userData = PAGE.users[userName];
            var backupDates = [];
            userData.forEach(function(backupDate) {
                backupDates.push(backupDate.when);
            });
            var userObj = { user: userName,
                backup_date: backupDates.sort()
            };
            massagedUserList.push(userObj);
        });

        userListSize = massagedUserList.length;

        return massagedUserList;
    }

    /**
     * Accepts a string or date object and returns a formatted string for YUI Calendar.
     *
     * @method yuiCalendarDate
     * @param {String|Object} date A string in the format YYYY-MM-DD or Date object
     * @return {String} A date string in the format MM/DD/YYYY
     */

    function yuiCalendarDate(date) {
        var dateArray = [];
        if (typeof date === "string") {
            dateArray = date.split("-");

            // construct the date object, note that months go from 0-11
            date = new Date(dateArray[0], dateArray[1] - 1, dateArray[2]);
        }

        // getMonth() returns 0-11 so add 1 to the month
        return date.getMonth() + 1 + "/" + date.getDate() + "/" + date.getFullYear();
    }

    /**
     * Accepts a YUI Calendar date and returns a formatted string for the api.
     *
     * @method apiDate
     * @param {Array} date An array containing pieces of a YUI Date [YYYY,MM,DD]
     * @return {String} A date string in the format YYYY-MM-DD
     */

    function apiDate(date) {

        // pad month and days less than 10 with a 0 to ensure it matches the backup folder name
        if (date[1] < 10) {
            date[1] = "0" + date[1];
        }
        if (date[2] < 10) {
            date[2] = "0" + date[2];
        }
        return date[0] + "-" + date[1] + "-" + date[2];
    }

    /**
     * Adds the selected user to the Queue.  This is called by a click event
     * on the "Add user to queue" button.
     *
     * @method addToQueue
     */

    function addToQueue() {
        var formData = CPANEL.Form.getData(restoreForm);

        if (!formData.user) {
            return;
        }

        // set the spinner and notice
        CPANEL.Form.toggleLoadingButton(addUserButton);
        setNotice("info", LOCALE.maketext("Adding “[_1]” to the restoration queue …", formData.user));

        CPANEL.api({
            func: "restore_queue_add_task",
            data: formData,
            callback: {
                success: function() {
                    var newRecord = {
                        user: formData.user,
                        restore_point: formData.restore_point,
                        options: {
                            subdomains: formData.subdomains,
                            mail_config: formData.mail_config,
                            mysql: formData.mysql,
                            give_ip: formData.give_ip,
                            destid: formData.destid
                        }
                    };
                    PAGE.queue.push(newRecord);

                    // reset calendar and user
                    calendar.clear();
                    if (selectingByUser) {
                        buildCalendar(calendar);
                    } else {
                        buildCalendar(calendar, dateListShort);
                    }
                    var selectedUser = DOM.getElementsByClassName("selected-list", "span", "restore_user_list");
                    DOM.removeClass(selectedUser, "selected-list");
                    restoreUser.value = "";
                    clearRestoreFromMenu();
                    buildQueue();
                    CPANEL.Form.purgeContainer(noticeArea);
                    CPANEL.Form.toggleLoadingButton(addUserButton);

                    // disable add user button until user selects user and date
                    addUserButton.disabled = true;
                    addUserButton.blur();
                    restoreButton.disabled = false;
                },
                failure: function(o) {
                    if (!("cpanel_error" in o)) {
                        if ("statusText" in o && o.statusText === "communication failure") {
                            o.cpanel_error = LOCALE.maketext("Your browser may have blocked the request, or your connection may be unstable");
                        } else {
                            o.cpanel_error = LOCALE.maketext("Unknown Error");
                        }
                    }
                    CPANEL.Form.toggleLoadingButton(addUserButton);
                    addUserButton.disabled = true;
                    addUserButton.blur();
                    buildQueue();
                    setNotice("error", LOCALE.maketext("Could not add “[_1]” to the restoration queue ([_2]).", formData.user, o.cpanel_error.html_encode()));

                    // enable the user if the queue add failed
                    var node = DOM.get(formData.user);
                    if (node) {
                        DOM.removeClass(node, "disabled-list");
                    }
                }
            }
        });
    }

    /**
     * This is an event handler for when the "remove" link is pressed on a
     * queue item.   It removes the user from the queue and activates
     * their user select box line.
     *
     * @method removeQueueItem
     * @param {event} the Event Object
     */

    function removeQueueItem(e) {

        // normalize the target element.
        var target = e.srcElement || e.target,
            node = DOM.getAncestorByTagName(target, "tr"),
            id = target.id.replace(/^remove_/i, ""); // get the user name embedded in the id.

        EVENT.preventDefault(e);

        var actionCell = DOM.getAncestorByClassName(target, "row-actions");
        DOM.addClass(actionCell, "row-loading");

        // replace the table row with the removal notice (info)
        if (DOM.hasClass(target, "delete-finished")) {
            var user = PAGE.finished[id].restore_job.user,
                started = PAGE.finished[id].status_info.started;

            CPANEL.api({
                func: "restore_queue_clear_completed_task",
                data: {
                    user: user,
                    start_time: started
                },
                callback: {
                    success: function() {
                        node.parentNode.removeChild(node);
                        PAGE.finished.splice(id, 1);
                        CPANEL.Form.purgeContainer(noticeArea);
                        buildQueue();
                    },
                    failure: function(o) {
                        DOM.removeClass(actionCell, "row-loading");

                        if (!("cpanel_error" in o)) {
                            o.cpanel_error = LOCALE.maketext("Unknown Error");
                        }
                        setNotice("error", LOCALE.maketext("Could not remove “[_1]” from the finished list ([_2]).", user, o.cpanel_error.html_encode()));
                    }
                }
            });
        } else {
            CPANEL.api({
                func: "restore_queue_clear_pending_task",
                data: {
                    user: id
                },
                callback: {
                    success: function() {
                        var i; // increment counter;
                        var listSize = userListEls.length;

                        // remove the table row.
                        node.parentNode.removeChild(node);

                        // reactivate the select box option
                        for (i = listSize - 1; i >= 0; i--) {
                            if (userListEls[i].id === id) {
                                DOM.removeClass(userListEls[i], "disabled-list");
                                break;
                            }
                        }
                        for (i = PAGE.queue.length - 1; i >= 0; i--) {
                            if (PAGE.queue[i].user === id) {
                                PAGE.queue.splice(i, 1);
                                break;
                            }
                        }
                        CPANEL.Form.purgeContainer(noticeArea);
                        buildQueue();
                    },
                    failure: function(o) {
                        DOM.removeClass(actionCell, "row-loading");
                        if (!("cpanel_error" in o)) {
                            o.cpanel_error = LOCALE.maketext("Unknown Error");
                        }
                        setNotice("error", LOCALE.maketext("Could not remove “[_1]” from the restoration queue ([_2]).", id, o.cpanel_error.html_encode()));
                    }
                }
            });
        }
    }

    /**
     * This is an event handler for when the "remove" link is pressed on a
     * queue item.   It removes the user from the queue and activates
     * their user select box line.
     *
     * @method viewQueueItemLog
     * @param {event} the Event Object
     */

    function viewQueueItemLog(e) {

        // normalize the target element.
        var target = e.srcElement || e.target,
            node = DOM.getAncestorByTagName(target, "tr"),
            id = target.id.replace(/^remove_/i, ""); // get the user name embedded in the id.

        EVENT.preventDefault(e);

        var idnum = id.split("_");
        var i = idnum[1];
        var finishedJob = PAGE.finished[i];

        if ( !finishedJob || !finishedJob.status_info || !finishedJob.status_info.transfer_session_id ) {
            alert(LOCALE.maketext("No log is available because the restore failed."));
        } else {
            if ( finishedJob.status_info.restore_logfile ) {

                window.open("../scripts5/render_transfer_log?transfer_session_id=" + encodeURIComponent( finishedJob.status_info.transfer_session_id ) + "&log_file=" + encodeURIComponent( finishedJob.status_info.restore_logfile ) );
            } else {
                window.open("../scripts5/transfer_session?transfer_session_id=" + encodeURIComponent( finishedJob.status_info.transfer_session_id ) );
            }
        }
    }

    /**
     * Generate a display name for a given destination id.
     *
     * @method destinationDisplayName
     * @param {string} destId destination key
     */

    function destinationDisplayName(destId) {
        if ( typeof destId === "undefined" ) {

            // If there is no destination ID associated, it's likely a local backup
            return "Local";
        }
        var destination = PAGE.destinations[destId];
        return destId === "local" ? "Local" : destination.name + " (" + destination.type + ")";
    }

    /**
     * We build the queue here.
     *
     * @method buildQueue
     * @param {boolean} noFilter true if we don't want to call filterUserList()
     */

    function buildQueue(noFilter) {
        var newTableContainer = document.createElement("div"),
            restoreTableBody = DOM.get("table_data"),
            tableRows = "",
            totalRows = 0,
            uId = 0,
            newTableBody,
            length,
            i;

        disableRestoreButton = true;
        for (i = 0, length = PAGE.active.length; i < length; i++, uId++) {
            var activeJob = PAGE.active[0];
            tableRows += YAHOO.lang.substitute(rowTemplate, {
                row_id: uId,
                rowClass: "table-row-stripe-odd",
                user: activeJob.user,
                date: findLocaleDate(activeJob.restore_point.split("-")),
                source: destinationDisplayName(activeJob.options.destid),
                status: LOCALE.maketext("Restoring Account"),
                statusImage: PAGE.activeImage,
                viewButtonClass: "hidden",
                clearButtonClass: "hidden",

                // TODO: set PAGE.active in a static var
                statusId: "active_" + activeJob.user,
                id: activeJob.user
            });
            totalRows++;
        }

        for (i = 0, length = PAGE.queue.length; i < length; i++, uId++) {
            var queuedJob = PAGE.queue[i];
            tableRows += YAHOO.lang.substitute(rowTemplate, {
                row_id: uId,
                rowClass: (uId % 2 === 1) ? "table-row-stripe-even" : "table-row-stripe-odd",
                user: queuedJob.user,
                date: findLocaleDate(queuedJob.restore_point.split("-")),
                source: destinationDisplayName(queuedJob.options.destid),
                status: LOCALE.maketext("Pending"),
                statusImage: PAGE.pendingImage,
                statusId: "queued_" + queuedJob.user,
                viewButtonClass: "hidden",
                clearButtonClass: "delete-link delete-queue",
                id: queuedJob.user
            });
            totalRows++;
            disableRestoreButton = false;
        }
        for (i = 0, length = PAGE.finished.length; i < length; i++, uId++) {
            var finishedJob = PAGE.finished[i];
            tableRows += YAHOO.lang.substitute(rowTemplate, {
                row_id: uId,
                rowClass: (uId % 2 === 1) ? "table-row-stripe-even" : "table-row-stripe-odd",
                user: finishedJob.restore_job.user,
                date: findLocaleDate(finishedJob.restore_job.restore_point.split("-")),
                source: destinationDisplayName(finishedJob.restore_job.options.destid),
                status: finishedJob.status_info.result === 2 ? LOCALE.maketext("Completed with warnings") : finishedJob.status_info.result ? LOCALE.maketext("Completed") : LOCALE.maketext("Failed"),
                statusImage: finishedJob.status_info.result === 2 ? PAGE.warningImage : finishedJob.status_info.result ? PAGE.successImage : PAGE.errorImage,
                statusId: "finished_" + finishedJob.restore_job.user,
                viewButtonClass: "view-link view-finished",
                clearButtonClass: "delete-link delete-finished",
                id: i
            });
            totalRows++;
            if (!finishedJob.status_info.result) {
                var logMsg = finishedJob.status_info.log ? finishedJob.status_info.log.replace(/\n/g, "<br/>\n") : LOCALE.maketext("The log file for the restore of user “[_1]” is empty.", finishedJob.restore_job.user );
                tableRows += YAHOO.lang.substitute(statusTemplate, {
                    type: "error",
                    message: LOCALE.maketext("Could not restore account “[_1]”: [_2]", finishedJob.restore_job.user, logMsg.html_encode()),
                    user: finishedJob.restore_job.user,
                    time: finishedJob.status_info.started
                });
                totalRows++;
            }
        }
        if (totalRows === 0) {

            // If no items to restore append the no items template to the table rows
            tableRows += noItemsTemplate;
        }
        restoreButton.disabled = disableRestoreButton;

        // build new table body and swap it with the existing table body
        newTableContainer.innerHTML = YAHOO.lang.substitute(rowContainerTemplate, {
            content: tableRows
        });
        newTableBody = SELECTOR.query(".row-container", newTableContainer, true);
        newTableBody.id = "table_data";
        restoreTable.replaceChild(newTableBody, restoreTableBody);

        if (!noFilter) {
            filterUserList();
        }

        // table action and notice listeners
        EVENT.on(DOM.getElementsByClassName("delete-link", "button", "table_data"), "click", removeQueueItem);
        EVENT.on(DOM.getElementsByClassName("view-link", "button", "table_data"), "click", viewQueueItemLog);
        EVENT.on(DOM.getElementsByClassName("close", "div", "table_data"), "click", clearNotice);
    }

    /**
     * Clears an error notice in the finished portion of the list.
     *
     * @method clearNotice
     * @param {event} e the event object
     */

    function clearNotice(e) {
        var target = e.target || e.srcElement,
            user = DOM.getAttribute(target, "user"),
            time = DOM.getAttribute(target, "time"),
            statusRow = DOM.getAncestorByTagName(target, "tr");

        // remove the status row
        statusRow.parentNode.removeChild(statusRow);
    }

    /**
     * Accepts an array [full year, month, date]
     * returns the toLocaleDateString value of the date.
     *
     * @method findLocaleDate
     * @param {array} dateArray [ full year, month, date]
     */

    function findLocaleDate(dateArray) {
        var localeDate = new Date(dateArray[0], dateArray[1] - 1, dateArray[2]);
        return LOCALE.local_datetime(localeDate, "date_format_full");
    }


    /**
     * Use the users object to build a dateListArr which has
     * dates->users instead of users->dates.
     *
     * @method buildDateList
     */

    function buildDateList() {

        // empty closure scoped arrays
        dateListArray = [];
        dateListShort = [];

        // iterate over PAGE.users

        var userNames = Object.keys(PAGE.users);

        for (var unIdx = 0; unIdx < userNames.length; unIdx++)  {
            var userName = userNames[unIdx];
            if (PAGE.users.hasOwnProperty(userName)) {
                PAGE.users[userName].forEach(function(arrayItem) {
                    if (!dateListShort.includes(arrayItem.when)) {
                        dateListShort.push(arrayItem.when);
                        dateListArray.push({ backup_date: arrayItem.when, user: [userName] });
                    } else {

                        // find item in dateListArray that matches
                        // the given date

                        var dateListElement = dateListArray.find(function(element) {
                            return element.backup_date === arrayItem.when;
                        });

                        if (typeof dateListElement !== "undefined" &&
                            !dateListElement.user.includes(userName)) {
                            dateListElement.user.push(userName);
                        }
                    }
                });

                dateListShort.sort();
            }
        }

        // don't sort if the array is empty
        if (dateListArray.length > 0) {
            dateListArray.sort_by("backup_date");
        }
    }

    /**
     * Clears the input filter element and calls the filter method
     *
     * @method clearFilter
     */

    function clearFilter() {
        userFilter.value = "";
        filterUserList();
    }

    /**
     * Toggle the table clear menu (activated by the "gear" icon)
     *
     * @method toggleActions
     */

    function toggleActions(e) {
        if (e) {
            EVENT.preventDefault(e);
        }
        validateQueueButton();
        if (DOM.hasClass("gear", "gear-active")) {
            DOM.removeClass("gear", "gear-active");
            DOM.addClass("remove_menu", "hidden");
        } else {
            DOM.addClass("gear", "gear-active");
            DOM.removeClass("remove_menu", "hidden");
            lastFocusMenu = DOM.get("remove_queue");
            lastFocusMenu.focus();
        }
    }

    /**
     * Handles a click on the "remove all" drop down menu
     *
     * @method handleMenuClick
     * @param event e -- Event
     */

    function handleMenuClick(e) {
        var target = e.srcElement || e.target; // get the source element of the click.
        EVENT.preventDefault(e);

        function clearFinished(clearErrors) {

            // Don't clear finished items that have an error state.
            for (var i = PAGE.finished.length - 1; i >= 0; i--) {
                if (PAGE.finished[i].status_info.result && !clearErrors) {
                    PAGE.finished.splice(i, 1);
                } else {
                    if (!PAGE.finished[i].status_info.result && clearErrors) {
                        PAGE.finished.splice(i, 1);
                    }
                }
            }
        }
        if ("remove_all" === target.id) {
            CPANEL.api({
                func: "restore_queue_clear_all_tasks",
                callback: {
                    failure: function() {
                        setNotice("error", LOCALE.maketext("Could not clear the restoration queue."));
                    }
                }
            });
            PAGE.queue = [];
            PAGE.finished = [];
        }
        if ("remove_queue" === target.id) {
            CPANEL.api({
                func: "restore_queue_clear_all_pending_tasks",
                callback: {
                    failure: function() {
                        setNotice("error", LOCALE.maketext("Could not clear pending restorations."));
                    }
                }
            });
            PAGE.queue = [];
        }
        if ("remove_completed" === target.id) {
            CPANEL.api({
                func: "restore_queue_clear_all_completed_tasks",
                callback: {
                    failure: function() {
                        setNotice("error", LOCALE.maketext("Could not clear completed restorations."));
                    }
                }
            });
            clearFinished();
        }
        if ("remove_errors" === target.id) {
            CPANEL.api({
                func: "restore_queue_clear_all_failed_tasks",
                callback: {
                    failure: function() {
                        setNotice("error", LOCALE.maketext("Could not clear failed restorations."));
                    }
                }
            });
            clearFinished(true);
        }
        toggleActions();
        buildQueue();
    }

    /**
     * Method to start the restore process when the "restore" button is pressed.
     *
     * @method activateRestoreQueue
     */

    function activateRestoreQueue() {
        CPANEL.Form.toggleLoadingButton("run_restore");
        PAGE.activeQueue = 1;
        CPANEL.api({
            func: "restore_queue_activate",
            callback: {
                success: function() {
                    runningQueue();
                },
                failure: function() {
                    CPANEL.Form.toggleLoadingButton("run_restore");
                    PAGE.activeQueue = 0;
                    setNotice("error", LOCALE.maketext("Could not start the restoration queue."));
                }
            }
        });
    }

    /**
     * Activates and manages communication with the restoration queue.
     *
     * @method runningQueue
     */

    function runningQueue() {

        // check to see if we are still waiting on api responses or initial page load
        if (callbackCounter === 0) {

            // build the restoration queue with the current data set
            buildQueue(true);
            filterUserList(true);

            // set the callback counter to match the number of api requests to wait for
            callbackCounter = 1;
            CPANEL.api({
                func: "restore_queue_state",
                callback: {
                    success: function(o) {
                        var data = o.cpanel_data;
                        if (data.length === 0) {
                            PAGE.activeQueue = 0;
                        } else {
                            PAGE.activeQueue = data.pending.length + data.active.length;
                            PAGE.active = data.active;
                            PAGE.queue = data.pending;
                            PAGE.finished = data.completed;
                        }
                        callbackCounter = 0;

                        // start polling if queue has not been started
                        if (!pollQueue) {
                            pollQueue = setInterval(runningQueue, POLL_INTERVAL);
                            checkQueueOnceMore = true;
                        }

                        // stop polling if queue is not active
                        if (!PAGE.activeQueue) {
                            if ( checkQueueOnceMore === true ) {

                                // Let's check one more time for final results
                                checkQueueOnceMore = false;
                            } else {
                                if (pollQueue) {
                                    clearInterval(pollQueue);
                                    pollQueue = false;
                                }
                                CPANEL.Form.toggleLoadingButton("run_restore");
                                restoreButton.disabled = true;
                            }
                        }
                    },
                    failure: function() {
                        setNotice("error", LOCALE.maketext("Failed to retrieve the restore queue state."));
                        callbackCounter = 0;
                    }
                }
            });
        }
    }

    /**
     * Initializes the restore page. Public method.
     *
     * @method initializationMethod
     */

    function initialize() {
        userSelection = DOM.get("user_selection");
        restoreUserList = DOM.get("restore_user_list");
        restoreUser = DOM.get("restore_user");
        restorePoint = DOM.get("restore_point");
        restoreCalendar = DOM.get("restore_calendar");
        restoreForm = DOM.get("restore_point_form");
        userFilter = DOM.get("user_filter");
        clearFilterEl = DOM.get("clear_user_filter");
        addUserButton = DOM.get("queue_add_user");
        userListEls = DOM.getElementsByClassName("restore-user-option", "span", restoreUserList);
        restoreTable = DOM.get("restore_table");
        restoreButton = DOM.get("run_restore");
        rowContainerTemplate = DOM.get("row_container_template").text.trim();
        noItemsTemplate = DOM.get("no_records_found_template").text.trim();
        statusTemplate = DOM.get("row_status").text.trim();
        rowTemplate = DOM.get("row_template").text.trim();
        noticeArea = DOM.get("notice_area");
        selectingByUser = true;
        dateListArray = [];
        dateListShort = [];

        userListArray = buildUserListArray();

        validSet = false; // true if a user AND a date are selected.

        /* Setup Events */

        // The "X" on the filter input to clear the selection.
        EVENT.on(clearFilterEl, "click", clearFilter);

        // The "Add user to Queue" button.
        EVENT.on(addUserButton, "click", addToQueue);

        // Filter events for user selection
        EVENT.on(userFilter, "keyup", filterUserList);
        EVENT.on(userFilter, "paste", filterUserList);

        // Toggle date select first/user select first
        EVENT.on("select-by-date", "click", selectByDate);
        EVENT.on("select-by-account", "click", selectByAccount);

        // The "restore" button
        EVENT.on("run_restore", "click", activateRestoreQueue);

        // The "select list"
        EVENT.on(restoreUserList, "click", selectUser);

        var restoreUserOptions = DOM.getElementsByClassName("restore-user-option", "SPAN", restoreUserList);
        EVENT.on(restoreUserOptions, "focus", function(e) {
            var target = e.srcElement || e.target;
            lastFocusUser = target;
        });
        EVENT.on(restoreUserOptions, "mouseover", function() {
            if (lastFocusUser) {
                lastFocusUser.blur();
                lastFocusUser = null;
            }
        });

        EVENT.on(["gear", "remove_menu"], "mouseout", function(e) {
            var element = e.toElement || e.relatedTarget;
            if (!DOM.hasClass("remove_menu", "hidden")) {
                if (!(element.parentNode.id === "remove_menu" || element.id === "remove_menu") && !(element.parentNode.id === "gear" || element.id === "gear")) {
                    toggleActions();
                }
            }
        });

        // Gear menu listeners call actions that affect groups of queue items
        EVENT.on("gear", "click", toggleActions);
        var gearMenuItems = DOM.getElementsByClassName("menu-item", "a", "remove_menu");
        EVENT.on(gearMenuItems, "click", handleMenuClick);
        EVENT.on(gearMenuItems, "mouseover", function() {
            lastFocusMenu.blur();
        });
        EVENT.on(gearMenuItems, "focus", function(e) {
            lastFocusMenu = e.srcElement || e.target; // get the source element of the click.
        });

        // HACK: add the default YUI skin back until styles can be adjusted
        DOM.addClass(document.getElementsByTagName("body"), "yui-skin-sam");

        calendar = new YAHOO.widget.Calendar("restore_calendar");

        // per 12-5-12 demo, we don't highlight today.
        calendar.Style.CSS_CELL_TODAY = "restore-today";
        calendar.selectEvent.subscribe(selectAvailableBackup, calendar, true);
        buildCalendar(calendar);

        // prevent form submit by hitting enter as there is already a handler that makes the restore API call
        YAHOO.util.Event.on("restore_point_form", "submit", function(e) {
            EVENT.stopEvent(e);
        });

        var userSelectionListener = new YAHOO.util.KeyListener(userSelection, {
            keys: [9, 13, 38, 40]
        }, keyboardSelectUser);
        userSelectionListener.enable();

        // check the state of the queue on page load
        if (parseInt(PAGE.activeQueue) === 1) {
            CPANEL.Form.toggleLoadingButton("run_restore");
            runningQueue();
        } else {
            buildQueue(true);
            filterUserList(true);
        }

        buildDateList();
        validateQueueButton();
        DOM.addClass(userSelection, "workflow-focus");
        userFilter.focus();
    }

    EVENT.onDOMReady(initialize);
}());
