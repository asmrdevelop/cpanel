/*
# cpanel - whostmgr/docroot/templates/edit_reseller_privileges/index.js
#                                                  Copyright 2023 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* globals do_quick_popupbox, suggestedNameservers */

var EditReseller = (function(doQuickPopupbox, PAGE, CPANEL, suggestedNameservers) { // eslint-disable-line no-unused-vars
    "use strict";

    // initialization
    var VALID = {};
    var cprapidRe = new RegExp(/\.cprapid\.com$/);
    var showWarning = {};
    checkst();
    showDiv("limits_resources", "usagelim");
    showPkgLim();
    accountLimitCheck();
    setupAccountLimitValidation();
    updateSubcategoryCheckboxes();
    delegate(document.querySelector(".list-group"), "click", "input.acl-checkbox", handleDelegatedEvent);
    delegate(document.querySelector(".save-acl-list-container"), "click", "input[type=radio]", handleRadioGroupEvent);
    delegate(document.querySelector("#limits_resources"), "click", "#limits_resources", accountLimitCheck);

    // return the object so it can be used outside the module
    return {
        toggleAll: toggleAll,
        checkcancreate: checkcancreate,
        checkcancreate2: checkcancreate2,
        addns: addns,
        killresnumlimitamt: killresnumlimitamt,
        checkresnumlimit: checkresnumlimit,
        updateacls: updateacls,
        handleLimitsForPreassignedPackages: handleLimitsForPreassignedPackages,
        handleLimitsForAccountAmounts: handleLimitsForAccountAmounts,
        handleLimitResources: handleLimitResources,
        toggleHelpText: toggleHelpText,
        toggleInherit: toggleInherit,
        initNsWarning: initNsWarning,
    };

    function updateNsWarning() {
        var nsWarning = document.getElementById("warning-ns");
        var show = Object.values(showWarning).some(_ => _);
        show ? nsWarning.classList.remove("hidden") : nsWarning.classList.add("hidden");
    }

    /* Public functions */
    function toggleInherit(inherit) {
        var nameserverList = document.getElementById("resellerNameserverList");
        if (inherit) {
            nameserverList.className = nameserverList.className + " hidden";
            showWarning["suggested"] = suggestedNameservers.map(_ => _.suggested_nameserver).some(_ => cprapidRe.test(_));
            showWarning["reseller"] = false;
        } else {
            showWarning["suggested"] = false;
            nameserverList.className = nameserverList.className.replace("hidden", "");
            nameserverList.scrollIntoView();
            document.getElementById("ns1").focus();
        }

        updateNsWarning();
    }

    function initNsWarning() {
        var nsValues = {};
        var nameserverList = document.getElementById("resellerNameserverList");
        var nsInputs = nameserverList.querySelectorAll('input[type="text"]');
        var inherit = document.getElementById("inheritNameserversFromYes").checked;
        showWarning["suggested"] = inherit && suggestedNameservers.map(_ => _.suggested_nameserver).some(_ => cprapidRe.test(_));
        var _nsListener = function(event) {
            var target = event.target;
            nsValues[target.id] = target.value;
            showWarning["reseller"] = Object.values(nsValues).some(_ => cprapidRe.test(_));
            updateNsWarning();
        };

        nsInputs.forEach(function(el) {
            nsValues[el.id] = el.value;
            el.addEventListener("input", _nsListener);
            el.addEventListener("focus", _nsListener);
        });

        showWarning["reseller"] = Object.values(nsValues).some(_ => cprapidRe.test(_));
        updateNsWarning();
    }

    function toggleAll(event) {
        var check = event.target.checked;
        var parentEl = event.target.parentNode.parentNode;
        var inputEls = parentEl.querySelectorAll("input");

        for (var i = 0, len = inputEls.length; i < len; i++) {

            // make sure we don't include the toggle input in this list
            if (event.target.id === inputEls[i].id) {
                continue;
            }

            inputEls[i].checked = check;
        }
    }

    function checkcancreate2(event, pkg) {
        document.resform["respkg-" + pkg].checked = event.target.value === "0";
    }

    function checkcancreate(pkg) {
        if (!document.resform["respkg-" + pkg].checked) {
            document.resform["acctlim-" + pkg].value = "0";
        }
    }

    function addns(el) {
        var nameserver = el.value;
        doQuickPopupbox({
            title: "Configure Address Records",
            url: "../scripts2/addaforns",
            showloading: 1,
            iframe: 1,
            height: 375,
        }, "nameserver", nameserver );
    }

    function killresnumlimitamt(sbox) {
        if (!sbox.checked) {
            document.resform.resnumlimitamt.value = 0;
        }
    }

    function checkresnumlimit(sbox) {
        if (parseInt(sbox.value, 10) > 0) {
            document.resform.limits_number_of_accounts.checked = true;
        }
    }

    function updateacls(event) {
        var selectedList = event.target.options[event.target.selectedIndex].value;

        if (typeof PAGE.acl_lists[selectedList] === "undefined") {
            return;
        }

        var list = PAGE.acl_lists[selectedList];
        for (var i = 0, keys = Object.keys(list), len = keys.length; i < len; i++) {
            var value = Boolean(Number(list[keys[i]]));
            document.resform["acl-" + keys[i]].checked = value;
        }

        updateSubcategoryCheckboxes();
    }

    function handleLimitsForPreassignedPackages(event) {
        var child = document.resform["limits_number_of_packages"];
        if (!event.target.checked) {
            child.checked = false;
        }

        checkst();
        showPkgLim();
    }

    function handleLimitsForAccountAmounts(event) {
        var parent = document.resform["limits_preassigned_packages"];
        if (event.target.checked) {
            parent.checked = true;
        }

        checkst();
        showPkgLim();
    }

    function handleLimitResources() {
        showDiv("limits_resources", "usagelim");
    }

    function toggleHelpText(event, helpContainer) {
        if (event.type === "keypress") {
            if (event.charCode === 32 || event.charCode === 13) {
                toggleText(helpContainer);
                event.preventDefault();
            }
        } else {
            toggleText(helpContainer);
        }
    }

    /* Private functions */
    function toggleText(id) {
        var container = document.getElementById(id);
        if (hasClass(container, "hidden")) {
            removeClass(container, "hidden");
        } else {
            addClass(container, "hidden");
        }
    }

    function checkst() {

        // This input doesn’t exist for single-user licenses.
        if (document.resform.limits_number_of_packages) {
            togglePkgNums(document.resform.limits_number_of_packages.checked);
        }
    }

    function updateSubcategoryCheckboxes() {
        var subcategoryBoxes = document.querySelectorAll(".acl-subcategory-checkbox");
        for (var i = 0, len = subcategoryBoxes.length; i < len; i++) {
            setSubcategoryCheckboxState(subcategoryBoxes[i]);
        }
    }

    function handleRadioGroupEvent(event) {
        var els = document.querySelectorAll(".save-acl-list-container input[type=radio]");
        for (var i = 0, len = els.length; i < len; i++) {
            if (els[i].id === event.target.id) {
                enableRelatedField(els[i]);
            } else {
                disableRelatedField(els[i]);
            }
        }
    }

    function enableRelatedField(el) {
        toggleRelatedField(el, false);
    }

    function disableRelatedField(el) {
        toggleRelatedField(el, true);
    }

    function toggleRelatedField(el, state) {
        var related = el.getAttribute("data-relates-to");
        if (related) {
            var relatedEl = document.getElementById(related);
            if (relatedEl) {
                relatedEl.disabled = state;
            }
        }
    }

    function handleDelegatedEvent(event) {
        setSubcategoryCheckboxState(event.target);
    }

    function setSubcategoryCheckboxState(el) {
        var checkboxContainer = el.closest("div.checkbox");
        if (checkboxContainer === null) {
            return;
        }

        var subCatContainer = checkboxContainer.parentNode;
        var subCatElement = subCatContainer.querySelector(".acl-subcategory-checkbox");
        var acls = subCatContainer.querySelectorAll(".acl-checkbox");
        var count = 0;
        var displayed = 0;
        for (var i = 0, len = acls.length; i < len; i++) {
            if (acls[i].checked) {
                count++;
            }
            displayed++;
        }

        subCatElement.checked = count === displayed;
        subCatElement.indeterminate = count > 0 && count < displayed;
    }

    function togglePkgNums(show) {
        var pkgtbl = document.getElementById("acctlimittbl");
        for (var i = 0; i < pkgtbl.rows.length; i++) {
            if (show) {
                removeClass(pkgtbl.rows[i].cells[3], "hidden");
            } else {
                addClass(pkgtbl.rows[i].cells[3], "hidden");
            }
        }
    }

    function showPkgLim() {
        var parent = document.getElementById("limits_preassigned_packages");
        var child = document.getElementById("limits_number_of_packages");

        if (parent === null || child === null) {
            return;
        }

        if (parent.checked || child.checked) {
            removeClass(document.getElementById("pkglim"), "hidden");
        }
        if (!parent.checked && !child.checked) {
            addClass(document.getElementById("pkglim"), "hidden");
        }
    }

    function showDiv(inputId, divname) {
        var conditionalElement = document.getElementById(inputId);
        var targetDiv = document.getElementById(divname);

        if (conditionalElement === null || targetDiv === null) {
            return;
        }

        if (conditionalElement.checked) {
            removeClass(targetDiv, "hidden");
        } else {
            addClass(targetDiv, "hidden");
        }
    }

    function hasClass(el, className) {
        if (el.classList) {
            return el.classList.contains(className);
        } else {
            var regex = new RegExp("(\\s|^)" + className + "(\\s|$)");
            return regex.test(el.className);
        }
    }

    function addClass(el, className) {
        if (el.classList) {
            el.classList.add(className);
        } else if (!hasClass(el, className)) {
            el.className += " " + className;
        }
    }

    function removeClass(el, className) {
        if (el.classList) {
            el.classList.remove(className);
        } else if (hasClass(el, className)) {
            var reg = new RegExp("(\\s|^)" + className + "(\\s|$)");
            el.className = el.className.replace(reg, " ");
        }
    }

    /**
     * Attachs an event listener to a root element to listen for events
     * on a child element.
     *
     * @method delegate
     * @param {HTMLElement} element - the root element to bind the listener to
     * @param {String} type - the events to listen to
     * @param {String} selector - a DOMString selector on which we will trigger events
     * @param {Function} callback - the function to execute on matching child elements
     */
    function delegate(element, type, selector, callback) {
        element.addEventListener(type, function(event) {

            // only execute the callback if we have a selector match
            if (event.target.closest(selector)) {
                callback.call(element, event);
            }
        });
    }

    function accountLimitCheck() {
        var diskOption = document.querySelector("#privs_allow-unlimited-disk-pkgs"),
            bandwidthOption = document.querySelector("#privs_allow-unlimited-bw-pkgs"),
            diskWarningToggle = document.querySelector("#acl-warning-toggle-allow-unlimited-disk-pkgs"),
            bandwidthWarningToggle = document.querySelector("#acl-warning-toggle-allow-unlimited-bw-pkgs"),
            diskWarning = document.querySelector("#acl-warning-allow-unlimited-disk-pkgs"),
            bandwidthWarning = document.querySelector("#acl-warning-allow-unlimited-bw-pkgs");

        if (document.querySelector("#limits_resources").checked) {
            diskOption.checked = false;
            diskOption.disabled = true;
            bandwidthOption.checked = false;
            bandwidthOption.disabled = true;
            diskWarningToggle.classList.remove("hidden");
            bandwidthWarningToggle.classList.remove("hidden");
            diskWarning.classList.remove("hidden");
            bandwidthWarning.classList.remove("hidden");
            updateValidation();
        } else {
            diskOption.checked = diskOption.defaultChecked;
            bandwidthOption.checked = bandwidthOption.defaultChecked;
            diskOption.disabled = false;
            bandwidthOption.disabled = false;
            diskWarningToggle.classList.add("hidden");
            bandwidthWarningToggle.classList.add("hidden");
            diskWarning.classList.add("hidden");
            bandwidthWarning.classList.add("hidden");
            clearValidationMessages();
        }
    }

    function isLimitResourcesChecked() {
        return document.querySelector("#limits_resources").checked;
    }

    function setupAccountLimitValidation() {
        var rslimitdisk = document.getElementById("rslimit-disk");
        var rslimitbw = document.getElementById("rslimit-bw");

        if (rslimitdisk) {
            VALID.maxAllowedDisk = new CPANEL.validate.validator(LOCALE.maketext("Maximum Allowed Disk Space")); // eslint-disable-line new-cap
            VALID.maxAllowedDisk.add("rslimit-disk", "if_not_empty(%input%, CPANEL.validate.positive_integer)", LOCALE.maketext("You must enter a positive integer value."), isLimitResourcesChecked);
            VALID.maxAllowedDisk.attach();
            if (rslimitdisk.value.length > 0) {
                VALID.maxAllowedDisk.verify();
            }
        }

        if (rslimitbw) {
            VALID.maxAllowedBW = new CPANEL.validate.validator(LOCALE.maketext("Maximum Allowed Bandwidth")); // eslint-disable-line new-cap
            VALID.maxAllowedBW.add("rslimit-bw", "if_not_empty(%input%, CPANEL.validate.positive_integer)", LOCALE.maketext("You must enter a positive integer value."), isLimitResourcesChecked);
            VALID.maxAllowedBW.attach();
            if (rslimitbw.value.length > 0) {
                VALID.maxAllowedBW.verify();
            }
        }

        CPANEL.validate.attach_to_form("save_button", VALID);
    }

    function updateValidation() {
        var rslimitdisk = document.getElementById("rslimit-disk");
        var rslimitbw = document.getElementById("rslimit-bw");

        if (VALID.maxAllowedDisk && rslimitdisk && rslimitdisk.value.length > 0) {
            VALID.maxAllowedDisk.verify();
        }

        if (VALID.maxAllowedBW && rslimitbw && rslimitbw.value.length > 0) {
            VALID.maxAllowedBW.verify();
        }
    }

    function clearValidationMessages() {
        if (VALID.maxAllowedDisk) {
            VALID.maxAllowedDisk.clear_messages();
        }

        if (VALID.maxAllowedBW) {
            VALID.maxAllowedBW.clear_messages();
        }
    }
}(do_quick_popupbox, PAGE, CPANEL, suggestedNameservers));

/**
 * Polyfill for closest and matches
 * from https://github.com/jonathantneal/closest/blob/master/closest.js
 * http://caniuse.com/#feat=element-closest
 * http://caniuse.com/#feat=matchesselector
 *
 * NOTE: This currently exists in the command.js for the WHM menu. It is added here
 * in case it gets removed from the other file.
 */
(function(ELEMENT) {
    "use strict";
    ELEMENT.matches = ELEMENT.matches || ELEMENT.mozMatchesSelector || ELEMENT.msMatchesSelector || ELEMENT.oMatchesSelector || ELEMENT.webkitMatchesSelector;

    ELEMENT.closest = ELEMENT.closest || function closest(selector) {
        var element = this;

        while (element) {
            if (element.matches(selector)) {
                break;
            }

            element = element.parentElement;
        }

        return element;
    };
}(Element.prototype));
