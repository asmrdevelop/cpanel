CPANEL.namespace("CPANEL.App");

/**
 * The EnableIPv6 module provides methods to set IPv6 addresses for accounts.
 *
 * @module EnableIPv6
 *
 */
CPANEL.App.EnableIPv6 = (function() {

    var Handlebars = window.Handlebars,
        CALLBACK_TIMEOUT = 120000,
        SELECTOR = YAHOO.util.Selector,
        EVENT = YAHOO.util.Event,
        DOM = YAHOO.util.Dom,
        PAGE = CPANEL.PAGE,
        accountsContainer,
        lastFilterValue,
        accountFilterInput,
        accountSelectButton,
        accountFilterButton,
        accountSelected,
        accountList,
        accountsTemplate,
        accountsShiftKeyListener,
        accountsKeyListener,
        accountInformationTemplate,
        enableAccountButton,
        disableAccountButton,
        apiNoticeContainer,
        rangeListNames,
        rangeAvailable;

    /**
     * Builds a string of addressed from an array of objects
     *
     * @method ipList
     * @param {Array} context An array of ipv6 addresses
     * @returns {String} The serialized string of addresses
     */
    var ipList = function(context) {
        var addressList = context[0];
        for (var i = 1, length = context.length; i < length; i++) {
            addressList += "," + context[i];
        }
        return addressList;
    };

    /**
     * Sets the input filter and swaps the button for clear icon
     *
     * @method setFilter
     * @param {Event} e The event object
     */
    var setFilter = function(e) {
        var target = e.target || e.srcElement;
        if (target.value !== "") {
            if (target.value !== lastFilterValue) {
                DOM.removeClass(SELECTOR.query("li.selected", accountList), "selected");
                accountSelected.value = "";
            }
            lastFilterValue = target.value;

            DOM.removeClass(accountFilterButton, "filter-search");
            DOM.addClass(accountFilterButton, "filter-clear");

            var visibleElements = SELECTOR.query("li", accountList);
            var filterPattern = new RegExp(target.value, "i");

            // loop over the list and hide accounts not matching the filter
            for (var i = 0, length = visibleElements.length; i < length; i++) {
                var currentElement = visibleElements[i],
                    account = DOM.getAttribute(currentElement, "id"),
                    domain = DOM.getAttribute(currentElement, "data-domain");

                // hide acounts that do not match
                if (filterPattern.test(account)) {
                    DOM.removeClass(currentElement, "hidden");
                } else if (filterPattern.test(domain)) {
                    DOM.removeClass(currentElement, "hidden");
                } else {
                    DOM.addClass(currentElement, "hidden");
                    DOM.removeClass(currentElement, "selected");
                }
            }
        } else {
            var hiddenElements = SELECTOR.query("li.hidden", accountList);
            DOM.removeClass(hiddenElements, "hidden");
            lastFilterValue = "";
            clearFilter({
                target: accountFilterButton,
            });
        }

    };

    /**
     * Clears the input filter and swaps the button for search glass icon
     *
     * @method clearFilter
     * @param {Event} e The event object
     */
    var clearFilter = function(e) {
        var target = e.target || e.srcElement;
        if (DOM.hasClass(target, "filter-clear")) {
            var hiddenElements = SELECTOR.query("li.hidden", accountList);
            accountFilterInput.value = "";
            DOM.removeClass(hiddenElements, "hidden");
            DOM.removeClass(target, "filter-clear");
            DOM.addClass(target, "filter-search");
        }
    };

    /**
     * Selects all accounts from the list and add them to the account_selected
     *
     * @method selectAll
     * @param {Event} e The event object
     */
    var selectAll = function() {
        var accounts = SELECTOR.query("li:not(.hidden)", accountList),
            cursor = SELECTOR.query("li.cursor", accountList, true);

        // empty the selected form field and populate with all accounts
        accountSelected.value = "";
        DOM.removeClass(cursor, "cursor");
        for (var i = 0, length = accounts.length; i < length; i++) {
            var currentAccount = accounts[i];
            accountSelected.value += currentAccount.id;
            if (i !== length - 1) {
                accountSelected.value += ", ";
            }
            DOM.addClass(currentAccount, "selected");
        }

        apiNoticeContainer.innerHTML = accountInformationTemplate({
            type: "info",
            ranges: rangeListNames,
            rangeAvailability: rangeAvailable,
            multipleAccounts: true,
        });

        if (rangeAvailable) {
            disableAccountButton.disabled = false;
            DOM.removeClass(disableAccountButton, "disabled");
            enableAccountButton.disabled = false;
            DOM.removeClass(enableAccountButton, "disabled");
        }
    };

    /**
     * Handles selection of an account from the list
     *
     * @method selectAccount
     * @param {Event} e The event object
     */
    var selectAccount = function(e) {
        if (!DOM.hasClass(accountList, "loading")) {
            var selected = e.selected || SELECTOR.query("li.selected", accountList),
                cursor = e.cursor || SELECTOR.query("li.cursor", accountList, true),
                newSelection = e.target || e.srcElement,
                accountSelectedValue = accountSelected.value || false,
                removal = e.cursor ? cursor : newSelection;

            if (e.shiftKey) {
                if (accountSelectedValue && accountSelectedValue.indexOf(",")) {
                    var accounts = accountSelectedValue.split(", ");
                    if (DOM.hasClass(newSelection, "selected")) {

                        // remove account from selection
                        accounts.splice($.inArray(removal.id, accounts), 1);
                        accountSelected.value = accounts.join(", ");
                        DOM.removeClass(removal, "selected");
                    } else {

                        // add account to selection
                        if ($.inArray(newSelection.id, accounts)) {
                            accounts.push(newSelection.id);
                            accountSelected.value = accounts.join(", ");
                            DOM.addClass(newSelection, "selected");
                        }
                    }
                } else {
                    if (DOM.hasClass(newSelection, "selected")) {

                        // remove account from selection
                        accountSelected.value = "";
                        DOM.removeClass(removal, "selected");
                    } else {

                        // add account to selection
                        accountSelected.value = newSelection.id;
                        DOM.addClass(newSelection, "selected");
                    }

                }
            } else {

                // replace the existing account selection
                DOM.removeClass(selected, "selected");
                accountSelected.value = newSelection.id;
                DOM.addClass(newSelection, "selected");
            }

            // update cursor class
            DOM.removeClass(cursor, "cursor");
            DOM.addClass(newSelection, "cursor");

            if (newSelection.tagName === "LI") {
                var noticeData = {
                    type: "info",
                    multipleAccounts: SELECTOR.query("li.selected", accountList).length > 1,
                    ranges: rangeListNames,
                    rangeAvailability: rangeAvailable,
                };

                if (noticeData.multipleAccounts) {
                    if (rangeAvailable) {
                        disableAccountButton.disabled = false;
                        DOM.removeClass(disableAccountButton, "disabled");
                        enableAccountButton.disabled = false;
                        DOM.removeClass(enableAccountButton, "disabled");
                    }
                } else {
                    noticeData.domain = DOM.getAttribute(newSelection, "data-domain");
                    noticeData.ipv6 = DOM.getAttribute(newSelection, "data-ipv6");
                    if (noticeData.ipv6) {
                        noticeData.ipv6 = noticeData.ipv6.split(",");
                        enableAccountButton.disabled = true;
                        DOM.addClass(enableAccountButton, "disabled");
                        disableAccountButton.disabled = false;
                        DOM.removeClass(disableAccountButton, "disabled");
                    } else {
                        if (rangeAvailable) {
                            enableAccountButton.disabled = false;
                            DOM.removeClass(enableAccountButton, "disabled");
                        }
                        disableAccountButton.disabled = true;
                        DOM.addClass(disableAccountButton, "disabled");
                    }
                }

                apiNoticeContainer.innerHTML = accountInformationTemplate(noticeData);

            } else {
                enableAccountButton.disabled = true;
                DOM.addClass(enableAccountButton, "disabled");
                disableAccountButton.disabled = true;
                DOM.addClass(disableAccountButton, "disabled");
                apiNoticeContainer.innerHTML = accountInformationTemplate({
                    type: "info",
                    noAccount: true,
                });
            }
        }
    };

    /**
     * Handles keyboard navigation of the accounts list
     *
     * @method keyboardSelectList
     * @param {String} e The event name
     * @param {Object} key The array of key and event information
     */
    var keyboardSelectList = function(e, key) {
        var list = SELECTOR.query("li:not(.hidden)", accountList),
            selected = SELECTOR.query("li.selected", accountList),
            cursor = SELECTOR.query("li.cursor", accountList, true),
            hasScroll = accountList.scrollHeight > accountList.offsetHeight,
            lastElement = list[list.length - 1],
            firstElement = list[0],
            keyPressed = key[0],
            keyEvent = key[1],
            newSelection;

        var visible = function(sibling) {
            return !DOM.hasClass(sibling, "hidden");
        };

        // escape, clear the filter and return
        if (keyPressed === 27) {
            clearFilter({
                target: accountFilterButton,
            });
            return;
        }

        if (selected) {
            if (keyPressed === 40) {

                // scroll user list down
                newSelection = DOM.getNextSiblingBy(cursor, visible);
                if (!newSelection) {
                    newSelection = firstElement;
                }
            } else if (keyPressed === 38) {

                // scroll user list up
                newSelection = DOM.getPreviousSiblingBy(cursor, visible);
                if (!newSelection) {
                    newSelection = lastElement;
                }
            } else if (keyPressed === 13) {

                // enter pressed so enable IPv6 for the current account
                enableAccountButton.click();
                EVENT.stopEvent(keyEvent);
            }
        } else {
            if (keyPressed === 40) {

                // select first user in the list
                newSelection = firstElement;
            } else if (keyPressed === 38) {

                // select last user in the list
                newSelection = lastElement;
            }
        }
        if (newSelection) {

            // ensure cursor does not move
            EVENT.preventDefault(keyEvent);

            if (hasScroll) {
                newSelection.scrollIntoView(false);
            }

            // select the account
            selectAccount({
                cursor: cursor,
                selected: selected,
                target: newSelection,
                shiftKey: keyEvent.shiftKey,
            });
        }
    };

    /**
     * Toggles the loading and enabled states of a button
     *
     * @method toggleLoadingButton
     * @param {String | HTMLElement} action The button to set a loading state on
     */
    var toggleLoadingButton = function(action) {
        if (typeof action === "string") {
            action = DOM.get(action);
        }
        var spinner = DOM.getElementsByClassName("spinner", "div", action)[0];
        if (!spinner) {
            action = action.parentNode;
            spinner = DOM.getElementsByClassName("spinner", "div", action)[0];
        } // Chrome focus is on the button text instead of the button
        if (DOM.hasClass(action, "loading")) {

            // remove loading state
            DOM.removeClass(action, "loading");
            DOM.removeClass(action, "disabled");
            action.disabled = false;
        } else {

            // set loading state
            action.disabled = true;
            DOM.addClass(action, "disabled");
            spinner.style.width = action.offsetWidth + "px";
            DOM.addClass(action, "loading");
        }
    };

    /**
     * Enables IPv6 Addressing for an account
     *
     * @method enableIPv6
     */
    var enableIPv6 = function() {
        var account = accountSelected.value,
            callbackTimeout = SELECTOR.query("li.selected", accountList).length * CALLBACK_TIMEOUT || CALLBACK_TIMEOUT,
            selectedRange = DOM.get("select_range").value,
            dedicated = 1;
        toggleLoadingButton(enableAccountButton);
        accountsKeyListener.disable();
        DOM.addClass(accountList, "loading");

        CPANEL.api({
            func: "ipv6_enable_account",
            data: {
                "user": account,
                "dedicated": dedicated,
                "range": selectedRange,
            },
            catch_api_errors: true,
            callback: {
                argument: {
                    account: account,
                    dedicated: dedicated,
                },
                success: function(o) {
                    var ipv6Set = o.cpanel_data.ipv6,
                        successAccounts = "",
                        successCount = 0,
                        failCount = o.cpanel_data.fail_cnt,
                        failures = o.cpanel_data.failures,
                        message,
                        accountListItem,
                        multipleAccounts = false,
                        accountDomain = [],
                        accountIPv6 = [];
                    for (var account in ipv6Set) {
                        if (ipv6Set.hasOwnProperty(account)) {
                            successAccounts += account + ", ";
                            successCount++;
                        }
                    }
                    successAccounts = successAccounts.substr(0, successAccounts.length - 2);

                    // message handle
                    if (successCount > 1) {
                        message = LOCALE.maketext("IPv6 is enabled for the following accounts: [_1]", successAccounts);
                        multipleAccounts = true;
                    } else if (successCount === 1) {
                        message = LOCALE.maketext("IPv6 enabled for the “[_1]” account.", account);
                    }

                    if (successCount !== 0) {
                        for (var user in ipv6Set) {
                            if (ipv6Set.hasOwnProperty(user)) {
                                accountListItem = DOM.get(user);
                                accountDomain.push(accountListItem.getAttribute("data-domain"));
                                accountListItem.setAttribute("data-ipv6", ipv6Set[user]);
                                accountIPv6.push(ipv6Set[user]);
                                DOM.addClass(accountListItem, "Enabled");
                            }
                        }

                        apiNoticeContainer.innerHTML = accountInformationTemplate({
                            type: "success",
                            message: message,
                            domain: accountDomain,
                            multipleAccounts: multipleAccounts,
                            ipv6: accountIPv6,
                        });
                    } else {
                        apiNoticeContainer.innerHTML = "";
                    }

                    if (failCount > 0) {
                        message = "";
                        for (var failure in failures) {
                            message = failure + ": " + failures[failure];
                            apiNoticeContainer.innerHTML += accountInformationTemplate({
                                type: "error",
                                error: true,
                                message: message,
                            });
                        }
                    }

                    // remove loading states
                    accountsKeyListener.enable();
                    DOM.removeClass(accountList, "loading");
                    toggleLoadingButton(enableAccountButton);
                    enableAccountButton.disabled = true;
                    DOM.addClass(enableAccountButton, "disabled");
                    disableAccountButton.disabled = false;
                    DOM.removeClass(disableAccountButton, "disabled");
                    accountFilterInput.focus();
                },
                failure: function(o) {
                    var error = LOCALE.maketext("Request timed out.");
                    if (o && o.status > 0) {
                        error = String(o.cpanel_error || o.error || o).html_encode();
                    }
                    apiNoticeContainer.innerHTML = accountInformationTemplate({
                        type: "error",
                        error: true,
                        message: error,
                    });

                    // remove loading states
                    accountsKeyListener.enable();
                    DOM.removeClass(accountList, "loading");
                    toggleLoadingButton(enableAccountButton);
                },
                timeout: callbackTimeout,
            },
        });
    };

    /**
     * Disables IPv6 Addressing for an account
     *
     * @method disableIPv6
     */
    var disableIPv6 = function() {
        var account = accountSelected.value,
            callbackTimeout = SELECTOR.query("li.selected", accountList).length * CALLBACK_TIMEOUT || CALLBACK_TIMEOUT;
        toggleLoadingButton(disableAccountButton);
        accountsKeyListener.disable();
        DOM.addClass(accountList, "loading");

        CPANEL.api({
            func: "ipv6_disable_account",
            data: {
                "user": account,
            },
            catch_api_errors: true,
            callback: {
                success: function() {

                    // handle multiple account disables
                    var accounts = accountSelected.value.split(", "),
                        length = accounts.length;
                    if (length > 1) {
                        apiNoticeContainer.innerHTML = accountInformationTemplate({
                            type: "success",
                            message: LOCALE.maketext("IPv6 is disabled for the following accounts: [_1]", account),
                            ranges: rangeListNames,
                            rangeAvailability: rangeAvailable,
                            multipleAccounts: true,
                        });
                    } else {
                        apiNoticeContainer.innerHTML = accountInformationTemplate({
                            type: "success",
                            message: LOCALE.maketext("IPv6 is disabled for the “[_1]” account.", account),
                            ranges: rangeListNames,
                            rangeAvailability: rangeAvailable,
                        });
                    }
                    for (var i = 0; i < length; i++) {
                        account = DOM.get(accounts[i]);
                        if (account.hasAttribute("data-ipv6")) {
                            account.removeAttribute("data-ipv6");
                        }
                        DOM.removeClass(account, "Enabled");
                    }

                    // remove loading states
                    accountsKeyListener.enable();
                    DOM.removeClass(accountList, "loading");
                    toggleLoadingButton(disableAccountButton);
                    enableAccountButton.disabled = false;
                    DOM.removeClass(enableAccountButton, "disabled");
                    disableAccountButton.disabled = true;
                    DOM.addClass(disableAccountButton, "disabled");
                    accountFilterInput.focus();
                },
                failure: function(o) {
                    var error = LOCALE.maketext("Request timed out.");
                    if (o && o.status > 0) {
                        error = String(o.cpanel_error || o.error || o).html_encode();
                    }
                    apiNoticeContainer.innerHTML = accountInformationTemplate({
                        type: "error",
                        error: true,
                        message: error,
                    });

                    // remove loading states
                    accountsKeyListener.enable();
                    DOM.removeClass(accountList, "loading");
                    toggleLoadingButton(disableAccountButton);
                },
                timeout: callbackTimeout,
            },
        });
    };

    Handlebars.registerHelper("if_eq", function(a, b, opts) {
        if (a === b) {
            return opts.fn(this);
        } else {
            return opts.inverse(this);
        }
    });

    Handlebars.registerHelper("wrap", function(text, characters) {
        var template = "<wbr>";

        // escape our input
        var escaped_text = Handlebars.Utils.escapeExpression(text);

        // return the string if we are do not have something to match on
        if (!characters) {
            return new Handlebars.SafeString(escaped_text);
        }

        // replace the matching characters with our template
        var match = "[" + characters + "]";
        var expression = new RegExp("(" + match + ")", "g");
        var result = escaped_text.replace(expression, "$1" + template);

        // return an html-escaped string
        return new Handlebars.SafeString(result);
    });

    /**
     * Initializes page elements and attaches listeners
     *
     * @method initialize
     */
    var initialize = function() {
        rangeListNames = [];

        // load available ranges names for enable dropdown
        for (var i = 0, length = CPANEL.PAGE.ranges.length; i < length; i++) {
            if (parseInt(CPANEL.PAGE.ranges[i].enabled)) {
                rangeListNames.push(CPANEL.PAGE.ranges[i].name);
            }
        }
        rangeAvailable = (rangeListNames.length === 0) ? false : true;

        accountInformationTemplate = Handlebars.compile(DOM.get("account_information_template").text.trim());
        accountSelected = DOM.get("account_selected");

        // register handlebars helpers
        Handlebars.registerHelper("ipList", ipList);

        // build the account list
        accountList = DOM.get("account_list");
        accountsTemplate = Handlebars.compile(DOM.get("accounts_template").text.trim());
        var accounts = "";
        for (i = 0, length = PAGE.users.length; i < length; i++) {
            accounts += accountsTemplate({
                account: PAGE.users[i].user,
                ipv6: PAGE.users[i].ipv6,
                domain: PAGE.users[i].domain,
            });
        }
        accountList.innerHTML = accounts;

        lastFilterValue = "";

        accountFilterInput = DOM.get("account_filter");
        EVENT.on(accountFilterInput, "keyup", setFilter);

        accountSelectButton = DOM.get("account_select_button");
        EVENT.on(accountSelectButton, "click", selectAll);

        accountFilterButton = DOM.get("account_filter_button");
        EVENT.on(accountFilterButton, "click", clearFilter);

        accountsContainer = DOM.get("accounts_container");

        // handle selecting multiple users at once
        accountsShiftKeyListener = new YAHOO.util.KeyListener(
            accountsContainer, {
                ctrl: false,
                shift: true,
                keys: [13, 27, 38, 40],
            },
            keyboardSelectList).enable();

        // handle keyboard selection of a single user
        accountsKeyListener = new YAHOO.util.KeyListener(
            accountsContainer, {
                keys: [13, 27, 38, 40],
            },
            keyboardSelectList);
        accountsKeyListener.enable();

        // mouse selection handler
        EVENT.on(accountList, "click", selectAccount);

        enableAccountButton = DOM.get("enable_account");
        enableAccountButton.disabled = true;
        EVENT.on(enableAccountButton, "click", enableIPv6);

        disableAccountButton = DOM.get("disable_account");
        disableAccountButton.disabled = true;
        EVENT.on(disableAccountButton, "click", disableIPv6);

        apiNoticeContainer = DOM.get("api_notice");

        // prevent hitting enter in input elements causing a form submit
        EVENT.on("ipv6_accounts_form", "submit", function(e) {
            EVENT.stopEvent(e);
        });

        accountFilterInput.focus();
    };

    EVENT.onDOMReady(initialize);
}());
