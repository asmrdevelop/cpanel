/*
# cpanel - whostmgr/docroot/templates/collapsible_wrapper/collapsible_wrapper.js
#                                                  Copyright 2022 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* eslint-disable new-cap, camelcase, strict */
/**
 * @module CollapsibleWrapper
 **/
(function() {
    var handleSectionClick = function(event) {
        event.preventDefault();

        event.currentTarget.classList.toggle("active");

        // eslint-disable-next-line no-use-before-define
        var content = getNextSibling(event.currentTarget, ".content");

        content.style.display = content.style.display === "block" ? "none" : "block";

        // eslint-disable-next-line no-use-before-define
        updateIcon(event.currentTarget.querySelector("i"));
    };

    var getNextSibling = function(elem, selector) {
        var sibling = elem.nextElementSibling;
        if (!selector) {
            return sibling;
        }

        while (sibling) {
            if (sibling.matches(selector)) {
                return sibling;
            }
            sibling = sibling.nextElementSibling;
        }
    };

    var updateIcon = function(element) {
        var iconClassList = element.classList;
        iconClassList.toggle("fa-chevron-down");
        iconClassList.toggle("fa-chevron-up");
    };

    window.addEventListener("load", function() {
        var collapsibles = document.querySelectorAll(".collapsible-wrapper:not(.collapsible--disabled)");
        var disabledCollapsibles = document.querySelectorAll(".collapsible--disabled");

        collapsibles.forEach(function(collapsible) {
            collapsible.addEventListener("click", function(event) {
                handleSectionClick(event);
            });
        });

        disabledCollapsibles.forEach(function(collapsible) {
            collapsible.addEventListener("click", function(event) {
                event.preventDefault();
            });
        });
    });

})();
