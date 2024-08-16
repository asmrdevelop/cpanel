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
