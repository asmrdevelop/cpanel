//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/sharedjs/LogTail.js
// Generated: /usr/local/cpanel/base/sharedjs/LogTail-nb.js
// Module:    legacy_shared/LogTail-nb
// Locale:    nb
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Too many errors from “[_1]”. Future errors will be suppressed.":"For mange feil fra “[_1]“. Det tas ikke hensyn til fremtidige feil.","[asis,live_tail_log] encountered an internal error: [_1]":"Det oppstod en intern feil for [asis,live_tail_log]: [_1]","[asis,live_tail_log] encountered the maximum allowed errors ([numf,_1]) and will not continue.":"Maksimalt antall tillatte feil ([numf,_1]) har oppstått for [asis,live_tail_log], som avbrytes."};

    if (!this.LEXICON) {
        this.LEXICON = {};
    }

    for(var item in newLex) {
        if(newLex.hasOwnProperty(item)) {
            var value = newLex[item];
            if (typeof(value) === "string" && value !== "") {
                // Only add it if there is a value.
                this.LEXICON[item] = value;
            }
        }
    }
})();
//~~END-GENERATED~~
