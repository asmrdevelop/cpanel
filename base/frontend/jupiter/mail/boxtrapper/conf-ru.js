//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/frontend/jupiter/mail/boxtrapper/conf.js
// Generated: /usr/local/cpanel/base/frontend/jupiter/mail/boxtrapper/conf-ru.js
// Module:    /jupiter/mail/boxtrapper/conf-ru
// Locale:    ru
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Minimum [asis,Apache] [asis,SpamAssassin] Spam Score required to bypass [asis,BoxTrapper]:":"Minimum [asis,Apache] [asis,SpamAssassin] Spam Score required to bypass [asis,BoxTrapper]:","The minimum spam score must be numeric.":"Минимальный показатель спама должен быть числом.","The number of days that you wish to keep logs and messages in the queue:":"Количество дней, в течение которых вы хотите сохранять журналы и сообщения в очереди:","The number of days to keep logs must be a positive integer.":"Количество дней для хранения журналов должно быть положительным целым числом."};

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
