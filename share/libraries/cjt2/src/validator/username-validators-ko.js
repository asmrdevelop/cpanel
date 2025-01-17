//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/share/libraries/cjt2/src/validator/username-validators.js
// Generated: /usr/local/cpanel/share/libraries/cjt2/src/validator/username-validators-ko.js
// Module:    cjt/validator/username-validators-ko
// Locale:    ko
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"The user name should only contain the following characters: [asis,a-zA-Z0-9-].":"사용자 이름에는 다음과 같은 문자만 포함되어야 합니다. [asis,a-zA-Z0-9-].","User name cannot be longer than [quant,_1,character,characters].":"사용자 이름은 [quant,_1,자,자]보다 길 수 없습니다.","User name cannot be “[_1]”.":"사용자 이름은 “[_1]”일 수 없습니다."};

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
