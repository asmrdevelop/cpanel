// Polyfill for Internet Explorer:
// https://developer.mozilla.org/en-US/docs/Web/API/CustomEvent/CustomEvent
(function() {

    "use strict";

    if ( typeof window.CustomEvent === "function" ) {
        return false;
    }

    function CustomEvent( event, params ) {
        params = params || { bubbles: false, cancelable: false, detail: undefined };
        var evt = document.createEvent( "CustomEvent" );
        evt.initCustomEvent( event, params.bubbles, params.cancelable, params.detail );
        return evt;
    }

    CustomEvent.prototype = window.Event.prototype;

    window.CustomEvent = CustomEvent;
})();
/*
 * master_templates/contentContainerInit.js           Copyright 2022 cPanel, L.L.C.
 *                                                           All rights reserved.
 * copyright@cpanel.net                                         http://cpanel.net
 * This code is subject to the cPanel license. Unauthorized copying is prohibited
 */
(function() {

    "use strict";

    /**
     * We create two different ways to trigger initialization because both methods
     * are valid, the first callback fired differs by page, and we want to begin
     * initialization as soon as either condition is met.
     */
    window.addEventListener("load", function() {
        dispatchInitEvent("load event");
    });

    var observer = new MutationObserver(function() {
        var contentContainer = document.getElementById("contentContainer");
        if ( contentContainer !== null && contentContainer.firstElementChild ) {
            observer.disconnect();

            dispatchInitEvent("MutationObserver");
        }
    });

    observer.observe(window.document.documentElement, {
        childList: true,
        subtree: true
    });

    /**
     * Dispatches the event if it hasn't already done so in the past.
     */
    var eventDispatched;
    function dispatchInitEvent(triggerName) {
        if (eventDispatched) {
            return;
        }

        eventDispatched = true;

        if (window.location.href.indexOf("debug=1") !== -1) {
            console.log("content-container-init triggered via " + triggerName); // eslint-disable-line no-console
        }

        var event = new CustomEvent("content-container-init");
        window.dispatchEvent(event);
    }
})();
/*
# menu/topframe.js                                 Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function() {
    "use strict";

    // Load Average Timeout (5 minutes)
    var LOADAVG_TIMEOUT = 5 * 1000 * 60;
    var documentHidden = void 0;

    /**
     * Check if the browser window/tab is visible.
     *
     * We check explicitly for undefined in case the pagevisibility api is
     * not supported by the browser.
     *
     * @method isPageVisible
     */
    var isPageVisible = function() {
        return documentHidden === void 0 || !document[documentHidden];
    };

    /**
     * Checks for recent activity
     *
     * @method checkRecentActivity
     */
    var checkRecentActivity = function() {
        return isPageVisible() && (!top._LAST_ACTIVITY || (new Date() - top._LAST_ACTIVITY < LOADAVG_TIMEOUT));
    };

    var loadLiveEl;
    var loadLiveOne;
    var loadLiveFive;
    var loadLiveFifteen;

    /**
     * Callback for the loadavg ajax request
     *
     * @method updateLoad
     * @param {Event} event - the XmlHttpRequest event
     */
    var updateLoad = function(event) {

        if (loadLiveEl) {
            var loadavgs = JSON.parse(event.target.responseText);

            loadLiveOne.textContent = loadavgs.one;
            loadLiveFive.textContent = loadavgs.five;
            loadLiveFifteen.textContent = loadavgs.fifteen;

            if (loadLiveEl.classList.contains("hidden")) {

                // Show it now that we have data
                loadLiveEl.classList.remove("hidden");
            }

            if (checkRecentActivity()) {
                if (loadavgs["one"] < 0.5) {
                    setTimeout(getLoadAverage, 15000);
                } else if (loadavgs["one"] < 1.0) {
                    setTimeout(getLoadAverage, 30000);
                } else {
                    setTimeout(getLoadAverage, 45000);
                }
            } else {
                setTimeout(function checkActivity() {
                    if (checkRecentActivity()) {
                        getLoadAverage();
                    } else {
                        setTimeout(checkActivity, 20000);
                    }
                }, 20000);
            }

            return;
        }

        setTimeout(function() {
            updateLoad(event);
        }, 1000);
    };

    /**
     * Fetch the load average data
     *
     * @method getLoadAverage
     */
    var getLoadAverage = function() {
        var request = new XMLHttpRequest();
        request.addEventListener("load", function(event) {
            if (request.status === 0 ||
                request.status >= 200 && request.status < 300 ||
                request.status === 304) {
                updateLoad(event);
            }
        });

        var url = "";
        if (window.COMMON.securityToken) {
            url = window.COMMON.securityToken + "/json-api/loadavg";
        } else {
            url = "/json-api/loadavg";
        }

        if (url) {
            request.open("GET", url, true);
            request.send();
        }

    };

    /**
     * Sets the Last Activity
     *
     * @method setLastActivity
     */
    var setLastActivity = function() {
        top._LAST_ACTIVITY = new Date();
    };

    /**
     * Event handler for the page visibility api
     *
     * @method handleVisibilityChange
     */
    var handleVisibilityChange = function(event) {
        if (isPageVisible()) {
            setLastActivity();
        }
    };

    /**
     * Set the Last Activity
     *
     * @method attachLoadAvg
     */
    var attachLoadAvg = function() {
        var frames = top.document.getElementsByTagName("frame");

        var initializeEventHandler = function(frame) {

            // only listen to click and keyup to reduce the number of times we set LAST_ACTIVITY
            frame.document.body.addEventListener("click", setLastActivity);
            frame.document.body.addEventListener("keyup", setLastActivity);
        };

        if (frames) {
            for (var len = frames.length - 1; len > -1; len--) {
                var frame = frames[len];
                frame.contentWindow.addEventListener("load", initializeEventHandler(this));
            }
        }

    };

    /**
     * Check if there is an update available.
     */
    var checkUpdateAvailability = function() {
        var getUpdateAvailabilityEl = document.getElementById("getUpdateAvailability");
        if (getUpdateAvailabilityEl) {
            var request = new XMLHttpRequest();
            request.addEventListener("load", function(event) {
                if (request.status === 0 ||
                    request.status >= 200 && request.status < 300 ||
                    request.status === 304) {

                    if (event && event.target && event.target.responseText) {
                        var response = JSON.parse(event.target.responseText);
                        if (response && response.data && response.data.update_available) {

                            var updateNewestVersionEl = document.getElementById("lblUpdateNewestVersion");
                            if (updateNewestVersionEl) {
                                updateNewestVersionEl.textContent = updateNewestVersionEl.textContent.replace("[PLACEHOLDER_VALUE_UPDATE_VERSION]", response.data.newest_version);
                            }

                            if (getUpdateAvailabilityEl.classList.contains("hidden")) {
                                getUpdateAvailabilityEl.classList.remove("hidden");
                            }
                        }
                    }
                }
            });

            var url = "";
            if (window.COMMON.securityToken) {
                url = window.COMMON.securityToken + "/json-api/get_update_availability?api.version=1";
            } else {
                url = "/json-api/get_update_availability?api.version=1";
            }

            if (url) {
                request.open("GET", url, true);
                request.send();
            }

        }
    };

    /**
     * Logout of WHM
     *
     * @method logoutWHM
     */
    var logoutWHM = function() {

        // Clears navigation search bar on logout
        if (typeof sessionStorage.searchTerm !== "undefined") {
            delete sessionStorage.searchTerm;
            delete sessionStorage.userName;
        }
    };

    /**
     * Attach an event handler for the page visibility api, if supported
     *
     * @method addVisibilityListener
     */
    var addVisibilityListener = function() {
        var visibilityChange = void 0;
        if (typeof document.hidden !== "undefined") { // Opera 12.10 and Firefox 18 and later support
            documentHidden = "hidden";
            visibilityChange = "visibilitychange";
        } else if (typeof document.msHidden !== "undefined") {
            documentHidden = "msHidden";
            visibilityChange = "msvisibilitychange";
        } else if (typeof document.webkitHidden !== "undefined") {
            documentHidden = "webkitHidden";
            visibilityChange = "webkitvisibilitychange";
        }

        if (documentHidden !== void 0) {
            document.addEventListener(visibilityChange, handleVisibilityChange);
        }
    };

    function updateUIForQuota(data) {
        if (data && parseInt(data.quota_enabled) !== 1) {
            var quotaWarnings = document.querySelectorAll(".quota_sensitive");
            for (var quotaWarning in quotaWarnings) {
                if (quotaWarnings[quotaWarning].style) {
                    quotaWarnings[quotaWarning].style.display = "";
                }
            }
            var quotaValues = document.querySelectorAll(".quota_insensitive");
            for (var quotaValue in quotaValues) {
                if (quotaValues[quotaValue].style) {
                    quotaValues[quotaValue].style.display = "none";
                }
            }
        }
    }

    function checkQuota() {

        // do not run this check on dnsonly servers since it is not needed
        if (typeof window.COMMON.isDnsOnly !== "undefined" && window.COMMON.isDnsOnly) {
            return;
        }

        var pageURL = window.location.toString();

        /* window.serverNeedsReboot was originally set to 1 or 0 if a reboot was needed
         * since detailed data about why the reboot was needed was being suppressed which
         * will let use determine why the reboot is needed it was changed to return the
         * underlying data structure when it is available.  There may be (unknown?) cases
         * where it is still set to 1 so we handle this as well.
         *
         * Since we now know why a reboot is needed (always?) we know when it is safe to
         * cache the result of the quota_enabled api call which prevents it from happening
         * on every page when a reboot is needed for any reason.
         */
        var needsRebootReasonIsQuota = typeof window.serverNeedsReboot === "object" && window.serverNeedsReboot !== null ? parseInt(window.serverNeedsReboot.quota, 10) : parseInt(window.serverNeedsReboot, 10) === 1;
        var noCache = pageURL.match(/newquota/) || pageURL.match(/graceful_reboot_landing/) || pageURL.match(/forcereboot/) || needsRebootReasonIsQuota;

        // Pop cache in the event we're on the "initial quota setup" action page, or we just rebooted the server
        if ( noCache ) {
            window.localStorage.removeItem("cPQuotaStatus");
        }

        // Check for whether we've already got this data in the session, 1hr expiry (in milliseconds since epoch)
        var cached = window.localStorage.getItem("cPQuotaStatus");
        if ( cached ) {
            cached = JSON.parse(cached);
            if ( typeof cached === "object" && cached.hasOwnProperty("lastChecked") && ( Date.now() - cached.lastChecked ) < 3600000 ) {
                updateUIForQuota( cached );
                return false;
            }
        }

        var xmlhttp = new XMLHttpRequest();
        xmlhttp.onreadystatechange = function() {
            if (xmlhttp.readyState === XMLHttpRequest.DONE) {
                if (xmlhttp.status === 200 ) {
                    var response = JSON.parse(xmlhttp.responseText);
                    updateUIForQuota(response.data);
                    response.data.lastChecked = Date.now();
                    if ( !noCache ) {
                        window.localStorage.setItem( "cPQuotaStatus", JSON.stringify(response.data) );
                    }
                }
            }
        };

        var uri = "/json-api/quota_enabled?api.version=1";
        if (window.COMMON.securityToken) {
            uri =  window.COMMON.securityToken + uri;
        }
        xmlhttp.open("GET", uri, true);
        xmlhttp.send();
    }

    /**
     * Initialize Topframe JavaScript code
     *
     * @method init
     */
    var init = function() {

        var logoutLink = document.getElementById("lnkLogout");
        loadLiveEl = document.getElementById("loadlive");

        if (!logoutLink && !loadLiveEl) {
            return;
        }

        logoutLink.addEventListener("click", logoutWHM);

        // Cache the load sub-elements for updates
        loadLiveOne = loadLiveEl.querySelector("#lavg_one");
        loadLiveFive = loadLiveEl.querySelector("#lavg_five");
        loadLiveFifteen = loadLiveEl.querySelector("#lavg_fifteen");

        // Initializing _LAST_ACTIVITY
        setLastActivity();

        // Update Load Average
        getLoadAverage();
        checkQuota();

        addVisibilityListener();

        // Attach handlers click and keyup to keep updating last activity
        attachLoadAvg();

        if (window.COMMON.hasRootPrivileges) {
            checkUpdateAvailability();
        }
    };

    window.addEventListener("content-container-init", init);

})();
/*
# master_templates/master.js                         Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

(function(window) {
    "use strict";

    /**
     * Helper class to manage slide out menus. The container passed, must
     * have a .slideContainer, a .slideTab and a .slidPanel element.
     *
     * @class SlideMenu
     * @param {string} containerId Container where the SlideMenu will run.
     */
    var SlideMenu = function(containerId) {

        this.supportContainer = document.getElementById(containerId);
        this.slideToggleClass = "show";
        this.slideIcon = null;
        this.slideIconLink = null;
        this.slidePanel = null;
    };

    SlideMenu.prototype = {

        /**
         * Initializes the slide menu for the given container.
         *
         * @method init
         */
        init: function() {
            if (this.supportContainer !== null) {
                this.slideContainer = this.supportContainer.querySelector(".slideContainer");
                this.slideIcon = this.supportContainer.querySelector(".slideTab");
                this.slideIconLink = this.supportContainer.querySelector(".slideTab a");
                this.slidePanel = this.slideContainer.querySelector(".slidePanel");
                this._attachEvents();
                this.initializeGlobalListeners();
            }
        },

        /**
         * Helps in attaching events to the slide icon click & mouse out.
         *
         * @method _attachEvents ( private method )
         */
        _attachEvents: function() {

            // called when window has loaded.
            // attach events to links on the page. Send the current SlideMenu instance as
            // an added argument

            var slideMenu = this;

            this.slideIcon.addEventListener("click", function() {
                slideMenu.handleIconClick();
            }, false);
        },

        /**
         * Initializes keys that need to be recognized across all frames
         *
         * @method initializeGlobalListeners
         */
        initializeGlobalListeners: function() {
            var frames = this.getAllFrames();
            var slideObj = this;

            var handleKeyDown = function(keyEvent) {

                // keyCode 113 is F2 key
                if (keyEvent.keyCode === 113 && keyEvent.altKey) {
                    slideObj.handleSupportKey(keyEvent, slideObj);
                }
            };

            // Build our globalKeyListener object using the context of our available frames
            for (var i = 0, len = frames.length; i < len; i++) {

                // Case 82249: The Lastpass Chrome extension creates a (hidden)
                // frame on the webpage that is accessed in this loop.  This causes
                // a security error, since an https:// protocol frame is accessing
                // data from a non-https:// frame.  The uncaught exception prevents
                // pages like "installssl" in WHM from fully running, breaking
                // functionality.
                try {
                    frames[i].document.addEventListener("keydown", handleKeyDown, false);
                } catch (e) {

                    // Do Nothing
                }
            }
        },

        /**
         * Utility method to check to see whether a HTMLElement uses a specific class.
         *
         * @method hasClass
         * @element {HTMLElement} element to check
         * @classToCheck {string} class name to check
         */
        hasClass: function(element, classToCheck) {
            return element.className.indexOf(classToCheck) > -1;
        },

        /**
         * Utility method to add a class to a HTMLElement.
         *
         * @method addClass
         * @element {HTMLElement} element to modify
         * @classToAdd {string} class name to add to className property
         */
        addClass: function(element, classToAdd) {
            var classNames = element.className.split(" ");

            if (classNames.indexOf(classToAdd) === -1) {
                classNames.push(classToAdd);
                element.className = classNames.join(" ");
            }
        },

        /**
         * Utility method to remove a class from a HTMLElement.
         *
         * @method removeClass
         * @element {HTMLElement} element to modify
         * @classToRemove {string} class name to remove from className property
         */
        removeClass: function(element, classToRemove) {
            var classNames = element.className.split(" ");
            var stylePosition = classNames.indexOf(classToRemove);

            if (stylePosition > -1) {
                classNames = classNames.splice(stylePosition - 1, 1);
                element.className = classNames.join(" ");
            }
        },

        /**
         * Event handler for the slide tab focus event. This adds a hover style to the slide icon.
         *
         * @method handleSlideTabFocus
         * @e {object} slide link's focus event
         */
        handleSlideTabFocus: function() {
            this.addClass(this.slideIcon, "active");
        },

        /**
         * Event handler for the slide link's blur event. This removes the hover style to the slide icon.
         *
         * @method handleSlideTabBlur
         * @e {object} slide link's blur event
         */
        handleSlideTabBlur: function() {
            this.removeClass(this.slideIcon, "active");
        },

        /**
         * Event handler for the slide icon click event. This toggles the slide menu.
         *
         * @method handleIconClick
         * @e {object} slide icon's click event
         */
        handleIconClick: function() {
            this._toggleSlide();
        },

        /**
         * Keyboard event handler for toggling support slide menu.
         *
         * @method handleSupportKey
         * @e {object} slide icon's click event
         * @slideObj {object} an instance of SlideMenu object.
         */
        handleSupportKey: function(e, slideObj) {
            if (slideObj) {
                slideObj._toggleSlide();
            }
        },

        /**
         * Closes the slide menu and hides it.
         *
         * @method hideSlider
         */
        hideSlider: function() {

            // disable the tab index of all the links in the support panel
            // when the panel is hidden.
            this._setSupportLinksTabIndex("-1");
            this.removeClass(this.slideContainer, this.slideToggleClass);
            this.removeClass(this.slideIcon, "active");
            this.slideIconLink.setAttribute("aria-expanded", "false");
        },

        /**
         * Opens the slide menu and shows it.
         *
         * @method showSlider
         */
        showSlider: function() {

            // enable the tab index of all the links in the support panel
            // when the panel is shown.
            this._setSupportLinksTabIndex("0");
            this.addClass(this.slideContainer, this.slideToggleClass);
            this.addClass(this.slideIcon, "active");
            this.slideIconLink.setAttribute("aria-expanded", "true");
        },

        /**
         * Sets the given tab index for all the links inside the slide panel.
         *
         * @method _setSupportLinksTabIndex ( private method )
         * @indexVal {string} the tab index value to set to.
         */
        _setSupportLinksTabIndex: function(indexVal) {
            var links = this.slidePanel.querySelectorAll("a");

            for (var i = 0; i < links.length; i++) {
                links[i].tabIndex = indexVal;
            }
        },

        /**
         * This method toggles the slide menu.
         *
         * @method _toggleSlide ( private method )
         */
        _toggleSlide: function() {
            if (this.hasClass(this.slideContainer, this.slideToggleClass)) {
                this.hideSlider();
            } else {
                this.showSlider();
            }
        },

        /**
         * Method that can be used to get all frames in the window.
         * If there are not any frames it will return the window
         * deriving its name from the PFILE parameter in the url.
         *
         * @method getAllFrames
         * @return {Array} returns array of frames in the current window
         */
        getAllFrames: function() {
            var frames = [];
            var windowParentFrames = window.parent.frames;
            for (var i = 0, len = windowParentFrames.length; i < len; i++) {
                frames.push(windowParentFrames[i]);
            }

            // Use the window to fill our frames array
            if (frames.length === 0 && window.frames.length === 0) {
                frames[0] = window;

                return frames;
            }

            return frames;
        }
    };

    // supportMenu is the object of type SlideMenu which is used to slide open the Support menu.
    var supportMenu = null;

    /**
     * Initializes all the instances for Slide Menus
     *
     * @method initializeSlideMenus
     */
    function initializeSlideMenus() {
        supportMenu = new SlideMenu("supportContainer");
        supportMenu.init();
    }

    window.addEventListener("content-container-init", initializeSlideMenus);

})(window);
/*
# menu/command.js                                    Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/
/* jshint -W003 */

(function() {
    "use strict";

    // Page direction
    var PAGE_DIRECTION = document.getElementsByTagName("html")[0].getAttribute("dir");

    // Supported HTML Directions
    var HTML_DIRECTIONS = {
        LTR: "ltr",
        RTL: "rtl"
    };

    window.COMMON = window.COMMON || {};

    var NVData = window.COMMON.leftNavNVData || {};
    var securityToken = window.COMMON.securityToken || "";

    /**
     * Polyfill for closest and matches
     * from https://github.com/jonathantneal/closest/blob/master/closest.js
     * http://caniuse.com/#feat=element-closest
     * http://caniuse.com/#feat=matchesselector
     */
    (function(ELEMENT) {
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

    /**
     * Escape regex characters for search text
     * @method RegExp.escape
     * @param {string} text - Search text
     * @return {string} search text with escaped regex characters
     */
    RegExp.escape = function(text) {

        // This ignores any single quote in the search.
        text = text.replace("'", "");
        return text.replace(/[-[\]{}()*+?.,\\^$|#\s]/g, "\\$&");
    };

    /**
     * The commander module provides methods for controlling and manipulating
     * the left navigation.
     *
     * @module commander
     *
     */
    var commander = (function() {

        // This flag is used to prevent selection of active page from breadcrumb
        // when the main frame loads. It is useful for items in the Plugins category
        // which do not have breadcrumb data.
        var preventSelectFromBreadcrumb = false;

        /**
         * Collection of commonly used DOM nodes
         */
        var elements = {};

        /**
         * Check if supplied object is empty
         *
         * @method isEmptyObject
         * @param {object} o Object which is being tested
         * @return {Boolean} Returns true if empty
         */
        function isEmptyObject(o) {
            return !Object.keys(o).length;
        }

        /**
         * Determine if an object is visible in the current viewport
         *
         * @method elementInViewport
         * @param {HTMLElement} el
         * @return {Boolean}
         */
        function elementInViewport(el) {
            var rect = el.getBoundingClientRect(),
                windowWidth = window.innerWidth || document.documentElement.clientWidth,
                windowHeight = window.innerHeight || document.documentElement.clientHeight;

            return (
                rect.top >= 0 &&
                rect.left >= 0 &&
                rect.bottom <= windowHeight &&
                rect.right <= windowWidth
            );
        }

        /**
         * Gets the key code of the event for a KeyboardEvent
         *
         * @method getCharCode
         * @param {Event} event
         * @return {Number} the keycode of the event or 0 if there is none
         */
        function getCharCode(event) {
            return event.keyCode || event.charCode || 0;
        }

        /**
         * Handles adding a class to an element or an array
         * of elements
         * @method addClass
         * @param {String|Array} els - the elements to add classes to
         * @param {String} newClass - the new class you want to add
         */
        function addClass(els, newClass) {
            var currentClasses, newClasses, el;

            // if it is not an array-like value, make it an array
            if (els && !(Array.isArray(els) || els.hasOwnProperty("callee"))) {
                els = [els];
            } else if (els === void 0) {
                els = [];
            }

            for (var i = 0, len = els.length; i < len; i++) {
                el = els[i];

                // support either an element or ID being passed in
                el = (el.tagName !== void 0) ? el : document.getElementById(el);

                currentClasses = el.className || "";
                newClasses = currentClasses;
                if (newClasses.indexOf(newClass) === -1) {
                    newClasses += " " + newClass;
                }
                newClasses = newClasses.trim();
                if (el !== null && newClasses !== currentClasses) {
                    el.className = newClasses;
                }
            }
        }

        /**
         * Handles removing a class from an element or an array
         * of elements
         * @method removeClass
         * @param {String|Array} els - the elements to remove classes from
         * @param {String} oldClass - the old class you want to remove
         */
        function removeClass(els, oldClass) {
            var currentClasses, newClasses, el;

            // if it is not an array-like value, make it an array
            if (els && !(Array.isArray(els) || els.hasOwnProperty("callee"))) {
                els = [els];
            } else if (els === void 0) {
                els = [];
            }

            for (var i = 0, len = els.length; i < len; i++) {
                el = els[i];

                // support either an element or ID being passed in
                el = (el.tagName !== void 0) ? el : document.getElementById(el);

                currentClasses = el.className || "";
                newClasses = currentClasses;

                while (newClasses.indexOf(oldClass) !== -1) {
                    newClasses = newClasses.replace(oldClass, "");
                }
                newClasses = newClasses.trim();
                if (el !== null && newClasses !== currentClasses) {
                    el.className = newClasses;
                }
            }
        }

        /**
         * Determines if an element has the given class
         * @method hasClass
         * @param {Element} el - the element to check for a class
         * @param {String} className - the class to look for
         * @returns {Boolean} true if the element has the desired class
         */
        function hasClass(el, className) {
            return (el && el.nodeType === 1 && el.className.indexOf(className) > -1);
        }

        /**
         * Returns the Y coordinate of the given element
         * @method getY
         * @param {Element} el - the element that you want to get the Y value for
         * @returns {Number} the Y position of the element
         */
        function getY(el) {
            var scrollTop, clientTop, box, y = 0;
            if (!el) {
                return y;
            }

            var body = document.body;
            var docElem = document.documentElement;

            // this part is from YAHOO.util.Dom.isAncestor
            var haystack = el.ownerDocument.documentElement;
            var needle = el;
            var isInDocument = false;

            if ((haystack && needle) && (haystack.nodeType && needle.nodeType)) {
                if (haystack.contains && haystack !== needle) { // contains returns true when equal
                    isInDocument = haystack.contains(needle);
                } else if (haystack.compareDocumentPosition) { // gecko
                    isInDocument = !!(haystack.compareDocumentPosition(needle) & 16);
                }
            }

            // here is where we get the Y value of the current element
            if (el.style.display !== "none" && isInDocument) {
                scrollTop = window.pageYOffset || docElem.scrollTop || body.scrollTop;
                clientTop = docElem.clientTop || body.clientTop || 0;
                box = el.getBoundingClientRect();

                y = box.top + scrollTop - clientTop;
                y = Math.round(y);
            }

            return y;
        }

        /**
         * Locates the nearest ancestor with the given className
         * @method getAncestorByClassName
         * @param {Element} el - the element to begin the search
         * @param {String} className - the class that the ancestor must have
         * @return {Element|null} The ancestor with the given class or null
         */
        function getAncestorByClassName(el, className) {
            if (!el) {
                return null;
            }

            // support either an element or ID being passed in
            var node = (el.tagName !== void 0) ? el : document.getElementById(el);

            // go up the parentNode tree to find a match or until we have a null node
            while ((node = node.parentNode)) {
                if (hasClass(node, className)) {
                    return node;
                }
            }

            // no match, so return null
            return null;
        }

        /**
         * Locates the nearest ancestor with the given tagName
         * @method getAncestorByTagName
         * @param {Element} el - the element to begin the search
         * @param {String} tagName - the tag name that the ancestor must have
         * @return {Element|null} The ancestor with the tag name or null
         */
        function getAncestorByTagName(el, tagName) {
            if (!el) {
                return null;
            }

            // support either an element or ID being passed in
            var node = (el.tagName !== void 0) ? el : document.getElementById(el);

            // go up the parentNode tree to find a match or until we have a null node
            while ((node = node.parentNode)) {
                if (node.tagName && node.tagName.toUpperCase() === tagName.toUpperCase()) {
                    return node;
                }
            }

            // no match, so return null
            return null;
        }

        /**
         * Attaches an event listener to a root element to listen for events
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


        var util = {

            // code to get the current selected page based on breadcrumbs
            // code executes when onload event is fired.
            selectActivePageFromBreadcrumb: function() {

                var breadcrumb = document.getElementById("breadcrumbs_list");
                var listItem = breadcrumb.lastElementChild; // last 'li' in breadcrumb
                var link = listItem.firstElementChild; // anchor inside the last 'li' in breadcrumb
                var activeLink;

                if (commander.preventSelectFromBreadcrumb) {

                    // Prevent active page selection and reset the flag.
                    commander.preventSelectFromBreadcrumb = false;
                    return;
                }

                // iterate through the breadcrumb links until you find the link in left menu item
                do {
                    if (link !== null) {
                        if (link.href.split("=")[1] === "main") {
                            clearActivePageStyle();
                            return;
                        }

                        // get the uniquekey attribute of the current
                        // breadcrumb link
                        var breadCrumbUniqueKey = link.getAttribute("uniquekey"),
                            pageLinks = elements.pageLinks;

                        for (var i = 0, len = pageLinks.length; i < len; i++) {
                            if (breadCrumbUniqueKey === pageLinks[i].getAttribute("uniquekey")) {
                                activeLink = pageLinks[i];
                                break;
                            }
                        }

                        // If activeLink is not found, try to find the parent of the
                        // current breadcrumb.
                        if (typeof activeLink === "undefined") {
                            listItem = listItem.previousElementSibling;

                            if (listItem) {
                                link = listItem.firstElementChild;
                            }
                        }
                    }
                } while (listItem && typeof activeLink === "undefined");

                // set selected link style
                if (activeLink) {
                    selectActivePage(activeLink.parentNode);
                } else {
                    clearActivePageStyle();
                }
            },

            /**
             * Code to get the current selected page when a page icon
             * in the content page is clicked.
             * This is only for pages in PLUGINS Category
             * @method selectActivePageFromPageIcons
             */
            selectActivePageFromPageIcons: function(link) {
                var activeLink;

                // get the uniquekey attribute of the current
                // breadcrum link
                if (link !== null) {
                    var pageIconUniqueKey = link.getAttribute("uniquekey");
                    for (var i = 0, len = elements.pageLinks.length; i < len; i++) {
                        if (pageIconUniqueKey === elements.pageLinks[i].getAttribute("uniquekey")) {
                            activeLink = elements.pageLinks[i];
                            break;
                        }
                    }
                }

                // set selected link style
                if (activeLink) {
                    selectActivePage(activeLink.parentNode);
                    commander.preventSelectFromBreadcrumb = true;
                } else {
                    clearActivePageStyle();
                }
            },

            /**
             * Method that can be used to get all frames in the window.
             * If there are not any frames it will return the window
             * deriving its name from the PFILE parameter in the url.
             *
             * @method getAllFrames
             * @return {Array} returns array of frames in the current window
             */
            getAllFrames: function() {
                var frames = [],
                    parentFrames = window.parent.frames;

                for (var i = 0; i < parentFrames.length; i++) {
                    frames.push(parentFrames[i]);
                }

                // Use the window to fill our frames array
                if (frames.length === 0 && window.frames.length === 0) {
                    frames[0] = window;

                    return frames;
                }

                return frames;
            }
        };

        var searchIndexCache = {};

        // key codes
        var keys = {
            "backspace": 8,
            "escape": 27,
            "up": 38,
            "down": 40,
            "right": 39,
            "left": 37,
            "home": 36,
            "macHome": 115, // fn+left arrow
            "end": 35,
            "macEnd": 119, // fn+right arrow
            "shiftAsterisk": 56,
            "asterisk": 106,
            "forwardslash": 191,
            "tab": 9,
            "grave": 192,
        };

        // CAPS & _
        var NVDATA_ELEMENT_EXPANDED = "1", // Constant used to represent Expanded state
            NVDATA_ELEMENT_COLLAPSED = "0", // Constant used to represent Collapsed currState,
            NVDATA_NAVIGATION_COLLAPSED = "1", // Constant used to represent Collapsed Navigation,
            NVDATA_NAVIGATION_EXPANDED = "0", // Constant used to represent Expanded Navigation,
            HIGHLIGHTED_ITEM_CSS_CLASS = "highlighted";

        // key handle code
        var keyHandle = {

            // Note: we add and remove HIGHLIGHTED_ITEM_CSS_CLASS when user tabs through the left menu
            // so that the styles match the down key and hover styles. Styling :focus
            // for category and subitems have transition issues.
            down: function() {
                var menuItems = elements.menuItems,
                    highlightedItem = elements.highlightedItem,
                    pageIndex = menuItems.indexOf(highlightedItem),
                    nextValidNode;

                // if last item is the currently highlighted item, then
                // stop going further to avoid looping.
                if (typeof pageIndex !== "undefined" && pageIndex + 1 === menuItems.length) {
                    return;
                } else if (pageIndex === -1 || pageIndex + 1 >= menuItems.length) {

                    // if no items are selected we highlight the first item
                    if (typeof pageIndex !== "undefined") {
                        removeClass(menuItems[pageIndex], HIGHLIGHTED_ITEM_CSS_CLASS);
                    }

                    nextValidNode = keyHandle.util.verifyNextNode(menuItems[0], 0);
                    addClass(nextValidNode, HIGHLIGHTED_ITEM_CSS_CLASS);
                    highlightedItem = nextValidNode;
                    keyHandle.util.scrollDownIntoView(nextValidNode);
                } else {
                    nextValidNode = keyHandle.util.verifyNextNode(menuItems[pageIndex + 1], pageIndex + 1);
                    removeClass(menuItems[pageIndex], HIGHLIGHTED_ITEM_CSS_CLASS);
                    addClass(nextValidNode, HIGHLIGHTED_ITEM_CSS_CLASS);
                    highlightedItem = nextValidNode;
                    keyHandle.util.scrollDownIntoView(nextValidNode);
                }
                elements.highlightedItem = highlightedItem;

                // Set focus on the highlighted item
                // Needed for tab and Enter key to work
                setFocusOnHighlightedItem(highlightedItem);
            },
            up: function() {
                var menuItems = elements.menuItems,
                    highlightedItem = elements.highlightedItem,
                    pageIndex = menuItems.indexOf(highlightedItem),
                    previousValidNode;

                // if first item selected stay there
                if (pageIndex <= 0 || typeof pageIndex === "undefined") {
                    if (typeof pageIndex !== "undefined") {
                        removeClass(menuItems[pageIndex], HIGHLIGHTED_ITEM_CSS_CLASS);
                    }
                    addClass(menuItems[0], HIGHLIGHTED_ITEM_CSS_CLASS);
                    highlightedItem = menuItems[0];
                } else {
                    previousValidNode = keyHandle.util.verifyPreviousNode(menuItems[pageIndex - 1], pageIndex - 1);
                    removeClass(menuItems[pageIndex], HIGHLIGHTED_ITEM_CSS_CLASS);
                    addClass(previousValidNode, HIGHLIGHTED_ITEM_CSS_CLASS);
                    highlightedItem = previousValidNode;
                    keyHandle.util.scrollUpIntoView(previousValidNode);
                }

                elements.highlightedItem = highlightedItem;

                // Focus on the highlighted item
                // Needed for Shift+Tab and Enter key to work
                setFocusOnHighlightedItem(highlightedItem);
            },
            shiftTab: function() {
                if (!keyHandle.util.isSearchBoxInFocus()) {
                    if (elements.highlightedItem) {
                        keyHandle.util.scrollUpIntoView(elements.highlightedItem);
                    }
                }
            },
            tab: function() {
                if (!keyHandle.util.isSearchBoxInFocus()) {
                    if (elements.highlightedItem) {
                        keyHandle.util.scrollDownIntoView(elements.highlightedItem);
                    }
                }
            },
            left: function() {
                if (!keyHandle.util.isSearchBoxInFocus()) {
                    var parentCategory = getAncestorByTagName(elements.highlightedItem, "li");
                    if (parentCategory === null) {
                        return;
                    }

                    // Perform action depending on the language direction
                    if (PAGE_DIRECTION === HTML_DIRECTIONS.LTR) {
                        collapseCategory(parentCategory, true);
                        keyHandle.util.highlightCategory(parentCategory);
                    } else if (PAGE_DIRECTION === HTML_DIRECTIONS.RTL) {
                        expandCategory(parentCategory, true);
                    }
                }
            },
            right: function() {
                if (!keyHandle.util.isSearchBoxInFocus()) {
                    var parentCategory = getAncestorByTagName(elements.highlightedItem, "li");
                    if (parentCategory === null) {
                        return;
                    }

                    // Perform action depending on the language direction
                    if (PAGE_DIRECTION === HTML_DIRECTIONS.LTR) {
                        expandCategory(parentCategory, true);
                    } else if (PAGE_DIRECTION === HTML_DIRECTIONS.RTL) {
                        collapseCategory(parentCategory, true);
                        keyHandle.util.highlightCategory(parentCategory);
                    }
                }
            },
            escape: function() {
                clearSearch();
            },
            home: function() {
                if (!keyHandle.util.isSearchBoxInFocus()) {
                    var menuItems = elements.menuItems,
                        nextValidNode;

                    // Clear highlighted item
                    // safety code to avoid having two highlighted items in a menu
                    clearHighlightedItem();

                    // checks if the active element is a menu item or jump up link
                    var commanderHasActiveEl = getAncestorByClassName(document.activeElement, "mainCommandWrapper"),
                        jumpUpHasActiveEl = getAncestorByClassName(document.activeElement, "jumpUp");

                    if (commanderHasActiveEl !== null || jumpUpHasActiveEl !== null) {
                        nextValidNode = keyHandle.util.verifyNextNode(menuItems[0], 0);
                        addClass(nextValidNode, HIGHLIGHTED_ITEM_CSS_CLASS);
                        elements.highlightedItem = nextValidNode;

                        // set focus on the highlighted item
                        // needed to support keyboard navigation
                        setFocusOnHighlightedItem(elements.highlightedItem);
                    }

                }
            },
            end: function() {
                if (!keyHandle.util.isSearchBoxInFocus()) {
                    var menuItems = elements.menuItems,
                        previousValidNode;

                    clearHighlightedItem();

                    // check if the active element is a menu item or jump up link
                    var commanderHasActiveEl = getAncestorByClassName(document.activeElement, "mainCommandWrapper"),
                        jumpUpHasActiveEl = getAncestorByClassName(document.activeElement, "jumpUp");

                    if (commanderHasActiveEl !== null || jumpUpHasActiveEl !== null) {
                        if (menuItems.length > 2) {
                            previousValidNode = keyHandle.util.verifyPreviousNode(menuItems[menuItems.length - 2], menuItems.length - 2);
                            addClass(previousValidNode, HIGHLIGHTED_ITEM_CSS_CLASS);
                            elements.highlightedItem = previousValidNode;

                            // Set focus on the highlighted item
                            // Needed to support keyboard navigation
                            setFocusOnHighlightedItem(elements.highlightedItem);
                        }
                    }
                }
            },
            asterisk: function() {
                if (!keyHandle.util.isSearchBoxInFocus()) {
                    var currState = getExpandedState();

                    if (currState) {
                        var parentCategory = getAncestorByTagName(elements.highlightedItem, "li");

                        collapseAll();
                        if (parentCategory !== null) {
                            keyHandle.util.highlightCategory(parentCategory);
                        }
                    } else {
                        expandAll();
                    }
                }
            },
            grave: function(e) {
                if (e) {
                    e.stopPropagation();
                    e.preventDefault();
                }
                doNavExpandCollapse(e);
            },
            forwardslash: function(e) {

                // check held down modifying keys first
                // set our modifier key
                var modifier = e.ctrlKey;

                // If OS is macintosh system use the command key instead of ctrl
                if (/Mac|iPod|iPhone|iPad/i.test(window.navigator.platform)) {
                    modifier = e.metaKey; // set modifier key to "command"
                }

                if (modifier) {
                    var key = getCharCode(e);
                    if (key === keys.forwardslash) {
                        expandNavigation();
                        searchFocus();
                        e.stopPropagation();
                        e.preventDefault();
                    }
                }
            },

            util: {
                scrollDownIntoView: function(menuItem) {

                    var frameHeight = document.documentElement.clientHeight - elements.searchContainerOffsetHeight,
                        menuItemY = getY(menuItem) - elements.searchContainerOffsetHeight, // Get the "true" Y value for menuItem relative to its container
                        menuItemHeight = menuItem.offsetHeight,
                        frameScrollRatio = Math.floor((frameHeight * 0.75));

                    if (menuItemY > frameScrollRatio) {
                        elements.mainCommandWrapper.scrollTop += menuItemHeight;
                    }
                },
                scrollUpIntoView: function(menuItem) {
                    var frameHeight = document.documentElement.clientHeight - elements.searchContainerOffsetHeight,
                        menuItemY = getY(menuItem) - elements.searchContainerOffsetHeight, // Get the "true" Y value for menuItem relative to its container
                        menuItemHeight = menuItem.offsetHeight,
                        frameScrollRatio = Math.floor((frameHeight * 0.25));

                    if (Math.abs(menuItemY) < frameScrollRatio) {
                        elements.mainCommandWrapper.scrollTop -= menuItemHeight;
                    }
                },
                verifyNextNode: function(nextNode, nextNodeIndex) {
                    var menuItems = elements.menuItems,
                        pageHidden = hasClass(nextNode, "hide"),
                        subHidden = hasClass(nextNode.parentNode, "hide"),
                        catHidden = hasClass(nextNode.parentNode.parentNode, "collapsed");

                    if (typeof nextNode === "undefined") {
                        return menuItems[0];
                    } else if (pageHidden || subHidden || catHidden) {
                        return this.verifyNextNode(menuItems[nextNodeIndex + 1], nextNodeIndex + 1);
                    } else {
                        return menuItems[nextNodeIndex];
                    }
                },
                verifyPreviousNode: function(previousNode, previousNodeIndex) {
                    var menuItems = elements.menuItems,
                        pageHidden = hasClass(previousNode, "hide"),
                        subHidden = hasClass(previousNode.parentNode, "hide"),
                        catHidden = hasClass(previousNode.parentNode.parentNode, "collapsed");

                    if (typeof previousNode === "undefined") {
                        return menuItems[0];
                    } else if (pageHidden || subHidden || catHidden) {
                        return this.verifyPreviousNode(menuItems[previousNodeIndex - 1], previousNodeIndex - 1);
                    } else {
                        return menuItems[previousNodeIndex];
                    }
                },
                preventArrowDefault: function(e) {

                    // Should stop the default events for down and up keys for scroll issue
                    if (getCharCode(e) === keys.down || getCharCode(e) === keys.up) {
                        e.stopPropagation();
                        e.preventDefault();
                    }
                },
                highlightCategory: function(category) {
                    var menuItems = elements.menuItems,
                        pageIndex = menuItems.indexOf(elements.highlightedItem);

                    removeClass(menuItems[pageIndex], HIGHLIGHTED_ITEM_CSS_CLASS);

                    // Focused element and highlighted element should be the same
                    setFocusOnHighlightedItem(category);

                    // Set highlighted style
                    var catHeader = category.querySelector("[data-page-type]");

                    elements.highlightedItem = catHeader;
                    addClass(catHeader, HIGHLIGHTED_ITEM_CSS_CLASS);
                },
                isSearchBoxInFocus: function() {
                    var activeElement = document.activeElement;

                    if (activeElement && activeElement === elements.quickJump) {
                        return true;
                    }
                    return false;
                }
            }
        };

        // keyListener objects
        var keyDownListeners = [{
            "key": keys.down,
            "callback": keyHandle.down
        }, {
            "key": keys.up,
            "callback": keyHandle.up
        }, {
            "key": keys.left,
            "callback": keyHandle.left
        }, {
            "key": keys.right,
            "callback": keyHandle.right
        }, {
            "key": keys.home,
            "callback": keyHandle.home
        }, {
            "key": keys.macHome,
            "callback": keyHandle.home
        }, {
            "key": keys.end,
            "callback": keyHandle.end
        }, {
            "key": keys.macEnd,
            "callback": keyHandle.end
        }, {
            "key": keys.tab,
            "callback": keyHandle.shiftTab,
            "shift": true
        }, {
            "key": keys.tab,
            "callback": keyHandle.tab
        }];

        var keyUpListeners = [{
            "key": keys.escape,
            "callback": keyHandle.escape
        }];

        function triggerOnKeyDownMatch(event) {
            var iterator;
            var code = getCharCode(event);

            // see if the keydown matches any of the keys we are looking for
            for (var i = 0, len = keyDownListeners.length; i < len; i++) {
                iterator = keyDownListeners[i];

                if (iterator.shift === void 0) {
                    iterator.shift = false;
                }

                // if we have a match, call the callback for that key and then exit
                if (code === iterator.key && event.shiftKey === iterator.shift) {
                    iterator.callback.apply(event);
                    break;
                }
            }
        }

        function triggerOnKeyUpMatch(event) {
            var iterator = keyUpListeners[0];
            var code = getCharCode(event);

            // if we have a match, call the callback for that key and then exit
            if (code === iterator.key) {
                iterator.callback.apply(event);
            }
        }

        /**
         * Initialize search textbox
         * enables keyboard listeners
         * hooks onclick, onfocus events for various controls
         * builds search index
         * stripes menu items
         *
         * @method initialize
         */
        function initialize() {

            elements = {
                quickJump: document.getElementById("quickJump"),
                searchAction: document.getElementById("searchAction"),
                toggleAllControl: document.getElementById("toggleAll"),
                list: document.getElementById("mainCommand"),
                jumpUpLink: document.getElementById("jumpUpLink"),
                highlightedItem: null,
                body: document.body,
                collapseNavLink: document.getElementById("mobileMenuCollapseLink"),
                pageLinks: []
            };

            // These elements are dependent on the previous elements being established.
            elements.topFrameWrapper = document.querySelector(".topFrameWrapper");
            elements.topFrameWrapperOffsetHeight = elements.topFrameWrapper && elements.topFrameWrapper.offsetHeight || 0;

            elements.commandWrapper = document.querySelector(".commandContainer");
            elements.mainCommandWrapper = document.querySelector(".mainCommandWrapper");

            elements.menuItems = Array.prototype.slice.call(elements.list.querySelectorAll("[data-page-type]"));

            // Add the jump up pseudo list item to the menuItems list so it is accessible by keyboard navigation
            elements.menuItems.push(elements.jumpUpLink.parentNode);

            elements.categories = Array.prototype.slice.call(elements.list.querySelectorAll(".category"));
            elements.categoryHeaders = elements.menuItems.filter(function(item) {
                return item.getAttribute("data-page-type") === "category";
            });

            elements.categoryHeaderLinks = Array.prototype.slice.call(elements.list.querySelectorAll("[data-page-type='category'] > a"));

            elements.pages = Array.prototype.slice.call(elements.list.querySelectorAll("ul.sub li[data-page-type='feature']"));
            elements.categoryPageLinks = Array.prototype.slice.call(elements.list.querySelectorAll("ul.sub > li[data-page-type='feature'] > a"));

            elements.expandAll = elements.toggleAllControl.querySelector("a.expand");
            elements.collapseAll = elements.toggleAllControl.querySelector("a.collapse");

            elements.searchContainer = document.querySelector(".commandContainer > div.searchContainer");
            elements.searchContainerOffsetHeight = elements.searchContainer.offsetHeight;

            // All anchors in the left menu [Category Headers + Category Pages]
            elements.pageLinks.push.apply(elements.pageLinks, elements.categoryHeaderLinks);
            elements.pageLinks.push.apply(elements.pageLinks, elements.categoryPageLinks);

            elements.menuOffsetHeightDeductions = elements.searchContainerOffsetHeight + elements.topFrameWrapperOffsetHeight;

            elements.activePage = null;

            if (elements.quickJump.value) {
                elements.quickJump.value = "";
            }

            // expand/collapse category event
            delegate(elements.list, "click", "li.category .categoryHeader .actionIconContainer", doExpandCollapse);

            // expand all
            elements.expandAll.addEventListener("click", expandAll);

            // collapse all
            elements.collapseAll.addEventListener("click", collapseAll);

            // focus event for expand all is used only to clear the highlighted item
            // while shift tabbing from first menu item to expand all button.
            elements.expandAll.addEventListener("focus", blurHandler); // expand all

            elements.categoryPageLinks.forEach(function(category) {

                // select page on click
                category.addEventListener("click", pageLinkClickHandler);

                // the focus event on category page to highlight items
                // when focusing the items using tab & shift+tab keys
                category.addEventListener("focus", focusHandler);
            });

            elements.categoryHeaderLinks.forEach(function(categoryHeader) {

                // the focus event on category header links to highlight items
                // when focusing the items using tab & shift+tab keys
                categoryHeader.addEventListener("focus", focusHandler);
            });

            elements.jumpUpLink.addEventListener("focus", focusHandler);

            // the blur event on Back To Top link(jumpUpLink) ensures that it
            // looses the highlight once the focus goes off to the elements outside
            // the menu items.
            elements.jumpUpLink.addEventListener("blur", blurHandler);

            // jump to top of #mainCommander
            elements.jumpUpLink.addEventListener("click", jumpToTop);

            // clear search box
            elements.searchAction.addEventListener("click", clearSearch);

            // clear highlighted item when focused on search text box
            elements.quickJump.addEventListener("focus", clearHighlightedItem);

            // KeyHandle listeners
            // prevent the down/up arrows from scrolling the left ('commander') frame
            elements.commandWrapper.addEventListener("keydown", keyHandle.util.preventArrowDefault);
            elements.quickJump.addEventListener("keyup", searchTextHandler);

            // enable all keylisteners
            elements.commandWrapper.addEventListener("keyup", triggerOnKeyUpMatch);
            elements.commandWrapper.addEventListener("keydown", triggerOnKeyDownMatch);
            document.addEventListener("keydown", keyHandle.forwardslash);

            if (elements.collapseNavLink) {
                elements.collapseNavLink.addEventListener("click", doNavExpandCollapse);
            }

            document.addEventListener("keydown", function(event) {
                var tag = event.target.tagName.toLowerCase();
                if (tag === "input" || tag === "select" || tag === "textarea") {
                    return;
                }

                var code = getCharCode(event);

                if (code === keys.asterisk || code === keys.shiftAsterisk) {
                    keyHandle.asterisk.apply(this, event);
                    return false;
                }

            });

            document.addEventListener("keyup", function(event) {
                var tag = event.target.tagName.toLowerCase();
                if (tag === "input" || tag === "select" || tag === "textarea") {
                    return;
                }

                var code = getCharCode(event);

                if (code === keys.grave) {
                    keyHandle.grave.apply(this, event);
                    return false;
                }

            });

            if (screen.width <= 768) {
                collapseNavigation();
            } else {
                collapseNavigationByNVData(); // expand or collapse the navigation based on NVdata
            }
            collapseCommand(); // set the categories to expand/collapse based on NVdata
            searchFocus(); // focus on search box
            buildIndex(elements.pages, "idgen"); // build our search index

            // Search retention across tab session
            if (storedSearchTermExists()) {
                if (storedUserNameExists()) {
                    if (typeof window.COMMON.userName !== "undefined") {
                        if (sessionStorage.userName === window.COMMON.userName) {
                            elements.quickJump.value = sessionStorage.searchTerm;
                            var result = searchMenu(elements.quickJump.value);
                            searchResults(result);
                        } else {
                            delete sessionStorage.userName;
                            delete sessionStorage.searchTerm;
                        }
                    }
                }
            }

            if (elements.collapseNavLink) {
                util.selectActivePageFromBreadcrumb();
            }
        }

        function storedSearchTermExists() {
            if (typeof sessionStorage.searchTerm !== "undefined") {
                if (sessionStorage.searchTerm !== "") {
                    return true;
                }
            }
            return false;
        }

        function storedUserNameExists() {
            if (typeof sessionStorage.userName !== "undefined") {
                if (sessionStorage.userName !== "") {
                    return true;
                }
            }
            return false;
        }

        /**
         * Set focus in the search text box
         *
         * @method searchFocus
         */

        function searchFocus() {
            elements.quickJump.focus();

            if (elements.quickJump.value !== "") {
                elements.quickJump.value = elements.quickJump.value;
            }
        }

        /**
         * Handles click event for page links in a category
         *
         * @method pageLinkClickHandler
         * @param {Event} e - event object
         */

        function pageLinkClickHandler() {
            var uniqueKey = this.getAttribute("uniquekey");

            /**
             * Page links under Plugins category are handled
             * specially. Since plugins do not have breadcrumbs support,
             * we set the flag 'preventSelectFromBreadcrumb' to true.
             * This helps 'SelectActivePageFromBreadcrumb' method to handle
             * plugins correctly.
             */
            var isInPlugin = /^plugins_/.test(uniqueKey);

            if (isInPlugin) {
                var parentCategory = getAncestorByClassName(this, "category");
                if (parentCategory && parentCategory.id === "Plugins") {
                    commander.preventSelectFromBreadcrumb = true;
                } else {
                    commander.preventSelectFromBreadcrumb = false;
                }
            }

            selectActivePage(this.parentNode);
        }

        /**
         * Handles all focus events
         *
         * @method focusHandler
         * @param {Event} e - the event object
         */
        function focusHandler() {
            var menuItems = elements.menuItems,
                highlightedItem = this.parentNode,
                pageIndex = menuItems.indexOf(highlightedItem);

            // Check if the highlighted item is set in
            // down, up, home OR end key handlers
            if (highlightedItem === elements.highlightedItem) {
                return;
            }

            clearHighlightedItem();

            if (pageIndex !== -1 && pageIndex + 1 <= menuItems.length) {
                addClass(highlightedItem, HIGHLIGHTED_ITEM_CSS_CLASS);
                elements.highlightedItem = highlightedItem;
            }
        }

        /**
         * Clear the highlighted event on blur
         *
         * @method blurHandler
         * @param {Event} e - the event object
         */
        function blurHandler() {
            clearHighlightedItem();
        }

        /**
         * Select active page by settting active page style
         * and highlight that page as highlighted item.
         *
         * @method selectActivePage
         * @param {HTMLElement} activeEl selected anchor
         */
        function selectActivePage(activeEl) {

            // Make sure we do not apply the active class twice so that animation(css3) goes smoothly
            if (activeEl === elements.activePage) {
                return true;
            }

            // Set the highlighted item
            var menuItems = elements.menuItems,
                highlightedItem = activeEl,
                pageIndex = menuItems.indexOf(activeEl);

            if (typeof pageIndex !== "undefined" && pageIndex >= 0) {
                _setActivePageStyle(activeEl);
                clearHighlightedItem();
                addClass(highlightedItem, HIGHLIGHTED_ITEM_CSS_CLASS);

                // Set focus on the highlighted item
                // Needed for tab and Enter key to work
                setFocusOnHighlightedItem(highlightedItem);
                elements.highlightedItem = highlightedItem;
                elements.activePage = activeEl;
            }
        }

        /**
         * Set selected item style
         *
         * @method _setActivePageStyle
         * @param {HTMLElement} activeLinkEl selected anchor
         */
        function _setActivePageStyle(activeLinkEl) {

            // If the active link is not an 'a' element, find it and use it.
            if (typeof activeLinkEl !== "undefined" && activeLinkEl.tagName !== "A") {
                activeLinkEl = activeLinkEl.querySelector("a");
            }

            if (activeLinkEl && activeLinkEl.target === "") {

                // show hidden active element by expanding it's parent category
                if (activeLinkEl.parentNode.getAttribute("data-page-type") === "feature") {
                    var parentCategory = getAncestorByClassName(activeLinkEl, "category");

                    if (parentCategory && hasClass(parentCategory, "collapsed")) {
                        removeClass(parentCategory, "collapsed");
                        addClass(parentCategory, "expanded");
                    }
                }

                clearActivePageStyle();

                // we have to set a timeout in order to properly animate when a hidden page is shown
                window.setTimeout(function() {
                    addClass(activeLinkEl.parentNode, "activePage");
                }, 1);

                // safety check to make sure the active link is in the viewport
                if (!elementInViewport(activeLinkEl)) {

                    /* Get the "true" Y value for menuItem relative to its container
                     *  Note: getY() will return a negative number if the element
                     *  is above the current element and hidden from the visible scroll
                     *  area so we always get the abs value.
                     */
                    var menuItemY = Math.abs(getY(activeLinkEl)) - elements.menuOffsetHeightDeductions;

                    elements.mainCommandWrapper.scrollTop = Math.abs(menuItemY); // Put the activeLinkEl at the top of the left menu

                }
            }
        }

        /**
         * clear selected item style
         *
         * @method clearActivePageStyle
         */
        function clearActivePageStyle() {
            var activePage = elements.list.querySelector(".activePage");

            // If the active page is null don't try to manipulate the DOM
            if (activePage !== null) {
                removeClass(activePage, "activePage");
            }

            clearHighlightedItem();
        }

        /**
         * Loops through all the categories until it finds the first expanded category
         * and returns true else it returns false.
         *
         * @method getExpandedState
         * @return {Boolean} returns true when it finds the first expanded category
         */
        function getExpandedState() {
            var searchIsActive = elements.quickJump.value === "" ? false : true;

            // We need this to decide if we want to loop through DOM or NVData for getting expanded state.
            var nVDataIsEmpty = isEmptyObject(NVData);
            var match;

            if (searchIsActive || nVDataIsEmpty) { // filter only shown categories to do the expanded state check.
                var categoryList = elements.categories.filter(function(item) {
                    return !hasClass(item, "hide");
                });
                for (var i = 0; i < categoryList.length; i++) {
                    if (hasClass(categoryList[i], "expanded")) {
                        return true;
                    }
                }
            } else {

                // Check all the categories when search is not active.
                // Looping through the nvdata is the fastest approach.
                // However, we need to make sure we only include menu items that are in the DOM.
                // NVData can have something which may not be displayed and would affect the state.
                // For example, the "Plugins" category.
                for (var nvd in NVData) {
                    if (NVData.hasOwnProperty(nvd)) {
                        match = nvd.match(/^whmcommand:(.*)/);
                        if (match.length > 0) {
                            if (NVData[nvd] === NVDATA_ELEMENT_EXPANDED &&
                                document.getElementById(match[1]) !== null) {
                                return true;
                            }
                        }
                    }
                }
            }

            return false;
        }

        /**
         * Toggles the actionIconContainer's title attribute of a given category
         *
         * @method toggleTitle
         * @param {String | HTMLElement} el The parent category
         * @return {Array} The items that were changed
         */
        function toggleTitle(category) {
            var actionIconContainer;
            var categoryID = (typeof (category) === "string") ? category : category.id;
            var categoryEl = document.getElementById(categoryID + "Header");
            if (categoryEl) {
                actionIconContainer = categoryEl.querySelectorAll("div.actionIconContainer");
                for (var i = 0, len = actionIconContainer.length; i < len; i++) {
                    actionIconContainer[i].title = (actionIconContainer[i].title === "Expand") ? "Collapse" : "Expand";
                }
            }
            return actionIconContainer;
        }

        /**
         * Collapses a category to hide its sub menu.
         *
         * @method collapseCategory
         * @param {HTMLElement} category The category you wish to collapse
         * @param {Boolean} report Whether or not to report the change to the server to store in NVData
         * @return {Boolean} A pass/fail boolean
         */
        function collapseCategory(category, report) {
            if (hasClass(category, "expanded")) {
                removeClass(category, "expanded");
                addClass(category, "collapsed");
                toggleTitle(category);

                if (report) {
                    setnvdata("whmcommand:" + category.id, NVDATA_ELEMENT_COLLAPSED);
                }
                return true;
            }
            return false;
        }

        /**
         * Expands a category to show its sub menu.
         *
         * @method expandCategory
         * @param {HTMLElement} category The category you wish to expand
         * @param {Boolean} report Whether or not to report the change to the server to store in NVData
         * @return {Boolean} A pass/fail boolean
         */
        function expandCategory(category, report) {
            if (hasClass(category, "collapsed")) {
                removeClass(category, "collapsed");
                addClass(category, "expanded");
                toggleTitle(category);

                if (report) {
                    setnvdata("whmcommand:" + category.id, NVDATA_ELEMENT_EXPANDED);
                }
                return true;
            }
            return false;
        }

        /**
         * Adds hide CSS class to the category
         *
         * @method hideCategory
         * @param {HTMLElement} category The category you wish to hide
         */
        function hideCategory(category) {
            addClass(category, "hide");
        }

        /**
         * Removes hide CSS class from the category
         *
         * @method showCategory
         * @param {HTMLElement} category The category you wish to show
         */
        function showCategory(category) {
            removeClass(category, "hide");
        }

        /**
         * Expand or Collapse node
         * expanded elements will have the class 'expanded'
         * collapsed elements will have the class 'collapsed'
         *
         * @method doExpandCollapse
         * @param {event} event
         */
        function doExpandCollapse(event) {
            var parentCategory = event.target.closest("li");

            if (hasClass(parentCategory, "expanded")) {
                collapseCategory(parentCategory, true);
            } else {
                expandCategory(parentCategory, true);
            }
        }

        /**
        * Read NVData to determine which categories are to be expanded on load
        * NVData is set in master_template/_defheader in the format
            var NVData = {
                "whmcommand:Account_Functions": "1",
                "whmcommand:Server_Configuration": "0"
            };
        * where "1" is expanded and "0" is collapsed
        *
        * @method collapseCommand
        */
        function collapseCommand() {
            var nvset = {};
            for (var nvd in NVData) {
                if (nvd.match(/^whmcommand:/)) {
                    if (NVData[nvd] === NVDATA_ELEMENT_COLLAPSED) {
                        var categoryID = (nvd.split(":"))[1];
                        collapseCategory(document.getElementById(categoryID), false);
                    }
                }
            }
        }

        function doNavExpandCollapse() {
            if (hasClass(elements.body, "nav-collapsed")) {
                expandNavigation();
                window.dispatchEvent(new CustomEvent("toggle-navigation", { detail: "expand" }));
            } else {
                collapseNavigation();
                window.dispatchEvent(new CustomEvent("toggle-navigation", { detail: "collapse" }));
            }
        }

        function _mobileCategoryHeaderClicked(e) {
            e.stopPropagation();
            e.preventDefault();

            expandNavigation();
            var parentCategory = getAncestorByTagName(e.target, "li");
            if (parentCategory === null) {
                return;
            }

            expandCategory(parentCategory, true);
            var menuItemY = Math.abs(getY(parentCategory)) - elements.menuOffsetHeightDeductions;
            elements.mainCommandWrapper.scrollTop = Math.abs(menuItemY);

        }

        function expandNavigation() {
            if (hasClass(elements.body, "nav-collapsed")) {
                removeClass(elements.body, "nav-collapsed");

                // remove override on nav links
                elements.categoryHeaderLinks.forEach(function(element) {
                    element.removeEventListener("click", _mobileCategoryHeaderClicked);
                });

                // Focus on search box
                searchFocus();

                setnvdata("whmcommand:navigation", NVDATA_NAVIGATION_EXPANDED);

                return true;
            }
            return false;
        }

        function collapseNavigation() {
            if (!hasClass(elements.body, "nav-collapsed")) {
                addClass(elements.body, "nav-collapsed");

                // Override <a> links for navigation items
                elements.categoryHeaderLinks.forEach(function(element) {
                    element.addEventListener("click", _mobileCategoryHeaderClicked);
                });

                setnvdata("whmcommand:navigation", NVDATA_NAVIGATION_COLLAPSED);

                return true;
            }
            return false;
        }

        function collapseNavigationByNVData() {
            for (var nvd in NVData) {
                if (nvd === "whmcommand:navigation") {
                    if (NVData[nvd] === NVDATA_NAVIGATION_COLLAPSED) {
                        collapseNavigation();
                    }
                }
            }
        }

        /**
         * Expand all items of the menu and set the nvdata accordingly
         *
         * @method expandAll
         */
        function expandAll() {
            var categories = elements.categories,
                nvset = {};

            for (var i = 0, len = categories.length; i < len; i++) {
                if (expandCategory(categories[i], false)) {
                    nvset["whmcommand:" + categories[i].id] = NVDATA_ELEMENT_EXPANDED;
                }
            }
            if (!isEmptyObject(nvset)) {
                multisetnvdata(nvset);
            }
        }

        /**
         * Collapse all items of the menu and set the nvdata accordingly
         *
         * @method collapseAll
         */
        function collapseAll() {
            var categories = elements.categories,
                nvset = {};

            for (var i = 0, len = categories.length; i < len; i++) {
                if (collapseCategory(categories[i], false)) {
                    nvset["whmcommand:" + categories[i].id] = NVDATA_ELEMENT_COLLAPSED;
                }
            }

            if (!isEmptyObject(nvset)) {
                multisetnvdata(nvset);
            }
        }

        /**
         * sets multiple key value pairs to nvdata
         *
         * @method multisetnvdata
         */
        function multisetnvdata(keypairs) {
            var postdata = "";
            for (var nvkey in keypairs) {
                if (keypairs.hasOwnProperty(nvkey)) {
                    NVData[nvkey] = keypairs[nvkey];
                    postdata += "key=" + encodeURIComponent(nvkey) + "&value=" + encodeURIComponent(keypairs[nvkey]) + "&";
                }
            }
            var request = new XMLHttpRequest();
            request.open("POST", securityToken + "/json-api/nvset", true);
            request.send(postdata);
        }

        /**
         * set nvdata
         *
         * @method setnvdata
         * @param {string} key - the nvdata key
         * @param {string} value - the value for the nvdata key
         */
        function setnvdata(key, value) {
            NVData[key] = value;
            var request = new XMLHttpRequest();
            request.open("GET", securityToken + "/json-api/nvset?key=" + encodeURIComponent(key) + "&value=" + encodeURIComponent(value), true);
            request.send();
        }

        /**
         * removes highlighted item style from the menu items
         *
         * @method clearHighlightedItem
         */
        function clearHighlightedItem() {

            // clear the highlighted item
            if (elements.hightlightedItem !== null) {
                var menuItems = elements.menuItems,
                    pageIndex = menuItems.indexOf(elements.highlightedItem);

                removeClass(menuItems[pageIndex], HIGHLIGHTED_ITEM_CSS_CLASS);
                elements.highlightedItem = null;
            }
        }

        /**
         * sets focus on the anchor of the highlighted item
         *
         * @method setFocusOnHighlightedItem
         * @param {HTMLElement} highlightedItem - the element to focus on
         */
        function setFocusOnHighlightedItem(highlightedItem) {
            if (highlightedItem !== null) {
                var highlightedLink = highlightedItem.querySelector("a");

                if (highlightedLink) {
                    highlightedLink.focus();
                }
            }
        }

        /**
         * Handler method for search text box
         * focus event.
         *
         * @method searchTextHandler
         * @param {FocusEvent} e - the Focus Event
         */
        function searchTextHandler(e) {

            // clear highlighted item when searching
            clearHighlightedItem();

            // Override the down key so that we can move out of the quickJump with the down arrow.
            if (getCharCode(e) === keys.down || getCharCode(e) === keys.escape) {
                return;
            }

            // Search left nav's searchIndexCache
            var results = searchMenu(elements.quickJump.value);
            searchResults(results);
        }

        /**
         * Search menu items
         * @method searchMenu
         * @param {string} searchTerm - text to filter the menu items against
         * @return {Array} Array of matched elements ID's
         */
        function searchMenu(searchTerm) {

            // An extra check to see if the search text has just spaces. Avoid searching
            // in this case.

            var emptySpace = /^\s+$/g.test(searchTerm),
                results = [];

            if (!emptySpace) {

                // Store the search term across page load.
                sessionStorage.searchTerm = searchTerm || "";
                sessionStorage.userName = window.COMMON.userName || "";

                var term = RegExp.escape(searchTerm),
                    matchCount = 0;
                if (term.length) {
                    removeClass(elements.searchAction, "search");
                    addClass(elements.searchAction, "cancel");
                    for (var pageID in searchIndexCache) {
                        if (searchIndexCache.hasOwnProperty(pageID)) {
                            var re = new RegExp(term, "ig");
                            if (searchIndexCache[pageID].match(re)) {
                                results.push(pageID);
                                matchCount++;
                            } else {
                                addClass(pageID, "hide");
                            }
                        }
                    }
                    if (matchCount <= 0) {

                        // When the search result is empty and all items are hidden,
                        // hide the containing <ul> element too. This fixes the
                        // extra blank space that is seen on the screen.
                        addClass(elements.list, "hideMainCommand");
                    } else {
                        removeClass(elements.list, "hideMainCommand");
                    }
                } else {
                    clearSearch();
                }
            }
            return results;
        }

        /**
         * Display search results.
         *
         * @method searchResults
         * @param {String Array} termArr - the searched term.
         */
        function searchResults(termArr) {

            // Search left nav's searchIndexCache
            if (termArr.length) {

                // Hide all categories
                for (var i = 0, len = elements.categories.length; i < len; i++) {
                    hideCategory(elements.categories[i]);
                }

                // Unhide our matched results
                removeClass(termArr, "hide");

                // Show our results' parent categories
                for (i = 0, len = termArr.length; i < len; i++) {
                    var matchedCategory = getAncestorByTagName(termArr[i], "li");
                    if (matchedCategory) {
                        showCategory(matchedCategory);
                        expandCategory(matchedCategory, false);
                    }
                }
            }
        }

        /**
         * clear search items
         *
         * @method clearSearch
         */
        function clearSearch() {
            var categories = elements.categories,
                activePage = elements.activePage;

            clearHighlightedItem();
            removeClass(elements.searchAction, "cancel"); // switch icon back to search state
            addClass(elements.searchAction, "search"); // switch icon back to search state
            removeClass(elements.pages, "hide"); // unhide all pages
            removeClass(elements.pages, "even"); // clear current stripe state
            removeClass(elements.list, "hideMainCommand");

            // show all the categories
            for (var i = 0, len = categories.length; i < len; i++) {
                showCategory(categories[i]);
            }

            collapseCommand(); // reset category state based on NVdata
            elements.quickJump.value = "";
            searchFocus();

            // expand active page category if in collapsed state
            if (activePage !== null && activePage.parentNode.getAttribute("data-page-type") === "feature") {
                var parentCategory = getAncestorByClassName(activePage, "category");
                if (parentCategory && hasClass(parentCategory, "collapsed")) {
                    removeClass(parentCategory, "collapsed");
                    addClass(parentCategory, "expanded");
                }
            }
            if (storedSearchTermExists()) {
                delete sessionStorage.searchTerm;
            }
        }

        /**
         * generates ids for an array of nodes using provided genPrefix
         * prefix = 'idgen' will result in idgen0, idgen1, ..
         * builds a index of all search terms to be searched through
         *
         * @method buildIndex
         * @param {Array} pages - the items in the menu that are represent pages
         * @param {string} prefix - a string to prefix the IDs of the elements
         */
        function buildIndex(pages, prefix) {
            for (var i = 0, len = pages.length; i < len; i++) {
                pages[i].id = prefix + i;
                searchIndexCache[pages[i].id] = pages[i].getAttribute("searchtext").replace("’", "");
            }
        }

        /**
         * scroll to top of the page
         *
         * @method jumpToTop
         */
        function jumpToTop() {
            clearHighlightedItem();
            elements.highlightedItem = elements.menuItems[elements.menuItems.length];
            keyHandle.down();
        }

        return {
            initialize: initialize,
            elements: elements,
            keyHandle: keyHandle,
            clearSearch: clearSearch,
            searchIndexCache: searchIndexCache,
            searchMenu: searchMenu,
            util: util,
            preventSelectFromBreadcrumb: preventSelectFromBreadcrumb,
            elementInViewport: elementInViewport,
            getY: getY,
            doNavExpandCollapse: doNavExpandCollapse
        };
    })();

    window.addEventListener("content-container-init", commander.initialize);

    // NOTE: QA uses commander elementInViewport in one of its library modules.
    // Leaving it exposed to window at this point.
    window.commander = commander;

})();
