//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/share/libraries/cjt2/src/validator/username-validators.js
// Generated: /usr/local/cpanel/share/libraries/cjt2/src/validator/username-validators-zh.js
// Module:    cjt/validator/username-validators-zh
// Locale:    zh
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The user name should only contain the following characters: [asis,a-zA-Z0-9-].":"用户名只能包含以下字符: [asis,a-zA-Z0-9-]。","User name cannot be longer than [quant,_1,character,characters].":"用户名不能超过 [quant,_1,个字符,个字符]。","User name cannot be “[_1]”.":"用户名不能为“[_1]”。"};

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