//~~GENERATED~~
//-------------------------------------------------------------
// Source:    /usr/local/cpanel/share/libraries/cjt2/src/validator/length-validators.js
// Generated: /usr/local/cpanel/share/libraries/cjt2/src/validator/length-validators-vi.js
// Module:    cjt/validator/length-validators-vi
// Locale:    vi
// This file is generated by the cpanel localization system
// using the bin/_build_translated_js_hash_files.pl script.
//-------------------------------------------------------------
// !!! Do not hand edit this file !!!
//-------------------------------------------------------------
(function() {
    // The raw lexicon.
    var newLex = {"Select at least [quant,_1,item,items] from the list.":"Chọn ít nhất [quant,_1,mục,mục] từ danh sách.","The length of the string cannot be greater than [quant,_1,character,characters].":"Chiều dài của xâu không được lớn hơn [quant,_1,ký tự,ký tự].","The length of the string cannot be less than [quant,_1,character,characters].":"Chiều dài của xâu không được nhỏ hơn [quant,_1,ký tự,ký tự].","The length of the string should be [quant,_1,character,characters,zero].":"Chiều dài của xâu phải là [quant,_1,ký tự,ký tự,không].","This string is too long or complex. Shorten it, or replace complex (non-[asis,ASCII]) characters with simple ([asis,ASCII]) ones. (The string’s [asis,UTF-8] encoding cannot exceed [quant,_1,byte,bytes].)":"This string is too long or complex. Shorten it, or replace complex (non-[asis,ASCII]) characters with simple ([asis,ASCII]) ones. (The string’s [asis,UTF-8] encoding cannot exceed [quant,_1,byte,bytes].)"};

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
