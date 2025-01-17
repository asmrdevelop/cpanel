//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/base/frontend/jupiter/mail/boxtrapper/conf.js
// Generated: /usr/local/cpanel/base/frontend/jupiter/mail/boxtrapper/conf-vi.js
// Module:    /jupiter/mail/boxtrapper/conf-vi
// Locale:    vi
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Minimum [asis,Apache] [asis,SpamAssassin] Spam Score required to bypass [asis,BoxTrapper]:":"Điểm Thư Rác [asis,Apache] [asis,SpamAssassin] tối thiểu bắt buộc để vượt qua [asis,BoxTrapper]:","The minimum spam score must be numeric.":"Điểm thư rác tối đa phải là số.","The number of days that you wish to keep logs and messages in the queue:":"Số lượng ngày muốn giữ nhật ký và thư trong hàng đợi:","The number of days to keep logs must be a positive integer.":"Số lượng ngày duy trì nhật ký phải là số nguyên dương."};

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
