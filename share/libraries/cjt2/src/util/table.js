/*
# cpanel - cjt/util/table.js                      Copyright(c) 2020 cPanel, L.L.C.
#                                                           All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* global define: false */

define(
    [
        "lodash",
        "cjt/util/locale",
    ],
    function(_, LOCALE) {

        /**
         * Creates a Table object which handles search/sort/paging functionality for
         * client-side data. Does not support search/sort/paging via an AJAX call at this point.
         * It is expected to be used with an array of objects.
         * It is expected to be used with one table, that is 1 Table object for 1 Table being displayed.
         *
         * @class
         */
        function Table() {
            this.items = [];
            this.filteredList = this.items;
            this.selected = [];
            this.allDisplayedRowsSelected = false;
            this.searchFunction = void 0;
            this.filterOptionFunction = void 0;

            this.meta = {
                sortBy: "",
                sortDirection: "asc",
                totalItems: 0,
                pageNumber: 1,
                pageSize: 10,
                pageSizes: [10, 20, 50, 100],
                start: 0,
                limit: 0,
                searchText: "",
                filterOption: ""
            };

            // NOTE: This is only here since it is used by our apps to set the
            // max-pages setting in the ui-bootstrap uib-pagination directive
            this.meta.maxPages = 0;

            this.last_id = 0;
        }

        /**
         * Load data into the table
         *
         * @method load
         * @param {Array} data - an array of objects representing the data to display
         */
        Table.prototype.load = function(data) {
            if (!_.isArray(data)) {
                throw "Developer Exception: load requires an array";
            }

            // reset the last id
            this.last_id = 0;

            this.items = data;

            for (var i = 0, len = this.items.length; i < len; i++) {
                if (!_.isObject(this.items[i])) {
                    throw "Developer Exception: load requires an array of objects";
                }

                // add a unique id to each piece of data
                this.items[i]._id = i;

                // initialize the selected array with the ids of selected items
                if (this.items[i].selected) {
                    this.selected.push(this.items[i]._id);
                }
            }

            this.last_id = i;
        };

        /**
         * Set the search function to be used for searching the table. It is up to
         * the implementor to define how this will work. We are just providing a hook
         * point here.
         *
         * @method setSearchFunction
         * @param {Function} func - a function that can be used to search the data
         * @note The function passed to this function must
         * - return a boolean
         * - accept the following args: an item object and the search text
         */
        Table.prototype.setSearchFunction = function(func) {
            if (!_.isFunction(func)) {
                throw "Developer Error: setSearchFunction requires a function";
            }

            this.searchFunction = func;
        };

        /**
         * Set the filter option function. This is intended to be used with a
         * way to apply filters to the data in the interface (e.g. pre-defined
         * values like Most Used or Most Recent). It is up to the implementor to
         * define how this will work. We are just providing a hook point here.
         *
         * @method setFilterOptionFunction
         * @param {Function} func - a function that can be used to filter data
         * @note The function passed to this function must
         * - return a boolean
         * - accept the following args: an item object and the search text
         */
        Table.prototype.setFilterOptionFunction = function(func) {
            if (!_.isFunction(func)) {
                throw "Developer Error: setFilterOptionFunction requires a function";
            }

            this.filterOptionFunction = func;
        };


        /**
         * Set the sort by and direction for the data
         *
         * @method setSort
         * @param {String} by - the field(s) you want to sort on. you can specify multiple fields
         * by separating them with a comma
         * @param {String} direction - the direction you want to sort, "asc" or "desc"
         */
        Table.prototype.setSort = function(by, direction) {
            if (!_.isUndefined(by)) {
                this.meta.sortBy = by;
            }

            if (!_.isUndefined(direction)) {
                this.meta.sortDirection = direction;
            }
        };

        /**
         * Get the table metadata
         *
         * @method getMetadata
         * @return {Object} The metadata for the table. We return a
         * reference here so that callers can update the object and
         * changes can easily be propagated.
         */
        Table.prototype.getMetadata = function() {
            return this.meta;
        };

        /**
         * Get the table data
         *
         * @method getList
         * @return {Array} The table data
         */
        Table.prototype.getList = function() {
            return this.filteredList;
        };

        /**
         * Get the table data that is selected
         *
         * @method getSelectedList
         * @return {Array} The table data that is selected
         */
        Table.prototype.getSelectedList = function() {
            return this.items.filter(function(item) {
                return item.selected;
            });
        };

        /**
         * Determine if all the filtered table rows are selected
         *
         * @method areAllDisplayedRowsSelected
         * @return {Boolean}
         */
        Table.prototype.areAllDisplayedRowsSelected = function() {
            return this.allDisplayedRowsSelected;
        };

        /**
         * Get the total selected rows in the table
         *
         * @method getTotalRowsSelected
         * @return {Number} total of selected rows in the table
         */
        Table.prototype.getTotalRowsSelected = function() {
            return this.selected.length;
        };

        /**
         * Select all items for a single page of data in the table
         *
         * @method selectAllDisplayed
         */
        Table.prototype.selectAllDisplayed = function() {

            // Select the rows if they were previously selected on this page.
            for (var i = 0, filteredLen = this.filteredList.length; i < filteredLen; i++) {
                var item = this.filteredList[i];
                item.selected = true;

                // make sure this item is not already in the list
                if (this.selected.indexOf(item._id) !== -1) {
                    continue;
                }

                this.selected.push(item._id);
            }

            this.allDisplayedRowsSelected = true;
        };

        /**
         * Unselect all items for a single page of data in the table
         *
         * @method unselectAllDisplayed
         */
        Table.prototype.unselectAllDisplayed = function() {

            // Extract the unselected items and remove them from the selected collection.
            var unselected = this.filteredList.map(function(item) {
                item.selected = false;
                return item._id;
            });

            this.selected = _.difference(this.selected, unselected);
            this.allDisplayedRowsSelected = false;
        };

        /**
         * Select an item on the current page.
         *
         * @method selectItem
         * @param {Object} item - the item that we want to mark as selected.
         */
        Table.prototype.selectItem = function(item) {
            if (_.isUndefined(item)) {
                return;
            }

            item.selected = true;

            // make sure this item is not already in the list
            if (this.selected.indexOf(item._id) !== -1) {
                return;
            }

            this.selected.push(item._id);

            // Check if all of the displayed rows are now selected
            this.allDisplayedRowsSelected = this.filteredList.every(function(thisitem) {
                return thisitem.selected;
            });
        };

        /**
         * Unselect an item on the current page.
         *
         * @method unselectItem
         * @param {Object} item - the item that we want to mark as unselected.
         */
        Table.prototype.unselectItem = function(item) {
            if (_.isUndefined(item)) {
                return;
            }

            item.selected = false;

            // remove this item from the list of selected items
            this.selected = this.selected.filter(function(thisid) {
                return thisid !== item._id;
            });

            this.allDisplayedRowsSelected = false;
        };

        /**
         * Clear all selections for all pages.
         *
         * @method clearAllSelections
         */
        Table.prototype.clearAllSelections = function() {
            this.selected = [];

            for (var i = 0, len = this.items.length; i < len; i++) {
                var item = this.items[i];
                item.selected = false;
            }

            this.allDisplayedRowsSelected = false;
        };

        /**
         * Clear the entire table.
         *
         * @method clear
         */
        Table.prototype.clear = function() {
            this.items = [];
            this.selected = [];
            this.last_id = 0;
            this.allDisplayedRowsSelected = false;
            this.update();
        };

        /**
         * Update the table with data accounting for filtering, sorting, and paging
         *
         * @method update
         * @return {Array} the table data
         */
        Table.prototype.update = function() {
            var filtered = [];
            var self = this;

            // search the data if search text is specified
            if (this.meta.searchText !== null &&
                this.meta.searchText !== void 0 &&
                this.meta.searchText !== "" &&
                this.searchFunction !== void 0) {
                filtered = this.items.filter(function(item) {
                    return self.searchFunction(item, self.meta.searchText);
                });
            } else {
                filtered = this.items;
            }

            // apply a filter to the list if one is specified
            if (this.meta.filterOption !== null &&
                this.meta.filterOption !== void 0 &&
                this.meta.filterOption !== "" &&
                this.filterOptionFunction !== void 0) {
                filtered = filtered.filter(function(item) {
                    return self.filterOptionFunction(item, self.meta.filterOption);
                });
            }

            // sort the filtered list
            // Check for multiple sort fields separated by a comma
            var sort_options = this.meta.sortBy.split(",");
            if (this.meta.sortDirection !== "" && sort_options.length) {
                filtered = _.orderBy(filtered, sort_options, [this.meta.sortDirection]);
            }

            // update the total items
            this.meta.totalItems = filtered.length;

            // page the data accordingly or display it all.
            // we need to check the page sizes here since the page sizes can change based on the
            // number of items in our list (the pageSizeDirective does this).
            if (this.meta.totalItems > _.min(this.meta.pageSizes) ) {
                var start = (this.meta.pageNumber - 1) * this.meta.pageSize;
                var limit = this.meta.pageNumber * this.meta.pageSize;

                filtered = _.slice(filtered, start, limit);

                this.meta.start = start + 1;
                this.meta.limit = start + filtered.length;
            } else {
                if (filtered.length === 0) {
                    this.meta.start = 0;
                } else {
                    this.meta.start = 1;
                }

                this.meta.limit = filtered.length;
            }

            // select the appropriate items
            var countNonSelected = 0;
            for (var i = 0, filteredLen = filtered.length; i < filteredLen; i++) {
                var item = filtered[i];

                // Select the rows if they were previously selected on this page.
                if (this.selected.indexOf(item._id) !== -1) {
                    item.selected = true;
                } else {
                    item.selected = false;
                    countNonSelected++;
                }
            }

            this.filteredList = filtered;

            // Clear the 'Select All' checkbox if at least one row is not selected.
            this.allDisplayedRowsSelected = (filtered.length > 0) && (countNonSelected === 0);

            return filtered;
        };

        /**
         * Add an item to the table.
         *
         * @method add
         * @param {Object} item - the item that we want to add to the list.
         */
        Table.prototype.add = function(item) {
            if (!_.isObject(item)) {
                throw "Developer Exception: add requires an object";
            }

            // update our internal ID counter
            this.last_id++;
            item._id = this.last_id;

            this.items.push(item);
            this.update();
        };

        /**
         * Remove an item from the table.
         * If the object exists in the table more than once, only the first instance is removed.
         *
         * @method remove
         * @param {Object} item - the item that we want to remove from the list.
         */
        Table.prototype.remove = function(item) {
            if (!_.isObject(item)) {
                throw "Developer Exception: remove requires an object";
            }

            var found = false;
            if (item.hasOwnProperty("_id")) {
                for (var i = 0, len = this.items.length; i < len; i++) {
                    if (this.items[i]._id === item._id) {
                        found = true;
                        break;
                    }
                }

                if (found) {
                    this.items.splice(i, 1);
                    this.update();
                }
            }
        };

        /**
         * Create a localized message for the table stats
         *
         * @method paginationMessage
         * @return {String}
         */
        Table.prototype.paginationMessage = function() {
            return LOCALE.maketext("Displaying [numf,_1] to [numf,_2] out of [quant,_3,item,items]", this.meta.start, this.meta.limit, this.meta.totalItems);
        };

        return Table;
    }
);
