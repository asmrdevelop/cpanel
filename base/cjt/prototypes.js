// THIS FILE CONTAINS ONLY CUSTOM ADDITIONS TO BUILT-IN JAVSCRIPT PROTOTYPES.
// COMPATIBILITY FUNCTIONS TO PROTOTYPES GO IN compatibility.js.

(function() {

    /**
     * This module contains extesions to the standard Javascript String object.
     * @module  String Extensions
     */

    /**
     * Left pads the string with leading characters. Will use spaces if
     * the padder parameter is not defined. Will pad with "0" if the padder
     * is 0.
     * @method  lpad
     * @param  {Number} len    Length of the padding
     * @param  {String} padder Characters to pad with.
     * @return {String}        String padded to the full width defined by len parameter.
     */
    String.prototype.lpad = function(len, padder) {
        if (padder === 0) {
            padder = "0";
        } else if (!padder) {
            padder = " ";
        }

        var deficit = len - this.length;
        var pad = "";
        var padder_length = padder.length;
        while (deficit > 0) {
            pad += padder;
            deficit -= padder_length;
        }
        return pad + this;
    };

    /**
     * Reverse the characters in a string.
     * @return {String} New string with characters reversed.
     */
    String.prototype.reverse = function() {
        return this.split("").reverse().join("");
    };

    // add html_encode functionality to the String object
    // Copying the logic found in YUI 2.9.0 YAHOO.lang.escapeHTML()
    var html_chars = {
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#x27;",
        "/": "&#x2F;",
        "`": "&#x60;"
    };

    var html_chars_regex = /[&<>"'\/`]/g;
    var html_function = function(match) {
        return html_chars[match];
    };

    /**
     * Encode the string using html encoding rules
     * @method  html_encode
     * @return {String} Encoded html string.
     */
    String.prototype.html_encode = function() {
        return this.replace(html_chars_regex, html_function);
    };

    // Perl has \Q\E for this, but JS offers no such nicety.
    var escapees_regexp = /([\\^$*+?.()|{}\[\]])/g;

    /**
     * Encode the regular expression.
     * @method  regexp_encode
     * @return {String} Encoded regular expression
     */
    String.prototype.regexp_encode = function() {
        return this.replace(escapees_regexp, "\\$1");
    };
})();

(function() {

    /**
     * This module contains extesions to the standard Javascript Array object.
     * @module  Array Extensions
     */


    // COMPARABLE TO SQL SORTS: EACH ARGUMENT SPECIFIES A "TRANSFORM" FUNCTION
    // THAT GENERATES A COMPARISON VALUE FOR EACH MEMBER OF THE ARRAY.
    //
    // OR, YOU CAN WRITE A PROPERTY OR METHOD NAME AS A STRING.
    // INDICATE REVERSAL WITH A '!' AS THE FIRST CHARACTER.
    //
    // EXAMPLE: SORT DATES BY MONTH, BACKWARDS BY YEAR, AND SOMETHING ELSE
    // BY DOING THIS:
    // datesArray.sort_by('getMonth','!getYear',function (d) { ... })
    //
    // FOR GENERIC REVERSAL OF A TRANSFORM FUNCTION,
    // DEFINE A reverse PROPERTY ON IT AS true.
    Array.prototype.sort_by = function() {
        var this_length = this.length;

        if (this_length === 0) {
            return this;
        }

        var xformers = [];
        var xformers_length = arguments.length;
        for (var s = 0; s < xformers_length; s++) {
            var cur_xformer = arguments[s];

            var xformer_func;
            var reverse = false;

            if (cur_xformer instanceof Function) {
                xformer_func = cur_xformer;
                reverse = cur_xformer.reverse || false;
            } else {
                reverse = ((typeof cur_xformer === "string" || cur_xformer instanceof String) && cur_xformer.charAt(0) === "!");
                if (reverse) {
                    cur_xformer = cur_xformer.substring(1);
                }

                var referenced = this[0][cur_xformer];
                var isFunc = (referenced instanceof Function);
                xformer_func = isFunc ?
                    function(i) {
                        return i[cur_xformer]();
                    } :
                    function(i) {
                        return i[cur_xformer];
                    };
            }

            xformer_func.reverse_val = reverse ? -1 : 1;

            xformers.push(xformer_func);
        }

        var xformed_values = [];
        for (var i = 0; i < this_length; i++) {
            cur_value = this[i];
            var cur_xformed_values = [];
            for (var x = 0; x < xformers_length; x++) {
                cur_xformed_values.push(xformers[x](cur_value));
            }
            cur_xformed_values.push(i); // Do this for cross-browser stable sorting.
            cur_xformed_values.item = cur_value;
            xformed_values.push(cur_xformed_values);
        }

        var index, _xformers_length, first_xformed, second_xformed;
        var sorter = function(first, second) {
            index = 0;
            _xformers_length = xformers_length; // save on scope lookups
            while (index < _xformers_length) {
                first_xformed = first[index];
                second_xformed = second[index];
                if (first_xformed > second_xformed) {
                    return (1 * xformers[index].reverse_val);
                } else if (first_xformed < second_xformed) {
                    return (-1 * xformers[index].reverse_val);
                }
                index++;
            }
            return 0;
        };

        xformed_values.sort(sorter);

        for (var xv = 0; xv < this_length; xv++) {
            this[xv] = xformed_values[xv].item;
        }

        return this;
    };

    /**
     * Finds all the unique items in the Array returning them as a new Array.
     * @method  unique
     * @return {Array} Unique items in the array as determined by ===
     * @source http://www.martienus.com/code/javascript-remove-duplicates-from-array.html
     */
    Array.prototype.unique = function() {
        var r = [];

        bigloop: for (var i = 0, n = this.length; i < n; i++) {
            for (var x = 0, y = r.length; x < y; x++) {
                if (r[x] === this[i]) {
                    continue bigloop;
                }
            }
            r[y] = this[i];
        }

        return r;
    };

    /**
     * Extends the Array object to be able to retrieve
     * the smallest element in the array by value.
     * @method  max
     * @return {Object} the smallest element in the array
     * by value using < comparison.
     */
    Array.prototype.min = function() {
        var min = this[this.length - 1];
        for (var i = this.length - 2; i >= 0; i--) {
            if (this[i] < min) {
                min = this[i];
            }
        }

        return min;
    };

    /**
     * Extends the Array object to be able to retrieve
     * the largest element in the array by value.
     * @method  max
     * @return {Object} the largest element in the array
     * by value using > comparison.
     */
    Array.prototype.max = function() {
        var max = this[this.length - 1];
        for (var i = this.length - 2; i >= 0; i--) {
            if (this[i] > max) {
                max = this[i];
            }
        }

        return max;
    };

})();
