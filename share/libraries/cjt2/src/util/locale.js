/*
# cjt/util/locale.js                                Copyright 2022 cPanel, L.L.C.
#                                                            All rights reserved.
# copyright@cpanel.net                                         http://cpanel.net
# This code is subject to the cPanel license. Unauthorized copying is prohibited
*/

/* --------------------------*/
/* DEFINE GLOBALS FOR LINT
/*--------------------------*/
/* global define:false, console:false, global:false     */
/* --------------------------*/

/* eslint camelcase: 0 */

// TODO: Add tests for these

/**
 *
 * @module cjt/util/locale
 * @example
 *  define(
 *  [
 *      "cjt/util/locale",
 *  ],
 *  function(LOCALE) {
 *      LOCALE.numf(100.1);
 *  });
 *
 * @example
 *
 * The main use case is to get the current selected locale. If you need access to other locales, you
 * must set them up manually by doing the following in a module that brings in cjt2/util/locale. With
 * these you can generate new locales, modify existing locale, etc, though there should be very limited
 * need
 *
 *  define(
 *  [
 *      "cjt/util/locale",
 *  ],
 *  function(LOCALE) {
 *      var manager = LOCALE.get_manager();
 *      if (!manager.has_locale("fr")) {
 *          manager.generateClassFromCldr("fr", {
 *              misc_info: {
 *                  delimiters: {
 *                      quotation_start: "<<",
 *                      quotation_end:   ">>"
 *                  }
 *              }
 *          });
 *      }
 *  }
 *
 */
define(["lodash"], function(_) {
    "use strict";

    /**
     * Utility module for building localized strings.
     *
     * @static
     * @public
     * @class locale
     */


    var DEFAULT_ELLIPSIS = {
        initial: "…{0}",
        medial: "{0}…{1}",
        "final": "{0}…"
    };

    var html_apos = _.escape("'");
    var html_quot = _.escape("\"");
    var html_amp  = _.escape("&");

    /**
     * JS getUTCDay() starts from Sunday, but CLDR starts from Monday.
     * @param  {[type]} the_date [description]
     * @return {[type]}          [description]
     */
    var get_cldr_day = function(the_date) {
        var num = the_date.getUTCDay() - 1;
        return (num < 0) ? 6 : num;
    };

    function Locale() {}
    Locale._locales = {};
    Locale._currentLocaleTag = "";

    /**
     * Get the current locale tag name
     * @return {String} Locale tag name in ISO ??? format.
     */
    Locale.getCurrentLocale = function() {
        return Locale._currentLocaleTag;
    };

    /**
     * Sets the current locale by its tag name.
     * @param {String} tag Locale tag name in ISO ??? format.
     */
    Locale.setCurrentLocale = function(tag) {
        if (tag in Locale._locales.keys()) {
            Locale._currentLocaleTag = tag;
            window.LOCALE = Locale._locales[tag];
        } else {
            // eslint-disable-next-line no-console
            console.log("Failed to locate the requested locale " + tag + " in the loaded locales.");
        }
        return window.LOCALE;
    };

    /**
     * Add a locale to the system
     * @param {String} tag        Locale tag name in ISO ??? format.
     * @param {Function} construc Constructor function for the CLDR instance for this locale.
     */
    Locale.add_locale = function(tag, construc) {
        Locale._locales[tag] = construc;
        Locale._currentLocaleTag = tag; // Assume the last one set is the current locale.
        construc.prototype._locale_tag = tag;
    };

    /**
     * Remove a local from the system
     * @param  {String} tag Locale tag name in ISO ??? format.
     */
    Locale.remove_locale = function(tag) {  // For testing
        return delete Locale._locales[tag];
    };

    /**
     * Remove all locales
     */
    Locale.clear_locales = function(tag) {  // For testing
        Locale._locales = {};
    };

    /**
     * Test if the locale generator or instance exists
     * @param  {String} tag Locale tag name in ISO format.
     */
    Locale.has_locale = function(tag) {
        return !!Locale._locales[tag];
    };

    /**
     * Get a handle to the specified locale, processing the arguments until one is found.
     * You can provide one or more instances tags to attempt. This method will search until
     * if finds one or will return the first one if it cant find any of the ones you passed,
     * or you didn't pass a tag.
     * @param {String...} tag name of the locale to lookup.
     * @return {Object} Locale object containing the CLDR knowledge and string management
     * logic for a given locale.
     */
    Locale.get_handle = function() {
        var cur_arg;
        var arg_count = arguments.length;
        for (var a = 0; a < arg_count; a++) {
            cur_arg = arguments[a];
            if ( cur_arg in Locale._locales ) {
                return new Locale._locales[cur_arg]();
            }
        }

        // We didn't find anything from the given arguments, so check _locales.
        // We can't trust JS's iteration order, so grab keys and take the first one.
        var locale_tags = Object.keys(Locale._locales);
        var loc = locale_tags.length ? locale_tags[0] : false;

        var loc_obj = (loc && Locale._locales[loc] ? new Locale._locales[loc]() : new Locale());
        loc_obj.get_manager = function() {
            return Locale;
        };
        return loc_obj;
    };

    // ymd_string_to_date will be smarter once case 52389 is done.
    // For now, we need the ymd order from the server.
    Locale.ymd = null;

    /**
     * Convert a YYMMDD string to a date object
     * @param  {String} str [description]
     * @return {Date}     [description]
     * @????
     */
    Locale.ymd_string_to_date = function(str) {
        var str_split = str.split(/\D+/);
        var ymd = this.ymd || "mdy";  // U.S. English;

        var day = str_split[ ymd.indexOf("d") ];
        var month = str_split[ ymd.indexOf("m") ];
        var year = str_split[ ymd.indexOf("y") ];

        // It seems unlikely that we'd care about ancient times.
        if ( year && (year.length < 4) ) {
            var deficit = 4 - year.length;
            year = String((new Date()).getFullYear()).substr(0, deficit) + year;
        }

        var date = new Date( year, month - 1, day );
        return isNaN(date.getTime()) ? undefined : date;
    };

    // temporary, until case 52389 is in
    Locale.date_template = null;

    /**
     * Convert a date into a YYMMDD string
     * @param {Date} date [description]
     * @return {String} [description]
     */
    Locale.to_ymd_string = function(date) {
        var template = Locale.date_template || "{month}/{day}/{year}";  // U.S. English
        return template.replace(/\{(?:month|day|year)\}/g, function(subst) {
            switch (subst) {
                case "{day}":
                    return date.getDate();
                case "{month}":
                    return date.getMonth() + 1;
                case "{year}":
                    return date.getFullYear();
            }
        } );
    };

    var bracket_re = /([^~\[\]]+|~.|\[|\]|~)/g;

    // cf. Locale::Maketext re DEL
    var faux_comma = "\x07";
    var faux_comma_re = new RegExp( faux_comma, "g" );

    // For outside a bracket group
    var tilde_chars = { "[": 1, "]": 1, "~": 1 };

    var underscore_digit_re = /^_(\d+)$/;

    var func_substitutions = {
        "#": "numf",
        "*": "quant"
    };

    // NOTE: There is no widely accepted consensus of exactly how to measure data
    // and which units to use for it. For example, some bodies define "B" to mean
    // bytes, while others don't. (NB: SI defines "B" to mean bels.) Some folks
    // use k for kilo; others use K. Some say kilo should be 1,024; others say
    // it's 1,000 (and "kibi" would be 1,024). What we do here is at least in
    // longstanding use at cPanel.
    var data_abbreviations = [ "KB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB" ];

    // NOTE: args *must* be a list, not an Array object (as is permissible with
    // most other functions in this module).

    /**
     * Internal implementation
     * @param  {String} str Source string.
     * @return {String}     Interpolated string.
     */
    var _maketext = function(str /* , args list */) { // ## no extract maketext
        if (!str) {
            return;
        }

        str = this.LEXICON && this.LEXICON[str] || str;

        if ( str.indexOf("[") === -1 ) {
            return String(str);
        }

        var assembled = [];

        var pieces = str.match(bracket_re);
        var pieces_length = pieces.length;

        var in_group = false;
        var bracket_args = "";

        var p, cur_p, a;

        PIECE:
        for (p = 0; p < pieces_length; p++) {
            cur_p = pieces[p];
            if ((cur_p === "[")) {
                if (in_group) {
                    throw "Invalid maketext string: " + str; // ## no extract maketext
                }

                in_group = true;
            } else if ( cur_p === "]" ) {

                if (!in_group || !bracket_args) {
                    throw "Invalid maketext string: " + str; // ## no extract maketext
                }

                in_group = false;

                var real_args = bracket_args.split(",");
                var len = real_args.length;
                var func;

                if ( len === 1 ) {
                    var arg = real_args[0].match(underscore_digit_re);
                    if ( !arg ) {
                        throw "Invalid maketext string: " + str; // ## no extract maketext
                    }

                    var looked_up = arguments[arg[1]];
                    if ( typeof looked_up === "undefined" ) {
                        throw "Invalid argument \"" + arg[1] + "\" passed to maketext string: " + str; // ## no extract maketext
                    } else {
                        bracket_args = "";
                        assembled.push(looked_up);
                        continue PIECE;
                    }
                } else {
                    func = real_args.shift();
                    len -= 1;
                    func = func_substitutions[func] || func;

                    if ( typeof this[func] !== "function" ) {
                        throw "Invalid function \"" + func + "\" in maketext string: " + str; // ## no extract maketext
                    }
                }

                if ( bracket_args.indexOf(faux_comma) !== -1 ) {
                    for (a = 0; a < len; a++) {
                        real_args[a] = real_args[a].replace(faux_comma_re, ",");
                    }
                }

                var cur_arg, alen;

                for (a = 0; a < len; a++) {
                    cur_arg = real_args[a];
                    if ( cur_arg.charAt(0) === "_" ) {
                        if ( cur_arg === "_*" ) {
                            real_args.splice( a, 1 );
                            for (a = 1, alen = arguments.length; a < alen; a++) {
                                real_args.push( arguments[a] );
                            }
                        } else {
                            var arg_num = cur_arg.match(underscore_digit_re);
                            if ( arg_num ) {
                                if ( arg_num[1] in arguments ) {
                                    real_args[a] = arguments[arg_num[1]];
                                } else {
                                    throw "Invalid variable \"" + arg_num[1] + "\" in maketext string: " + str; // ## no extract maketext
                                }
                            } else {
                                throw "Invalid maketext string: " + str; // ## no extract maketext
                            }
                        }
                    }
                }

                bracket_args = "";
                assembled.push( this[func].apply(this, real_args) );
            } else if ( cur_p.charAt(0) === "~" ) {
                var real_char = cur_p.charAt(1) || "~";
                if ( in_group ) {
                    if (real_char === ",") {
                        bracket_args += faux_comma;
                    } else {
                        bracket_args += real_char;
                    }
                } else if ( real_char in tilde_chars ) {
                    assembled.push(real_char);
                } else {
                    assembled.push(cur_p);
                }
            } else if (in_group) {
                bracket_args += cur_p;
            } else {
                assembled.push(cur_p);
            }
        }

        if (in_group) {
            throw "Invalid maketext string: " + str; // ## no extract maketext
        }

        return assembled.join("");
    };

    // Most of what is here ports functionality from CPAN Locale::Maketext::Utils.
    Locale.prototype = Object.create({

        /**
         * Initialized with the value stored in window.LEXICON if there is anything.
         * @type {Object} - where each key is the untranslated string and the value is the translated version
         * of that string in the current users selected locale.
         */
        LEXICON: (typeof window === "undefined") ?
            global.LEXICON || (global.LEXICON = {}) :
            window.LEXICON || (window.LEXICON = {}),

        /**
         * Use this method to localize a static string. These strings are harvested normally.
         *
         * @method maketext                                                                                         // ## no extract maketext
         * @param {String} template Template to process.
         * @param {...*}   [args]   Optional replacement arguments for the template.
         * @return {String}
         */
        maketext: _maketext, // ## no extract maketext

        /**
         * Like maketext() but does not lookup the phrase in the lexicon and compiles the phrase exactly as given.  // ## no extract maketext
         *
         * @note  In the current implementation this works just like maketext, but will need to be modified once we // ## no extract maketext
         * start doing lexicon lookups.
         *
         * @method maketext                                                                                         // ## no extract maketext
         * @param {String} template Template to process.
         * @param {...*}   [args]   Optional replacement arguments for the template.
         * @return {String}
         */
        makethis: _maketext,                                                                                       // ## no extract maketext

        /**
         * Use this method instead of maketext if you are passing a variable that contains the maketext template.   // ## no extract maketext
         *
         * @method makevar
         * @param {String} template Template to process.
         * @param {...*}   [args]   Optional replacement arguments for the template.
         * @return {String}
         * @example
         *
         * var translatable = LOCALE.translatable;                                                                  // ## no extract maketext
         * var template = translatable("What is this [numf,_1] thing.");                                            // ## no extract maketext
         * ...
         * var localized = LOCALE.makevar(template)
         *
         * or
         *
         * var template = LOCALE.translatable("What is this [numf,_1] thing.");                                     // ## no extract maketext
         * ...
         * var localized = LOCALE.makevar(template)
         *
         */
        makevar: _maketext, // this is a marker method that is ignored in phrase harvesting, but is functionally equivalent to maketext otherwise. // ## no extract maketext

        /**
         * Marks the phrase as translatable for the harvester.                                                      // ## no extract maketext
         *
         * @method translatable                                                                                     // ## no extract maketext
         * @param  {String} str Translatable string
         * @return {Strung}     Same string, this is just a marker function for the harvester
         */
        translatable: function(str) { // ## no extract maketext
            return str;
        },

        _locale_tag: null,

        /**
         * Get the language tag for this locale.
         * @return {[type]} [description]
         */
        get_language_tag: function() {
            return this._locale_tag;
        },

        /**
         * Returns an instance of Intl.Collator for the current locale.
         * @return {[type]} [description]
         */
        getCollator: function getCollator() {
            if (!this._collator) {
                var localeTag = this.get_language_tag();

                try {
                    this._collator = new Intl.Collator(localeTag);
                } catch (e) {
                    // eslint-disable-next-line no-console
                    console.info("Failed to create collator for locale: " + localeTag + "; falling back to “en”", e);

                    this._collator = new Intl.Collator("en");
                }
            }

            return this._collator;
        },

        // These methods are locale-independent and should not need overrides.

        /**
         * Join a list with the provided separator.
         * @param  {[type]} sep  [description]
         * @param  {[type]} list [description]
         * @return {[type]}      [description]
         * @example
         *
         *  LOCALE.maketext("We have [join,,,_1].", ["fruit", "nuts", "raisins"]);  // ## no extract maketext
         */
        join: function(sep, list) {
            sep = String(sep);

            if ( typeof list === "object" ) {
                return list.join(sep);
            } else {
                var str = String(arguments[1]);
                for (var a = 2; a < arguments.length; a++) {
                    str += sep + arguments[a];
                }
                return str;
            }
        },

        /**
         * Boolean operator.
         * Perl has undef, but JavaScript has both null *and* undefined.
         * Let's treat null as undefined since JSON doesn't know what
         * undefined is, so serializers use null instead.
         * @param  {Boolean} condition  [description]
         * @param  {String} when_true  String to write when condition is true
         * @param  {String} when_false String to write when condition is false
         * @param  {String} [when_null]  String to write when condition is null or undefined
         * @return {String}
         * @example
         *
         *  LOCALE.maketext("We have [boolean,_1,a,no] banana.", bananas); // ## no extract maketext
         */
        "boolean": function(condition, when_true, when_false, when_null) {
            if (condition) {
                return "" + when_true;
            }

            if ( ((arguments.length > 3) && (condition === null || condition === undefined)) ) {
                return "" + when_null;
            }

            return "" + when_false;
        },

        /**
         * Comment operator
         * @return {String} Returns nothing
         * @example
         *
         *  LOCALE.maketext("We have only bananas. [comment,This does nothing]"); // ## no extract maketext
         */
        comment: function() {
            return "";
        },

        //

        /**
         * Output operator for bracket notation. Acts as "dispatch" function for the
         * output_* methods below.
         * @param  {String} sub_func Name of the output function to process
         * @param  {String} str      String to pass to the output function
         * @return {String}          Processed output.
         */
        output: function( sub_func, str ) {
            var that = this;

            var sub_args = Array.prototype.concat.apply([], arguments).slice(1);

            // Implementation of the chr() and amp() embeddable methods
            if ( sub_args && typeof sub_args[0] === "string" ) {
                sub_args[0] = sub_args[0].replace(/chr\((\d+|\S)\)/g, function(str, p1) {
                    return that.output_chr(p1);
                });
                sub_args[0] = sub_args[0].replace(/amp\(\)/g, function(str) {
                    return that.output_amp();
                });
            }

            var func_name = "output_" + sub_func;
            if ( typeof this[func_name] === "function" ) {
                return this[func_name].apply(this, sub_args);
            } else {
                if (window.console) {
                    window.console.warn("Locale output function \"" + sub_func + "\" is not implemented.");
                }
                return str;
            }
        },

        /**
         * Output an HTML safe apostrophe
         * @return {String}
         */
        output_apos: function() {
            return html_apos;
        },

        /**
         * Output an HTML safe quote mark
         * @return {String}
         */
        output_quot: function() {
            return html_quot;
        },

        // TODO: Implement embeddable methods described at
        // https://metacpan.org/pod/Locale::Maketext::Utils#asis()
        output_asis: String,
        asis: String,

        /**
         * Output the string wrapped in a <u> HTML tag
         * @param  {String} str
         * @return {String}
         */
        output_underline: function(str) {
            return "<u>" + str + "</u>";
        },

        /**
         * Output the string wrapped in a <strong> HTML tag
         * @param  {String} str
         * @return {String}
         */
        output_strong: function(str) {
            return "<strong>" + str + "</strong>";
        },

        /**
         * Output the string wrapped in a <em> HTML tag
         * @param  {String} str
         * @return {String}
         */
        output_em: function(str) {
            return "<em>" + str + "</em>";
        },

        /**
         * Output the string wrapped in a <abbr> HTML tag
         * @param  {String} abbr Abbreviation
         * @param  {String} full Full version of the abbreviation
         * @return {String}
         */
        output_abbr: function(abbr, full) {
            return "<abbr title=\"__FULL__\">".replace(/__FULL__/, full) + abbr + "</abbr>";
        },

        /**
         * Output the string wrapped in a <abbr> HTML tag with special markings
         * @param  {String} abbr Acronym
         * @param  {String} full Full version of the acronym
         * @return {String}
         */
        output_acronym: function(abbr, full) {

            // TODO: Is this still right with bootstrap???
            return this.output_abbr(abbr, full).replace(/^(<[a-z]+)/i, "$1 class=\"initialism\"");
        },

        /**
         * Output the string wrapped in a <span> HTML tag with the provided classes
         * @param {String} str String to embed in the span.
         * @param {String...} list of classes as arguments.
         * @return {[type]}     [description]
         */
        output_class: function(str) {
            var classes = Array.prototype.slice.call( arguments, 1 );
            return "<span class=\"" + classes.join(" ") + "\">" + str + "</span>";
        },

        /**
         * Output the requested character encoded as an HTML character.
         * @param  {Number} num Character code to output.
         * @return {String}
         */
        output_chr: function(num) {
            return isNaN(+num) ? String(num) : _.escape(String.fromCharCode(num));
        },

        /**
         * Output the HTML escaped version of an ampersand.
         * @return {String}
         */
        output_amp: function() {
            return html_amp;
        },

        /**
         * Output a url from the input. There are multiple forms possible:
         *  A) output_url( dest, text, [ config_obj ] )
         *  B) output_url( dest, text, [ key1, val1, [...] ] )
         *  C) output_url( dest, [ config_obj ] )
         *  D) output_url( dest, [ key1, val1, [...] ] )
         * @param  {String} dest Url to link the results too.
         * @return {String}
         */
        output_url: function(dest) {
            var
                args_length = arguments.length,
                config = arguments[args_length - 1],
                text,
                key,
                value,
                start_i,
                a,
                len;

            // object properties hash, form A or C
            if ( typeof config === "object" ) {
                text = (args_length === 3) ? arguments[1] : (config.html || dest);

                // Go ahead and clobber other stuff.
                if ( "_type" in config && config._type === "offsite" ) {
                    config["class"] = "offsite";
                    config.target = "_blank";
                    delete config._type;
                }
            } else {
                config = {};

                if (args_length % 2) {
                    start_i = 1;
                } else {
                    text = arguments[1];
                    start_i = 2;
                }
                a = start_i;
                len = arguments.length;
                while ( a < len ) {
                    key = arguments[a];
                    value = arguments[++a];
                    if (key === "_type" && value === "offsite") {
                        config.target = "_blank";
                        config["class"] = "offsite";
                    } else {
                        config[key] = value;
                    }
                    a++;
                }

                if (!text) {
                    text = config.html || dest;
                }
            }

            var html = "<a href=\"" + dest + "\"";
            if ( typeof config === "object" ) {
                for (key in config) {
                    if (config.hasOwnProperty(key)) {
                        html += " " + key + "=\"" + config[key] + "\"";
                    }
                }
            }
            html += ">" + text + "</a>";

            return html;
        },


        // Flattening argument lists in JS is much hairier than in Perl,
        // so this doesn't flatten array objects. Hopefully CLDR will soon
        // implement list_or; then we could deprecate this function.
        // cf. http://unicode.org/cldr/trac/ticket/4051
        list_separator: ", ",
        oxford_separator: ",",
        list_default_and: "&",


        /**
         * Maketext list operator
         * @param  {String} word Type of list to process. Examples are 'and' and 'or'.
         * @return {[type]}      [description]
         */
        list: function(word /* , [foo,bar,...] | foo, bar, ... */) {
            if (!word) {
                word = this.list_default_and;  // copying our Perl
            }
            var list_sep   = this.list_separator;
            var oxford_sep = this.oxford_separator;

            var the_list;
            if (typeof arguments[1] === "object" && arguments[1] instanceof Array) {
                the_list = arguments[1];
            } else {
                the_list = Array.prototype.concat.apply([], arguments).slice(1);
            }

            var len = the_list.length;

            if (!len) {
                return "";
            }

            if (len === 1) {
                return String(the_list[0]);
            } else if (len === 2) {
                return (the_list[0] + " " + word + " " + the_list[1]);
            } else {

                // Use slice() here to avoid altering the array
                // since it may have been passed in as an object.
                return (the_list.slice(0, -1).join(list_sep) + [oxford_sep, word, the_list.slice(-1)].join(" "));
            }
        },


        /**
         * Formats bytes with the specific decimal places.
         * This depends on locale-specific overrides of base functionality
         * but should not itself need an override.
         * @param  {[type]} bytes          [description]
         * @param  {[type]} decimal_places [description]
         * @return {[type]}                [description]
         */
        format_bytes: function(bytes, decimal_places) {

            if ( decimal_places === undefined ) {
                decimal_places = 2;
            }

            bytes = Number(bytes);

            var exponent = bytes && Math.min( Math.floor( Math.log(bytes) / Math.log(1024) ), data_abbreviations.length );
            if ( !exponent ) {

                // This is a special, internal-to-format_bytes, phrase: developers will not have to deal with this phrase directly.
                return this.maketext( "[quant,_1,%s byte,%s bytes]", bytes ); // the space between the '%s' and the 'b' is a non-break space (e.g. option-spacebar, not spacebar)
                // We do not use &nbsp; or \u00a0 since:
                //   * parsers would need to know how to interpolate them in order to work with the phrase in the context of the system
                //   * the non-breaking space character behaves as you'd expect its various representations to.
                // Should a second instance of this sort of thing happen we can revisit the idea of adding [comment] in the phrase itself or perhaps supporting an embedded call to [output,nbsp].
            } else {

                // We use \u00a0 here because it won't affect lookup since it is not
                // being used in a source phrase and we don't want to worry about
                // whether an entity is going to be interpreted or not.
                return this.numf(bytes / Math.pow(1024, exponent), decimal_places) + "\u00a0" + data_abbreviations[exponent - 1];
            }
        },

        // CLDR-informed functions

        /**
         * Maketext numerate operator
         * @param  {Number} num Quantity to numerate.
         * @return {String}
         */
        numerate: function(num) {
            if ( this.get_plural_form ) {   // from CPAN Locales
                var numerated = this.get_plural_form.apply(this, arguments)[0];
                if (numerated === undefined) {
                    numerated = arguments[arguments.length - 1];
                }
                return numerated;
            } else {

                // English-language logic, in the absence of CLDR
                // The -1 case here is debatable.
                // cf. http://unicode.org/cldr/trac/ticket/4049
                var abs = Math.abs(num);

                if (abs === 1) {
                    return "" + arguments[1];
                } else if (abs === 0) {
                    return "" + arguments[ arguments.length - 1 ];
                } else {
                    return "" + arguments[2];
                }
            }
        },

        /**
         * Maketext quant operator..
         * @param  {Number} num Quantity on which the output depends.
         * @return {[type]}     [description]
         */
        quant: function(num) {
            var numerated,
                is_special_zero,
                decimal_places = 3;

            if ( num instanceof Array ) {
                decimal_places = num[1];
                num = num[0];
            }

            if ( this.get_plural_form ) {

                // from CPAN Locales
                var gpf = this.get_plural_form.apply(this, arguments);
                numerated = gpf[0];

                // If there's a mismatch between the actual number of forms
                // (singular, plural, etc.) and the real number, this can be
                // undefined, which can break code.  We pick the rightmost, or
                // "most plural," form as a fallback.
                if (numerated === undefined) {
                    numerated = arguments[arguments.length - 1];
                }
                is_special_zero = gpf[1];
            } else {

                // no CLDR, fall back to English
                numerated = this.numerate.apply(this, arguments);

                // Check: num is 0, we gave a special_zero value, and that numerate() gave it
                is_special_zero = (parseInt(num, 10) === 0) &&
                    ( arguments.length > 3 ) &&
                    ( numerated === String(arguments[3]) )
                ;
            }
            var formatted = this.numf(num, decimal_places);

            if (numerated.indexOf("%s") !== -1) {
                return numerated.replace(/%s/g, formatted);
            }

            if (is_special_zero) {
                return numerated;
            }

            return this.is_rtl() ? (numerated + " " + formatted) : (formatted + " " + numerated);
        },

        _max_decimal_places: 6,

        /**
         * [numf description]
         * @param  {[type]} num            [description]
         * @param  {[type]} decimal_places [description]
         * @return {[type]}                [description]
         */
        numf: function(num, decimal_places) {
            if ( decimal_places === undefined ) {
                decimal_places = this._max_decimal_places;
            }

            // exponential -> don't know how to deal
            if (/e/.test(num)) {
                return String(num);
            }

            var cldr, decimal_format, decimal_group, decimal_decimal;
            try {
                cldr = this.get_cldr("misc_info").cldr_formats;
                decimal_format = cldr.decimal;
                decimal_group = cldr._decimal_format_group;
                decimal_decimal = cldr._decimal_format_decimal;
            } catch (e) {}

            // No CLDR, so fall back to hard-coded English values.
            if (!decimal_format || !decimal_group || !decimal_decimal) {
                decimal_format = "#,##0.###";
                decimal_group = ",";
                decimal_decimal = ".";
            }

            var is_negative = num < 0;
            num = Math.abs(num);

            // Trim the decimal part to 6 digits and round
            var whole = Math.floor(num);
            var normalized, fraction;
            if ( /(?!')\.(?!')/.test(num) ) {

                // This weirdness is necessary to avoid floating-point
                // errors that can crop up with large-ish numbers.

                // Convert to a simple fraction.
                fraction = String(num).replace(/^[^.]+/, "0");

                // Now round to the desired precision.
                fraction = Number(fraction).toFixed(decimal_places);

                // e.g., 1.9999 when only 3 decimal places are desired.
                if (/^1/.test(fraction)) {
                    whole++;
                    num = whole;
                    fraction = undefined;
                    normalized = num;
                } else {
                    fraction = fraction.replace(/^.*\./, "").replace(/0+$/, "");
                    normalized = Number( whole + "." + fraction );
                }
            } else {
                normalized = num;
            }

            var pattern_with_outside_symbols;
            if ( /(?!');(?!')/.test(decimal_format) ) {
                pattern_with_outside_symbols = decimal_format.split(/(?!');(?!')/)[ is_negative ? 1 : 0 ];
            } else {
                pattern_with_outside_symbols = (is_negative ? "-" : "") + decimal_format;
            }

            var inner_pattern = pattern_with_outside_symbols.match(/[0#].*[0#]/)[0];

            // Applying the integer part of the pattern is much easier if it's
            // done with the strings reversed.
            var pattern_split = inner_pattern.split(/(?!')\.(?!')/);
            var int_pattern_split = pattern_split[0].split("").reverse().join("").split(/(?!'),(?!')/);

            // If there is only one part of the int pattern, then set the "joiner"
            // to empty string. (http://unicode.org/cldr/trac/ticket/4094)
            var group_joiner;
            if (int_pattern_split.length === 1) {
                group_joiner = "";
            } else {

                // Most patterns look like #,##0.###, for which the leftmost # is
                // just a placeholder so we know where to put the group separator.
                int_pattern_split.pop();
                group_joiner = decimal_group;
            }

            var whole_reverse = String(whole).split("").reverse();
            var whole_assembled = [];  // reversed
            var pattern;
            var replacer = function(chr) {
                switch (chr) {
                    case "#":
                        return whole_reverse.shift() || "";
                    case "0":
                        return whole_reverse.shift() || "0";
                }
            };
            while ( whole_reverse.length ) {
                if ( int_pattern_split.length ) {
                    pattern = int_pattern_split.shift();
                }

                // Since this is reversed, we can just replace a character
                // at a time, in regular forward order. Make sure we leave quoted
                // stuff alone while paying attention to stuff *by* quoted stuff.
                var assemble_chunk = pattern
                    .replace(/(?!')[0#]|[0#](?!')/g, replacer )
                    .replace(/'([.,0#;¤%E])'$/, "")
                    .replace(/'([.,0#;¤%E])'/, "$1")
                ;

                whole_assembled.push(assemble_chunk);
            }

            var formatted_num = whole_assembled.join(group_joiner).split("").reverse().join("") + ( fraction ? decimal_decimal + fraction : "" );
            return pattern_with_outside_symbols.replace(/[0#].*[0#]/, formatted_num);
        },

        // This *may* be useful publicly.
        _quote: function(str) {
            var delimiters;
            try {
                delimiters = this.get_cldr("misc_info").delimiters;
            } catch (e) {
                delimiters = {
                    quotation_start: "“",
                    quotation_end: "”"
                };
            }
            return delimiters["quotation_start"] + str + delimiters["quotation_end"];
        },

        /**
         * Quotes each value and then returns a localized “and”-list of them.
         *
         * Accepts either a list of arguments or a single array of arguments.
         *
         * @return {String} The localized list of quoted items.
         */
        list_and_quoted: function() {
            return this._list_quoted("list_and", arguments);
        },

        /**
         * Quotes each value and then returns a localized “and”-list of them.
         *
         * Accepts either a list of arguments or a single array of arguments.
         *
         * @return {String} The localized list of quoted items.
         */
        list_or_quoted: function() {
            return this._list_quoted("list_or", arguments);
        },

        _list_quoted: function(join_fn, args) {
            var the_list;
            if (typeof (args[0]) === "object") {
                if (args[0] instanceof Array) {

                    // slice() so that we don’t change the caller’s data
                    the_list = args[0].slice();
                } else {
                    throw ( "Unrecognized list_and_quoted() argument: " + args[0].toString() );
                }
            } else {
                the_list = Array.prototype.slice.apply(args);
            }

            // Emulate Locales.pm _quote_get_list_items() list_quote_mode 'all'.
            // list_or(), currently not implemented in JS (no reason for it not to be), will need to behave the same
            if (the_list === undefined || the_list.length === 0) {

                the_list = [""]; // disambiguate no args
            }

            // The CJT1 code actually writes out the list_and() logic again.
            // There doesn’t seem to be a good reason for that … ??
            return this[join_fn](the_list.map( _.bind(this._quote, this) ) );
        },

        /**
         * [list_and description]
         * @return {[type]} [description]
         */
        list_and: function() {
            return this._list_join_cldr("list", arguments);
        },

        list_or: function() {
            return this._list_join_cldr("list_or", arguments);
        },


        _list_join_cldr: function(templates_name, args) {
            var the_list;
            if ( (typeof args[0] === "object") && args[0] instanceof Array ) {
                the_list = args[0];
            } else {
                the_list = args;
            }

            var cldr_list;
            var len = the_list.length;
            var pattern;
            var text;

            try {
                cldr_list = this.get_cldr("misc_info").cldr_formats[templates_name];
            } catch (e) {

                // Use hard-coded English below if we don't have CLDR.

                var conjunction = (templates_name === "list_or") ? "or" : "and";

                cldr_list = {
                    2: "{0} " + conjunction + " {1}",
                    start: "{0}, {1}",
                    middle: "{0}, {1}",
                    end: "{0}, " + conjunction + " {1}",
                };
            }

            var replacer = function(str, p1) {
                switch (p1) {
                    case "0":
                        return text;
                    case "1":
                        return the_list[i++];
                }
            };

            switch (len) {
                case 0:
                    return;
                case 1:
                    return String(the_list[0]);
                default:
                    if ( len === 2 ) {
                        text = cldr_list["2"];
                    } else {
                        text = cldr_list.start;
                    }

                    text = text.replace(/\{([01])\}/g, function(all, bit) {
                        return the_list[bit];
                    });
                    if (len === 2) {
                        return text;
                    }

                    var i = 2;
                    while ( i < len ) {
                        pattern = cldr_list[ (i === len - 1) ? "end" : "middle" ];

                        text = pattern.replace(/\{([01])\}/g, replacer );
                    }

                    return text;
            }
        },

        /**
         * [_apply_quote_types description]
         * @param  {[type]} quotee    [description]
         * @param  {[type]} starttype [description]
         * @param  {[type]} endtype   [description]
         * @return {[type]}           [description]
         */
        _apply_quote_types: function( quotee, starttype, endtype ) {
            if (quotee === undefined) {
                return;
            }

            var delimiters = this.get_cldr().misc_info.delimiters;

            return delimiters[starttype] + quotee + delimiters[endtype];
        },

        /**
         * [quote description]
         * @param  {[type]} quotee [description]
         * @return {[type]}        [description]
         */
        quote: function( quotee ) {
            return this._apply_quote_types( quotee, "quotation_start", "quotation_end" );
        },

        /**
         * [alt_quote description]
         * @param  {[type]} quotee [description]
         * @return {[type]}        [description]
         */
        alt_quote: function( quotee ) {
            return this._apply_quote_types( quotee, "alternate_quotation_start", "alternate_quotation_end" );
        },

        /**
         * [_quote_list description]
         * @param  {[type]} quote_method [description]
         * @param  {[type]} list_method  [description]
         * @param  {[type]} items_obj    [description]
         * @return {[type]}              [description]
         */
        _quote_list: function( quote_method, list_method, items_obj ) {
            if ( (typeof items_obj[0] === "object") && (items_obj[0] instanceof Array) ) {
                items_obj = items_obj[0];
            }

            var quoted = [];
            for (var i = items_obj.length - 1; i >= 0; i--) {
                quoted[i] = this[quote_method]( items_obj[i] );
            }

            return this[list_method]( quoted );
        },

        /**
         * [quote_list_and description]
         * @return {[type]} [description]
         */
        quote_list_and: function() {
            return this._quote_list( "quote", "list_and", arguments );
        },

        /**
         * [alt_quote_list_and description]
         * @return {[type]} [description]
         */
        alt_quote_list_and: function() {
            return this._quote_list( "alt_quote", "list_and", arguments );
        },

        /* NOT IMPLEMENTED, pending a list_or() implementation
        quote_list_or : function( items ) {
            return this._quote_list( "quote", "list_or", items );
        },

        alt_quote_list_or : function( items ) {
            return this._quote_list( "alt_quote", "list_or", items );
        },
        */

        /**
         * [local_datetime description]
         * @param  {[type]} my_date       [description]
         * @param  {[type]} format_string [description]
         * @return {[type]}               [description]
         */
        local_datetime: function( my_date, format_string ) {
            if (!this._cldr) {
                return this.datetime.apply(this, arguments);
            }

            if ( my_date instanceof Date ) {
                my_date = new Date(my_date);
            } else if ( /^-?\d+$/.test(my_date) ) {
                my_date = new Date(my_date * 1000);
            } else {
                my_date = new Date();
            }

            var tz_offset = my_date.getTimezoneOffset();

            my_date.setMinutes( my_date.getMinutes() - tz_offset );

            var non_utc = this.datetime( my_date, format_string );

            // This is really hackish...but should be safe.
            if ( non_utc.indexOf("UTC") > -1 ) {
                var hours = (tz_offset > 0) ? "-" : "+";
                hours += _.padStart(Math.floor(Math.abs(tz_offset) / 60).toString(), 2, "0");
                var minutes = _.padStart((tz_offset % 60).toString(), 2, "0");
                non_utc = non_utc.replace("UTC", "GMT" + hours + minutes);
            }

            return non_utc;
        },

        // time can be either epoch seconds or a JS Date object
        // format_string can match the regexp below or be a [ date, time ] suffix pair
        // (e.g., [ "medium", "short" ] -> "Aug 30, 2011 5:12 PM")

        /**
         * Format dates according to CLDR.
         * This logic should stay in sync with Cpanel::Date::Format in Perl.
         *
         * @param  {[type]} my_date       [description]
         * @param  {[type]} format_string [description]
         * @return {[type]}               [description]
         */
        datetime: function datetime( my_date, format_string ) {
            if ( !my_date && (my_date !== 0) ) {
                my_date = new Date();
            } else if ( !(my_date instanceof Date) ) {
                my_date = new Date(my_date * 1000);
            }

            var loc_strs = this.get_cldr("datetime");

            if ( !loc_strs ) {
                return my_date.toString();
            }

            if ( format_string ) {

                // Make sure we don't just grab any random CLDR datetime key.
                if ( /^(?:date|time|datetime|special)_format_/.test(format_string) ) {
                    format_string = loc_strs[format_string];
                }
            } else {
                format_string = loc_strs.date_format_long;
            }

            /**
             * [substituter description]
             * @return {[type]} [description]
             */
            var substituter = function() {

                // Check for quoted strings
                if (arguments[1]) {
                    return arguments[1].substr( 1, arguments[1].length - 2 );
                }

                // No quoted string, eh? OK, let’s check for a known pattern.
                var key = arguments[2];
                var xformed = ( function() {
                    switch (key) {
                        case "yy":
                            return Math.abs(my_date.getUTCFullYear()).toString().slice(-2);
                        case "y":
                        case "yyy":
                        case "yyyy":
                            return Math.abs(my_date.getUTCFullYear());
                        case "MMMMM":
                            return loc_strs.month_format_narrow[my_date.getUTCMonth()];
                        case "LLLLL":
                            return loc_strs.month_stand_alone_narrow[my_date.getUTCMonth()];
                        case "MMMM":
                            return loc_strs.month_format_wide[my_date.getUTCMonth()];
                        case "LLLL":
                            return loc_strs.month_stand_alone_wide[my_date.getUTCMonth()];
                        case "MMM":
                            return loc_strs.month_format_abbreviated[my_date.getUTCMonth()];
                        case "LLL":
                            return loc_strs.month_stand_alone_abbreviated[my_date.getUTCMonth()];
                        case "MM":
                        case "LL":
                            return _.padStart((my_date.getUTCMonth() + 1).toString(), 2, "0");
                        case "M":
                        case "L":
                            return my_date.getUTCMonth() + 1;
                        case "EEEE":
                            return loc_strs.day_format_wide[ get_cldr_day(my_date) ];
                        case "EEE":
                        case "EE":
                        case "E":
                            return loc_strs.day_format_abbreviated[ get_cldr_day(my_date) ];
                        case "EEEEE":
                            return loc_strs.day_format_narrow[ get_cldr_day(my_date) ];
                        case "cccc":
                            return loc_strs.day_stand_alone_wide[ get_cldr_day(my_date) ];
                        case "ccc":
                        case "cc":
                        case "c":
                            return loc_strs.day_stand_alone_abbreviated[ get_cldr_day(my_date) ];
                        case "ccccc":
                            return loc_strs.day_stand_alone_narrow[ get_cldr_day(my_date) ];
                        case "dd":
                            return _.padStart(my_date.getUTCDate().toString(), 2, "0");
                        case "d":
                            return my_date.getUTCDate();
                        case "h":
                        case "hh":
                            var twelve_hours = my_date.getUTCHours();
                            if ( twelve_hours > 12 ) {
                                twelve_hours -= 12;
                            }
                            if ( twelve_hours === 0 ) {
                                twelve_hours = 12;
                            }
                            return ( key === "hh" ) ? _.padStart(twelve_hours.toString(), 2, "0") : twelve_hours;
                        case "H":
                            return my_date.getUTCHours();
                        case "HH":
                            return _.padStart(my_date.getUTCHours().toString(), 2, "0");
                        case "m":
                            return my_date.getUTCMinutes();
                        case "mm":
                            return _.padStart(my_date.getUTCMinutes().toString(), 2, "0");
                        case "s":
                            return my_date.getUTCSeconds();
                        case "ss":
                            return _.padStart(my_date.getUTCSeconds().toString(), 2, "0");
                        case "a":
                            var hours = my_date.getUTCHours();
                            if (hours < 12) {
                                return loc_strs.am_pm_abbreviated[0];
                            } else if ( hours > 12 ) {
                                return loc_strs.am_pm_abbreviated[1];
                            }

                            // CLDR defines "noon", but CPAN DateTime::Locale doesn't have it.
                            return loc_strs.am_pm_abbreviated[1];
                        case "z":
                        case "zzzz":
                        case "v":
                        case "vvvv":
                            return "UTC";
                        case "G":
                        case "GG":
                        case "GGG":
                            return loc_strs.era_abbreviated[ my_date.getUTCFullYear() < 0 ? 0 : 1 ];
                        case "GGGGG":
                            return loc_strs.era_narrow[ my_date.getUTCFullYear() < 0 ? 0 : 1 ];
                        case "GGGG":
                            return loc_strs.era_wide[ my_date.getUTCFullYear() < 0 ? 0 : 1 ];
                    }

                    if (window.console) {
                        // eslint-disable-next-line no-console
                        console.warn("Unknown CLDR date/time pattern: " + key + " (" + format_string + ")" );
                    }
                    return key;
                } )();

                return xformed;
            };

            return format_string.replace(
                /('[^']+')|(([a-zA-Z])\3*)/g,
                substituter
            );
        },

        /**
         * [is_rtl description]
         * @return {Boolean} [description]
         */
        is_rtl: function() {
            try {
                return this.get_cldr("misc_info").orientation.characters === "right-to-left";
            } catch (e) {
                return false;
            }
        },

        /**
        * Shorten a string into one or two end fragments, using CLDR formatting.
        *
        * ex.: elide( "123456", 2 )    //"12…"
        * ex.: elide( "123456", 2, 2 ) //"12…56"
        * ex.: elide( "123456", 0, 2 ) //"…56"
        *
        * @param str     {String} The actual string to shorten.
        * @param start_length {Number} How many initial characters to put into the result.
        * @param end_length {Number} How many final characters to put into the result. (optional)
        * @return        {String} The processed string.
        */
        elide: function(str, start_length, end_length) {
            start_length = start_length || 0;
            end_length = end_length || 0;

            if (str.length <= (start_length + end_length)) {
                return str;
            }

            var template, substring0, substring1;
            if (start_length) {
                if (end_length) {
                    template = "medial";
                    substring0 = str.substr(0, start_length);
                    substring1 = str.substr( str.length - end_length );
                } else {
                    template = "final";
                    substring0 = str.substr(0, start_length);
                }
            } else if (end_length) {
                template = "initial";
                substring0 = str.substr( str.length - end_length );
            } else {
                return "";
            }

            try {
                template = this._cldr.misc_info.cldr_formats.ellipsis[template]; // JS reserved word
            } catch (e) {
                template = DEFAULT_ELLIPSIS[template];
            }

            if (substring1) {   // medial
                return template
                    .replace( "{0}", substring0 )
                    .replace( "{1}", substring1 )
                ;
            }

            return template.replace( "{0}", substring0 );
        },

        /**
         * [get_first_day_of_week description]
         * @return {[type]} [description]
         */
        get_first_day_of_week: function() {
            var fd = Number(this.get_cldr("datetime").first_day_of_week) + 1;
            return (fd === 8) ? 0 : fd;
        },

        /**
         * [set_cldr description]
         * @param {[type]} cldr [description]
         */
        set_cldr: function(cldr) {
            var cldr_obj = this._cldr;
            if ( !cldr_obj ) {
                cldr_obj = this._cldr = {};
            }
            for (var key in cldr) {
                if (cldr.hasOwnProperty(key)) {
                    cldr_obj[key] = cldr[key];
                }
            }
        },

        /**
         * [get_cldr description]
         * @param  {[type]} key [description]
         * @return {[type]}     [description]
         */
        get_cldr: function(key) {
            if ( !this._cldr ) {
                return;
            }

            if ((typeof key === "object") && (key instanceof Array)) {
                return key.map(this.get_cldr, this);
            } else {
                return key ? this._cldr[key] : this._cldr;
            }
        },

        /**
         * For testing. Don't "delete" since this will cause prototype traversal.
         * @return {[type]} [description]
         */
        reset_cldr: function() {
            this._cldr = undefined;
        },

        _cldr: null
    });

    // Annotate the class hierarchy for introspection.
    Locale.prototype.constructor = Locale;
    Locale.prototype.parent = Object;

    Locale.generateClassFromCldr = function(tag, cldr) {

        // Create a custom class for the locale generated from the CLDR data.
        var GeneratedLocale = function() {
            GeneratedLocale.prototype.parent.apply(this, arguments);
            this.set_cldr( { datetime: cldr.datetime_info } );
            this.set_cldr( { misc_info: cldr.misc_info } );
        };

        GeneratedLocale.prototype = new Locale();

        // Annotate the class hierarchy for introspection.
        GeneratedLocale.prototype.constructor = GeneratedLocale;
        GeneratedLocale.prototype.parent = Locale;

        // Mix in the the CLDR locale functions into the new class.
        for (var key in cldr.functions) {
            if ( cldr.functions.hasOwnProperty(key)) {
                GeneratedLocale.prototype[key] = cldr.functions[key];
            }
        }

        // Add the new locale class to the collection
        Locale.add_locale(tag, GeneratedLocale);
    };

    var tag;
    if (window.CJT2_loader && window.CJT2_loader.CLDR && window.CJT2_loader.current_locale) {
        tag = window.CJT2_loader.current_locale;
        Locale.generateClassFromCldr(tag, window.CJT2_loader.CLDR[tag]);
    }

    return Locale.get_handle(tag);
});
