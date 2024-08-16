// Copyright 2023 cPanel, L.L.C. - All rights reserved.
// copyright@cpanel.net
// https://cpanel.net
// This code is subject to the cPanel license. Unauthorized copying is prohibited

/**
 * @example
 * Dispatch an event named "breadcrumbSetCrumbs" with the payload
 *
 * dispatchEvent(new CustomEvent('breadcrumbSetCrumbs', {
 *     bubbles: true,
 *     detail: {
 *       separator: ">",
 *       crumbs: [
 *	        {
 *              displayName: "",
 *              longName: "",
 *              link: ""
 *	        }
 *      ]
 *      }
 *   })
 *);
 *
 * Listen for event "breadcrumbNavigate" to pick up on user clicks of a breadcrumb element. Payload (e["detail"]):
 * {
 *      link: ""
 * }
 */

(function() {
    "use strict";

    /**
     * Breadcrumb class that handles all of logic for creating a breadcrumb DOM element
    */
    function Breadcrumb() {
        this.crumbs = [];
        this.crumbId = -1;
    }

    Breadcrumb.prototype = {

        /**
         * Adds an id to the array of breadcrumbs that was in the action
         * @param {Object[]} arrOfCrumbs Array of breadcrumbs to have an id added
        */
        setBreadcrumbId: function(arrOfCrumbs) {
            this.crumbs = [];
            this.crumbs = arrOfCrumbs.map(function(crumb, i) {
                this.crumbId++;
                return {
                    id: "breadcrumbItem_" + i,
                    displayName: crumb.displayName,
                    longName: crumb.longName,
                    link: crumb.link,
                    isRealHref: crumb.isRealHref,
                };
            }, this);
        },

        /**
         * Creates the breadcrumb DOM fragment.
         * @param {Object[]} arrOfCrumbs Array of breadcrumbs to have an id added
         * @param {string} separator A string of characters to be used for separating each breadcrumb
         * @throws Will throw an error when the container element is not present.
        */
        buildBreadcrumbFragment: function(arrOfCrumbs, separator) {
            var breadcrumbContainer = document.getElementById("cpanel-breadcrumbs");
            if (!breadcrumbContainer) {
                throw "Missing parent container for breadcrumbs";
            }

            // Note: Temporary solution to make breadcrumbs work with bootstrap5.
            // TODO: Create a breadcrumb component that works in all technologies
            var isJupiterStyle = breadcrumbContainer.getAttribute("data-jupiter-style");

            separator = separator || "/";
            this.setBreadcrumbId(arrOfCrumbs);
            var breadcrumbDOMFragment = document.createDocumentFragment();
            breadcrumbContainer.appendChild(breadcrumbDOMFragment);

            for (var i = 0; i < this.crumbs.length; i++) {
                var crumbsLength = this.crumbs.length;
                var crumb = this.crumbs[i];
                var element = this.createAnElement(crumb, i, crumbsLength);

                breadcrumbDOMFragment.appendChild(element);

                // eslint-disable-next-line eqeqeq
                if (isJupiterStyle == null) {
                    var separatorElement = this.createSeparatorElement(separator);

                    // Check that there are more than 1 breadcrumb and it's not on the last element before adding a separator element
                    if (
                        crumbsLength > 1 && i < crumbsLength - 1
                    ) {
                        breadcrumbDOMFragment.appendChild(separatorElement);
                    }
                }

            }

            breadcrumbContainer.textContent = "";
            breadcrumbContainer.appendChild(breadcrumbDOMFragment);

            // Display the element in case it was hidden previously
            breadcrumbContainer.style = "display: flex";
        },

        /**
         * The logic for deciding what type of element to create for the breadcrumb fragment.
         * @param {Object} crumb A specific breadcrumb JS object
         * @param {number} position The position of the breadcrumb JS object in the breadcrumb array
         * @param {number} length The length of the breadcrumb array
        */
        createAnElement: function(crumb, position, length) {

            // One item make it only a span with no link
            if (length === 1) {
                return this.createParentSpanElement(crumb);
            }

            // Make an anchor element that shows on mobile for the 2nd to last element in list
            if (position === (length - 2)) {
                return this.createParentAnchorElement(crumb);
            }

            // Make the last element a span without an anchor tag. Different from above because it hides on mobile
            if (position === (length - 1)) {
                return this.createLastSpanElement(crumb);
            }
            return this.createMiddleAnchorElement(crumb);
        },

        /**
         * Creates the seperator element for the breadcrumb fragment being created.
         * @param {string} separatorString String of characters used to separate each breadcrumb element.
        */
        createSeparatorElement: function(separatorString) {
            var separatorElement = document.createElement("span");
            separatorElement.setAttribute("class", "hidden-xs breadcrumb-separator");
            separatorElement.textContent = separatorString;
            return separatorElement;
        },

        /**
         * Creates a span element without an anchor tag.
         * @param {Object} crumb A specific breadcrumb JS object
        */
        createParentSpanElement: function(crumb) {
            var span = document.createElement("span");
            span.setAttribute("id", crumb.id);
            span.setAttribute("aria-current", "page");
            span.setAttribute("class", "breadcrumb-item");
            span.textContent = crumb.displayName;
            return span;
        },

        /**
         * Creates a span element without an anchor tag that is hidden on a mobile view.
         * @param {Object} crumb A specific breadcrumb JS object
        */
        createLastSpanElement: function(crumb) {
            var element = this.createParentSpanElement(crumb);
            element.setAttribute("class", "breadcrumb-item hidden-xs d-none d-sm-block");
            return element;
        },

        /**
         * Creates an anchor element that does not navigate and dispatches an event when clicked.
         * @param {Object} crumb A specific breadcrumb JS object
        */
        createParentAnchorElement: function(crumb) {
            var anchor = document.createElement("a");
            anchor.textContent = crumb.displayName;

            // This stops the anchor tag from doing anything and allows angular to handle routing
            var linkHref = "javascript:;";
            var isRealHref = Object.hasOwn(crumb, "isRealHref") && crumb.isRealHref;
            if ( isRealHref ) {
                linkHref = crumb.link;
            }
            anchor.setAttribute("href", linkHref);
            anchor.setAttribute("id", crumb.id);
            anchor.setAttribute("class", "breadcrumb-item");
            if ( Object.hasOwn( crumb, "longName" ) && crumb.longName ) {
                anchor.setAttribute("title", crumb.longName);
            }
            anchor.addEventListener("click", function(e) {
                anchor.dispatchEvent(new CustomEvent("breadcrumbNavigate", {
                    bubbles: true,
                    detail: {
                        link: crumb.link,
                    },
                }));
            });
            return anchor;
        },

        /**
         * Creates an anchor element that also hides on mobile.
         * @param {Object} crumb A specific breadcrumb JS object
        */
        createMiddleAnchorElement: function(crumb) {
            var element = this.createParentAnchorElement(crumb);
            element.setAttribute("class", "hidden-xs breadcrumb-item d-none d-sm-block");
            return element;
        },
    };

    function appendHelpLink(helpLink) {
        var breadcrumbContainer = document.getElementById("cpanel-breadcrumbs");
        var helpElem = document.createElement("a");
        helpElem.setAttribute( "href", helpLink );
        helpElem.setAttribute( "target", "_blank" );
        helpElem.setAttribute( "style", "text-decoration:none;" );
        var helpIcon = document.createElement("span");
        helpIcon.setAttribute( "title", "Documentation" ); // XXX TODO: Localize?
        helpIcon.setAttribute( "class", "ri-question-line" );
        helpIcon.setAttribute( "style", "margin-left:.25rem;width:1rem;height:1rem;color:black;");
        helpElem.appendChild(helpIcon);
        breadcrumbContainer.appendChild(helpElem);
    }

    var breadcrumb = new Breadcrumb();

    /**
     * Adds event listener to global window for setting breadcrumbs
    */
    document.addEventListener("breadcrumbSetCrumbs", function(e) {
        breadcrumb.buildBreadcrumbFragment(e.detail.crumbs, e.detail.separator);

        // Add help link if provided
        if ( Object.hasOwn(e.detail, "help") && e.detail.help ) {
            appendHelpLink(e.detail.help);
        }
    });
})();
