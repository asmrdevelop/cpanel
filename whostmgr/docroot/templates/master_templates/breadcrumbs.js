/* global $:false */

(function() {

    /**
     * Breadcrumb client side API. To use the client side API you must include jquery.
     * @requires jquery
     * @class Breadcrumb
     * @constructor
     */
    function Breadcrumb() {
        this.breadcrumbs = null;
    }

    Breadcrumb.prototype = {

        /**
         * Get the breadcrumbs collection.
         *
         * @class Breadcrumb
         * @method getBreadcrumbs
         * @return {Object} Wrapped UL tag
         */
        getBreadcrumbs: function() {

            // Defend against users that didn't include Jquery
            if (typeof ($) === "undefined") {
                if (window && window.console) {
                    window.console.log("You must include a version of Jquery to use the breadcrum client API.");
                    throw ("You must include a version of Jquery to use the breadcrum client API.");
                }
            }

            if (!this.breadcrumbs) {
                this.breadcrumbs = $("#breadcrumbs_list");
            }
            return this.breadcrumbs;
        },

        /**
         * Update breadcrumb link to page-specific documentation. Also updates
         * documentation menu item in Lifesaver menu.
         *
         * @class Breadcrumb
         * @method updateDocLink
         * @param {String} name Name of documentation page
         * @return {object} docsBreadcrumb updated
         */
        updateDocLink: function(name) {
            var docsUrl = "https://go.cpanel.net/whmdocs" + encodeURIComponent(name.replace(/\W+/g, ""));
            $("#docs-link").attr("href", docsUrl);
            var docMenuItem = $("#docs-menu-item");
            if (docMenuItem) {
                docMenuItem.attr("href", docsUrl);
            }
        },

        /**
         * Push a new breadcrumb on the stack.
         *
         * @class Breadcrumb
         * @method push
         * @param  {String} name Name to show
         * @param  {String} link Link to navigate to if clicked.
         * @param  {String} [tags] Optional tags to add to the li.
         */
        push: function(name, link, tags) {
            var last = this.getLeaf();
            var lastHref = last.find("a:last-child");
            var parentUniqueKey = lastHref.attr("uniquekey");
            lastHref.removeClass("leafNode");
            var separator = $("<span>&nbsp;&raquo;</span>");
            last.append(separator);
            var newLast = $("<li><a class='leafNode' href='" + link + "'" + (parentUniqueKey ? " uniquekey='" + parentUniqueKey + "'" : "") + "'><span>" + name + "</span></a></li>");
            this.setData(newLast, name, tags);
            last.after(newLast);
            this.updateDocLink(name);
        },

        /**
         * Pop the leaf breadcrumb off the stack.
         *
         * @class Breadcrumb
         * @method pop
         */
        pop: function() {
            var last = this.getLeaf();
            last.remove();
            last = this.getLeaf();
            last.find("a").addClass("leafNode");
            last.children("span").remove();
            this.updateDocLink(this.getLeafName());
        },

        /**
         * Update the leaf breadcrumb with new name and link.
         *
         * @class Breadcrumb
         * @method update
         * @param  {String} name Name to show
         * @param  {String} link Link to navigate to if clicked.
         * @param  {String} [tags] Optional tags to add to the li.
         */
        update: function(name, link, tags) {
            var last = this.getLeaf();
            this.setData(last, name, tags);
            var lastHref = last.find("a");
            lastHref.attr("href", link);
            lastHref.find("span").html(name);
            this.updateDocLink(name);
        },

        /**
         * Sets name and tag data on the given element.
         *
         * @class Breadcrumb
         * @param {Object} elem         A jQuery wrapped element
         * @param {String} name         The name for the breadcrumb
         * @param {Array|String} tags   Tag(s) for this breadcrumb
         */
        setData: function(elem, name, tags) {
            if (!$.isArray(tags)) {
                tags = [tags];
            }

            elem.data({
                name: name,
                tags: tags
            });

            return elem;
        },

        /**
         * Check if the leaf node has a particular tag
         *
         * @class Breadcrumb
         * @method leafHasTag
         * @param  {String} tag Tag to look for on the leaf node.
         * @return {Boolean}    true if the leaf has the tag, false otherwise.
         */
        leafHasTag: function(tag) {
            var tags = this.getLeaf().data("tags");
            return tags ? tags.indexOf(tag) > -1 : false;
        },

        /**
         * Fetch the leaf node.
         *
         * @class Breadcrumb
         * @method getLeaf
         * @return {Object} Warped LI tag.
         */
        getLeaf: function() {
            var breadcrumbs = this.getBreadcrumbs();
            return breadcrumbs.find("li:not(#docs-crumb)").filter(":last");
        },

        /**
         * Fetch the name of the leaf without any additional conent
         *
         * @class Breadcrumb
         * @method getLeafName
         * @return {String}    The unadulterated name of the leaf
         */
        getLeafName: function() {
            return this.getLeaf().data("name");
        },

        /**
         * Fetch the url of the leaf node.
         *
         * @class Breadcrumb
         * @method getLeafHref
         * @return {String} url the leaf node navigates too.
         */
        getLeafHref: function() {
            return this.getLeaf().find("a").attr("href");
        },

        /**
         * Fetch the text of the leaf node.
         *
         * @class Breadcrumb
         * @method getLeafText
         * @return {String} url the leaf node navigates too.
         */
        getLeafText: function() {
            return this.getLeaf().find("span").text();
        },

        /**
         * Fetch the unique key of the leaf node. Unique keys are used to find the
         * related left menu item associated with this element.
         *
         * @class Breadcrumb
         * @method getLeafUniqueKey
         * @return {String} unique key of the the leaf node.
         */
        getLeafUniqueKey: function() {
            return this.getLeaf().find("a").attr("uniquekey");
        }
    };


    /**
    * Handles breadcrumb rendering on page load.
    *
    * @method breadcrumbContentHandler
    * @param {e} event object
    */
    function breadcrumbContentHandler(e) {

        // Publish the breadcrumb API to the window
        window.breadcrumb = new Breadcrumb();
    }

    document.addEventListener("DOMContentLoaded", breadcrumbContentHandler);

}());
