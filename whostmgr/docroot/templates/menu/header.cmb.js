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
